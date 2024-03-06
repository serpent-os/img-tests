#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2020-2023 Serpent OS Developers
#
# SPDX-License-Identifier: MPL-2.0
#
# Serpent OS prototype linux-desktop ISO image generator

die () {
    echo -e "$*"
    exit 1
}

# Root check
if [[ "${UID}" -ne 0 ]]; then
    die "\nThis script MUST be run as root.\n"
fi

# Add escape codes for color
RED='\033[0;31m'
RESET='\033[0m'

WORK="$(dirname $(realpath $0))"
echo ">>> workdir \${WORK}: ${WORK}"
TMPFS="/tmp/serpent_iso"
echo ">>> tmpfs dir \${TMPFS}: ${TMPFS}"

BINARIES=(
    fallocate
    mkfs.vfat
    mksquashfs
    moss
    moss-container
    mount
    sync
    xorriso
)
# up front check for necessary binaries
BINARY_NOT_FOUND=0
echo -e "\nChecking for necessary prerequisites..."
# 'all entries in the BINARIES array'
for b in ${BINARIES[@]}; do
    command -v ${b} > /dev/null 2>&1
    if [[ ! ${?} -eq 0 ]]; then
        echo -e "- ${b} ${RED}not found${RESET} in \$PATH."
        BINARY_NOT_FOUND=1
    else
        echo "- found ${b}"
    fi
done

if [[ ${BINARY_NOT_FOUND} -gt 0 ]]; then
    die "\nNecessary prerequisites not met, please install missing tool(s).\n"
else
    echo -e "\nAll necessary binaries found, generating Serpent OS linux-desktop ISO image...\n"
fi

# Pkg list check
test -f ${WORK}/pkglist || die "\nThis script MUST be run from within the desktop/ dir with the ./pkglist file.\n"
test -f ${WORK}/../pkglist-base || die "\nThis script MUST be able to find the ../pkglist-base file.\n"

# start with a common base of packages
readarray -t PACKAGES < ${WORK}/../pkglist-base

# add linux-desktop specific packages
PACKAGES+=($(cat ${WORK}/pkglist))

test -f ${WORK}/initrdlist || die "initrd package list is absent"
readarray -t initrd < ${WORK}/initrdlist

cleanup () {
    echo -e "\nCleaning up existing dirs, files and mount points...\n"
    # clean up dirs
    rm -rf ${TMPFS}/*

    # umount existing mount recursively and lazily
    test -d ${TMPFS}/* && umount -Rlv ${TMPFS}/*

    # clean leftover existing *.img
    test -e ${TMPFS}/*.img && rm -f ${TMPFS}/*.img
}
cleanup

die_and_cleanup() {
    cleanup
    die $*
}

# From here on, exit from script on any non-zero exit status command result
set -e

export BOOT="${TMPFS}/boot"
export CACHE="${WORK}/cached_stones"
export MOUNT="${TMPFS}/mount"
export SFSDIR="${TMPFS}/serpentfs"

# Use a permanent cache for downloaded .stones
mkdir -pv ${CACHE}

# Stash boot assets
mkdir -pv ${BOOT}

# Get it right first time.
mkdir -pv ${MOUNT} ${SFSDIR}
chown -Rc root:root ${MOUNT} ${SFSDIR}
# Only chmod directories
chmod -Rc u=rwX,g=rX,o=rX ${MOUNT} ${SFSDIR}

export RUST_BACKTRACE=1

export MOSS="moss -D ${SFSDIR} --cache ${CACHE}" 

echo ">>> Add moss volatile repository to ${SFSDIR}/ ..."
time ${MOSS} repo add volatile https://dev.serpentos.com/volatile/x86_64/stone.index || die_and_cleanup "Adding moss repo failed!"

echo ">>> Install packages to ${SFSDIR}/ ..."
time ${MOSS} install -y "${PACKAGES[@]}" || die_and_cleanup "Installing packages failed!"

echo ">>> Fix ldconfig in ${SFSDIR}/ ..."
mkdir -pv ${SFSDIR}/var/cache/ldconfig
time moss-container -u 0 -d ${SFSDIR} -- ldconfig

echo ">>> Set up basic environment in ${SFSDIR}/ ..."
time moss-container -u 0 -d ${SFSDIR} -- systemd-sysusers
time moss-container -u 0 -d ${SFSDIR} -- systemd-tmpfiles --create
time moss-container -u 0 -d ${SFSDIR} -- systemd-firstboot --force --setup-machine-id --delete-root-password --locale=en_US.UTF-8 --timezone=UTC --root-shell=/usr/bin/bash
time moss-container -u 0 -d ${SFSDIR} -- systemctl enable systemd-resolved systemd-networkd getty@tty1

echo ">>> Fix performance issues. Needs packaging/merging by moss"
time moss-container -u 0 -d ${SFSDIR} -- systemd-hwdb update

echo ">>> Extract assets..."
cp -av ${SFSDIR}/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${BOOT}/bootx64.efi
cp -av ${SFSDIR}/usr/lib/kernel/com.serpentos.* ${BOOT}/kernel

echo ">>> Install dracut in ${SFSDIR}/ ..."
time ${MOSS} install "${initrd[@]}" -y || die_and_cleanup "Failed to install initrd packages!"

echo ">>> Regenerate dracut..."
kver=$(ls ${SFSDIR}/usr/lib/modules)
time moss-container -u 0 -d ${SFSDIR}/ -- dracut --early-microcode --hardlink -N --nomdadmconf --nolvmconf --kver ${kver} --add "bash dash systemd lvm dm dmsquash-live" --fwdir /usr/lib/firmware --tmpdir /tmp --zstd --strip /initrd
mv -v ${SFSDIR}/initrd ${BOOT}/initrd

echo ">>> Clean up ${SFSDIR}/ ..."
time ${MOSS} remove "${initrd[@]}" -y || die_and_cleanup "Failed to remove initrd packages from ${TMPFS}/ !"
time ${MOSS} install -y "${PACKAGES[@]}" || die_and_cleanup "Installing packages failed!"

# Keep only latest state (= currently installed)
time ${MOSS} state prune -k1 -y || die_and_cleanup "Failed to prune moss state in ${TMPFS}/ !"
# Remove downloaded .stones to lower size of generated ISO
rm -rf ${SFSDIR}/.moss/cache/downloads/*

SFSSIZE=$(du -BMiB -s ${TMPFS}|cut -f1|sed -e 's|MiB||g')
echo ">>> ${SFSDIR} size: ${SFSSIZE} MiB"

echo ">>> Generate the LiveOS image structure..."
mkdir -pv ${TMPFS}/root/LiveOS/

# Show the contents that will get included to satisfy ourselves that the source dirs specified below are sufficient
ls -la ${SFSDIR}/
# Use lz4 compression to make it easier to spot size improvements/regressions during development
time mksquashfs ${SFSDIR}/* ${SFSDIR}/.moss ${TMPFS}/root/LiveOS/squashfs.img \
  -root-becomes LiveOS -keep-as-directory -all-root -b 1M -progress -comp lz4 #-Xhc # yields 10% extra compression

# Use zstd -19 for compressing release images, -3 for compressing quickly with better ratio than lz4 (default is 15)
#time mksquashfs ${SFSDIR}/* ${SFSDIR}/.moss ${TMPFS}/root/LiveOS/squashfs.img \
#  -root-becomes LiveOS -keep-as-directory -all-root -b 1M -info -progress -comp zstd -Xcompression-level 3

echo ">>> Create and mount the efi.img backing file..."
fallocate -l 45M ${TMPFS}/efi.img
mkfs.vfat -F 12 ${TMPFS}/efi.img -n EFIBOOTISO
mount -vo loop ${TMPFS}/efi.img ${MOUNT}

echo ">>> Set up EFI image..."
mkdir -pv ${MOUNT}/EFI/Boot/
cp -v ${BOOT}/bootx64.efi ${MOUNT}/EFI/Boot/bootx64.efi
sync
mkdir -pv ${MOUNT}/loader/entries/
cp -v ${WORK}/live-os.conf ${MOUNT}/loader/entries/
cp -v ${BOOT}/kernel ${MOUNT}/
cp -v ${BOOT}/initrd ${MOUNT}/
umount -Rlv ${MOUNT}

echo ">>> Put the new EFI image in the correct place..."
mkdir -pv ${TMPFS}/root/EFI/Boot
cp -v ${TMPFS}/efi.img ${TMPFS}/root/EFI/Boot/efiboot.img

echo ">>> Create the ISO file..."
xorriso -as mkisofs \
    -o ${WORK}/snekvalidator.iso \
    -R -J -v -d -N \
    -x snekvalidator.iso \
    -hide-rr-moved \
    -no-emul-boot \
    -eltorito-platform efi \
    -eltorito-boot EFI/Boot/efiboot.img \
    -isohybrid-gpt-basdat \
    -V "SERPENTISO" -A "SERPENTISO" \
    ${TMPFS}/root

cleanup

unset BOOT
unset CACHE
unset MOSS
unset MOUNT
unset RUST_BACKTRACE
unset SFSDIR
unset TMPFS
unset WORK
