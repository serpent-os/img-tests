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

D="$(dirname $0)"
echo "WORKDIR: ${D} "

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
    mkfs.ext3
    mkfs.vfat
    moss
    moss-container
    mount
    resize2fs
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
#die "Exit because this is just a test."

# Pkg list check
test -f ${D}/pkglist || die "\nThis script MUST be run from within the desktop/ dir with the ./pkglist file.\n"
test -f ${D}/../pkglist-base || die "\nThis script MUST be able to find the ../pkglist-base file.\n"

# start with a common base of packages
readarray -t PACKAGES < ${D}/../pkglist-base

# add linux-desktop specific packages
PACKAGES+=($(cat ${D}/pkglist))

#echo -e "List of packages:\n${PACKAGES[@]}\n"
#exit 1

test -f ${D}/initrdlist || die "initrd package list is absent"
readarray -t initrd < ${D}/initrdlist

DIRS=(
    mount
    root
    LiveOS
    boot
    overlay.upper
    overlay.mount
    overlay.work
)

cleanup () {
    echo -e "\nCleaning up existing dirs, files and mount points...\n"
    # clean up dirs
    for d in ${DIRS[@]}; do
        test -d ${D}/${d} && rm -rf ${D}/${d}
    done

    # umount existing mount recursively and lazily
    test -d ${D}/mount && umount -Rlv ${D}/mount

    # clean up existing rootfs.img
    test -e ${D}/rootfs.img && rm -f ${D}/rootfs.img
}
cleanup

die-and-cleanup() {
    cleanup
    die $*
}

# From here on, exit from script on any non-zero exit status command result
set -e

# Stash boot assets
mkdir -pv ${D}/boot

# Get it right first time.
mkdir -pv ${D}/mount
chown -Rc root:root ${D}/mount
chmod -Rc 00755 ${D}/mount

# Setup the root image
fallocate -l 10GB ${D}/rootfs.img
# don't want/need journaling on the fs
mkfs.ext3 -F ${D}/rootfs.img
mount -o loop ${D}/rootfs.img ${D}/mount

export RUST_BACKTRACE=1

# Add repositories
moss -D ${D}/mount/ repo add volatile https://dev.serpentos.com/volatile/x86_64/stone.index || die-and-cleanup "Adding moss repo failed!"

# Install the PACKAGES
moss -D ${D}/mount/ install -y "${PACKAGES[@]}" || die-and-cleanup "Installing packages failed!"

# Fix ldconfig
mkdir -pv ${D}/mount/var/cache/ldconfig
moss-container -u 0 -d ${D}/mount/ -- ldconfig

# Get basic env working
moss-container -u 0 -d ${D}/mount/ -- systemd-sysusers
moss-container -u 0 -d ${D}/mount/ -- systemd-tmpfiles --create
moss-container -u 0 -d ${D}/mount/ -- systemd-firstboot --force --setup-machine-id --delete-root-password --locale=en_US.UTF-8 --timezone=UTC --root-shell=/usr/bin/bash
moss-container -u 0 -d ${D}/mount/ -- systemctl enable systemd-resolved systemd-networkd getty@tty1

# Fix perf issues. Needs packaging/merging by moss
moss-container -u 0 -d ${D}/mount/ -- systemd-hwdb update

# Extract assets
cp -v ${D}/mount/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${D}/boot/bootx64.efi
cp -v ${D}/mount/usr/lib/kernel/com.serpentos.* ${D}/boot/kernel

# Setup the overlay.
mkdir ${D}/overlay.upper
mkdir ${D}/overlay.mount
mkdir ${D}/overlay.work

mount -t overlay -o lowerdir=${D}/mount,upperdir=${D}/overlay.upper,workdir=${D}/overlay.work,redirect_dir=on overlay ${D}/overlay.mount || die "Failed to mount overlay"

# Install dracut now
moss -D ${D}/overlay.mount install "${initrd[@]}" -y || die "Failed to install overlay packages"

# Regenerate dracut. BLUH.
kver=$(ls ${D}/mount/usr/lib/modules)
moss-container -u 0 -d ${D}/overlay.mount/ -- dracut --early-microcode --hardlink -N --nomdadmconf --nolvmconf --kver ${kver} --add "bash dash systemd lvm dm dmsquash-live" --fwdir /usr/lib/firmware --tmpdir /tmp --zstd --strip /initrd
cp -v ${D}/overlay.mount/initrd ${D}/boot/initrd

# Tear it down
umount ${D}/overlay.mount

# Cleanup!
rm -rf ${D}/mount/.moss/cache/downloads/*
umount ${D}/mount

# Shrink size to minimum
resize2fs -M ${D}/rootfs.img -f

# Force a check on it
e2fsck -fy ${D}/rootfs.img

# Now gen the structure

mkdir -pv ${D}/LiveOS
mv -v ${D}/rootfs.img ${D}/LiveOS/.
mksquashfs ${D}/LiveOS/ ${D}/squashfs.img -comp zstd -root-becomes LiveOS -keep-as-directory -all-root
rm -f ${D}/LiveOS/rootfs.img
mv -v ${D}/squashfs.img ${D}/LiveOS/.

mkdir -pv ${D}/root
mv -v ${D}/LiveOS ${D}/root/.

# Create the efi img
fallocate -l 45M ${D}/efi.img
mkfs.vfat -F 12 ${D}/efi.img -n EFIBOOTISO
mount -o loop ${D}/efi.img ${D}/mount

# Set it up...
mkdir -pv ${D}/mount/EFI/Boot
cp -v ${D}/boot/bootx64.efi ${D}/mount/EFI/Boot/bootx64.efi
sync
mkdir -pv ${D}/mount/loader/entries
cp -v ${D}/live-os.conf ${D}/mount/loader/entries/.
cp -v ${D}/boot/kernel ${D}/mount/kernel
cp -v ${D}/boot/initrd ${D}/mount/initrd
umount ${D}/mount

# Put it in place
mkdir -pv ${D}/root/EFI/Boot
mv -v ${D}/efi.img ${D}/root/EFI/Boot/efiboot.img

# Create the ISO
xorriso -as mkisofs \
    -o ${D}/snekvalidator.iso \
    -R -J -v -d -N \
    -x snekvalidator.iso \
    -hide-rr-moved \
    -no-emul-boot \
    -eltorito-platform efi \
    -eltorito-boot EFI/Boot/efiboot.img \
    -isohybrid-gpt-basdat \
    -V "SERPENTISO" -A "SERPENTISO" \
    root

unset RUST_BACKTRACE=1
unset D
