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

WORK="$(dirname $(realpath $0))"
echo ">>> workdir \${WORK}: ${WORK}"
TMPFS="/tmp/serpent_iso"
echo ">>> tmpfs dir \${TMPFS}: ${TMPFS}"

# Add escape codes for color
RED='\033[0;31m'
RESET='\033[0m'

# Root check
if [[ "${UID}" -ne 0 ]]; then
    die "\nThis script MUST be run as root.\n"
fi

BINARIES=(
    e2fsck
    fallocate
    lz4
    mkfs.ext3
    mkfs.vfat
    mksquashfs
    moss
    moss-container
    mount
    resize2fs
    sync
    xorriso
    zstd
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
#die "Exit because this is just a test."

# Pkg list check
test -f ${WORK}/pkglist || die "\nThis script MUST be run from within the desktop/ dir with the ./pkglist file.\n"
test -f ${WORK}/../pkglist-base || die "\nThis script MUST be able to find the ../pkglist-base file.\n"

# start with a common base of packages
readarray -t PACKAGES < ${WORK}/../pkglist-base

# add linux-desktop specific packages
PACKAGES+=($(cat ${WORK}/pkglist))

#echo -e "List of packages:\n${PACKAGES[@]}\n"
#exit 1

test -f ${WORK}/initrdlist || die "initrd package list is absent"
readarray -t initrd < ${WORK}/initrdlist

DIRS=(
    LiveOS
    boot
    mount
    root
    serpentfs
)

cleanup () {
    echo -e "\nCleaning up existing dirs, files and mount points...\n"
    # clean up dirs
    rm -rf ${TMPFS}/*

    # umount existing mount recursively and lazily
    test -d ${TMPFS}/mount && umount -Rlv ${TMPFS}/mount

    # clean up existing rootfs.img
    test -e ${TMPFS}/rootfs.img && rm -f ${TMPFS}/rootfs.img
}
cleanup

die-and-cleanup() {
    cleanup
    die $*
}

# From here on, exit from script on any non-zero exit status command result
set -e

export BOOT="${TMPFS}/boot"
export MOUNT="${TMPFS}/mount"
export SFSDIR="${TMPFS}/serpentfs"

# Stash boot assets
mkdir -pv ${BOOT}

# Get it right first time.
mkdir -pv ${MOUNT} ${SFSDIR}
chown -Rc root:root ${MOUNT} ${SFSDIR}
# Only chmod directories
chmod -Rc u=rwX,g=rX,o=rX ${MOUNT} ${SFSDIR}

export RUST_BACKTRACE=1

echo ">>> Add moss volatile repository to ${SFSDIR}/ ..."
time moss -D ${SFSDIR} repo add volatile https://dev.serpentos.com/volatile/x86_64/stone.index || die-and-cleanup "Adding moss repo failed!"

echo ">>> Install packages to ${SFSDIR}/ ..."
time moss -D ${SFSDIR} install -y "${PACKAGES[@]}" || die-and-cleanup "Installing packages failed!"

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
time moss -D ${SFSDIR} install "${initrd[@]}" -y || die-and-cleanup "Failed to install initrd packages!"

echo ">>> Regenerate dracut..."
kver=$(ls ${SFSDIR}/usr/lib/modules)
time moss-container -u 0 -d ${SFSDIR}/ -- dracut --early-microcode --hardlink -N --nomdadmconf --nolvmconf --kver ${kver} --add "bash dash systemd lvm dm dmsquash-live" --fwdir /usr/lib/firmware --tmpdir /tmp --zstd --strip /initrd
mv -v ${SFSDIR}/initrd ${BOOT}/initrd

echo ">>> Clean up ${SFSDIR}/ ..."
time moss -D ${SFSDIR} remove "${initrd[@]}" -y || die-and-cleanup "Failed to remove initrd packages from ${TMPFS}/ !"
time moss -D ${SFSDIR} install -y "${PACKAGES[@]}" || die-and-cleanup "Installing packages failed!"

# Keep only latest state (= currently installed)
time moss -D ${SFSDIR} state prune -k1 -y || die-and-cleanup "Failed to prune moss state in ${TMPFS}/ !"
# Remove downloaded .stones
rm -rf ${SFSDIR}/.moss/cache/downloads/*

#cp -avx ${TMPFS}/* ${TMPFS}/.moss ${MOUNT}/ # <- segfaults for me on Solus
echo ">>> Transfer ${SFSDIR}/ contents to rootfs.img mounted on ${MOUNT}/ ..."
IMGSIZE=$(du -BMiB -s ${TMPFS}|cut -f1|sed -e 's|MiB||g')
echo ">>> IMAGSIZE=${IMGSIZE}"
# Set up the root image to be twice as large as the SFS folder total size in MiB
fallocate -l $((${IMGSIZE} * 2))MiB ${TMPFS}/rootfs.img
# don't want/need journaling on the fs
mkfs.ext3 -F ${TMPFS}/rootfs.img
mount -vo loop ${TMPFS}/rootfs.img ${MOUNT}

time tar -C ${SFSDIR} -cf - ./  | tar -C ${MOUNT} --totals --checkpoint=20000 -xpf -
# save memory once the FS has been created
rm -rf ${SFSDIR}
umount -Rlv ${MOUNT}/

echo ">>> Shrink rootfs.img size to minimum..."
resize2fs -Mfp ${TMPFS}/rootfs.img

echo ">>> Force a filesystem check on rootfs.img..."
e2fsck -fvy ${TMPFS}/rootfs.img

echo ">>> Generate the LiveOS image structure..."
mkdir -pv ${TMPFS}/LiveOS
ln -v ${TMPFS}/rootfs.img ${TMPFS}/LiveOS/
#time mksquashfs ${WORK}/LiveOS/ ${WORK}/squashfs.img -root-becomes LiveOS -keep-as-directory -all-root -b 1M -info -progress -comp zstd
time mksquashfs ${TMPFS}/LiveOS/ ${TMPFS}/squashfs.img -root-becomes LiveOS -keep-as-directory -all-root -b 1M -info -progress -comp lz4 #-Xhc
rm -f ${TMPFS}/LiveOS/rootfs.img
ln -v ${TMPFS}/squashfs.img ${TMPFS}/LiveOS/

mkdir -pv ${TMPFS}/root
mv -v ${TMPFS}/LiveOS ${TMPFS}/root/.

echo ">>> Create and mount the efi.mg backing file..."
fallocate -l 45M ${TMPFS}/efi.img
mkfs.vfat -F 12 ${TMPFS}/efi.img -n EFIBOOTISO
mount -vo loop ${TMPFS}/efi.img ${MOUNT}

echo ">>> Set up EFI image..."
mkdir -pv ${TMPFS}/mount/EFI/Boot
cp -v ${BOOT}/bootx64.efi ${MOUNT}/EFI/Boot/bootx64.efi
sync
mkdir -pv ${TMPFS}/mount/loader/entries
cp -v ${WORK}/live-os.conf ${MOUNT}/loader/entries/.
cp -v ${BOOT}/kernel ${MOUNT}/kernel
cp -v ${BOOT}/initrd ${MOUNT}/initrd
umount -Rlv ${MOUNT}

echo ">>> Put the new EFI image in the correct place..."
mkdir -pv ${TMPFS}/root/EFI/Boot
mv -v ${TMPFS}/efi.img ${TMPFS}/root/EFI/Boot/efiboot.img

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

unset RUST_BACKTRACE=1
unset BOOT
unset SFSDIR
unset MOUNT
unset TMPFS
unset WORK