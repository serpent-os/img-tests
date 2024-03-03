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

W="$(dirname $0)"
echo ">>> workdir \${W}: ${W}"
T="/tmp/serpent-image"
echo ">>> tmpfs dir \${T}: ${T}"

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
test -f ${W}/pkglist || die "\nThis script MUST be run from within the desktop/ dir with the ./pkglist file.\n"
test -f ${W}/../pkglist-base || die "\nThis script MUST be able to find the ../pkglist-base file.\n"

# start with a common base of packages
readarray -t PACKAGES < ${W}/../pkglist-base

# add linux-desktop specific packages
PACKAGES+=($(cat ${W}/pkglist))

#echo -e "List of packages:\n${PACKAGES[@]}\n"
#exit 1

test -f ${W}/initrdlist || die "initrd package list is absent"
readarray -t initrd < ${W}/initrdlist

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
    rm -rf ${T}/*

        # umount existing mount recursively and lazily
    test -d ${T}/mount && umount -Rlv ${T}/mount

    # clean up existing rootfs.img
    test -e ${T}/rootfs.img && rm -f ${T}/rootfs.img
}
cleanup

die-and-cleanup() {
    cleanup
    die $*
}

# From here on, exit from script on any non-zero exit status command result
set -e

export B="${T}/boot"
export M="${T}/mount"
export SFS="${T}/serpentfs"

# Stash boot assets
mkdir -pv ${B}

# Get it right first time.
mkdir -pv ${M} ${SFS}
chown -Rc root:root ${M} ${SFS}
# Only chmod directories
chmod -Rc u=rwX,g=rX,o=rX ${M} ${SFS}

export RUST_BACKTRACE=1

echo ">>> Add moss volatile repository to ${SFS}/..."
time moss -D ${SFS} repo add volatile https://dev.serpentos.com/volatile/x86_64/stone.index || die-and-cleanup "Adding moss repo failed!"

echo ">>> Install packages to ${SFS}/..."
time moss -D ${SFS} install -y "${PACKAGES[@]}" || die-and-cleanup "Installing packages failed!"

echo ">>> Fix ldconfig in ${SFS}/..."
mkdir -pv ${SFS}/var/cache/ldconfig
time moss-container -u 0 -d ${SFS} -- ldconfig

echo ">>> Set up basic environment in ${SFS}..."
time moss-container -u 0 -d ${SFS} -- systemd-sysusers
time moss-container -u 0 -d ${SFS} -- systemd-tmpfiles --create
time moss-container -u 0 -d ${SFS} -- systemd-firstboot --force --setup-machine-id --delete-root-password --locale=en_US.UTF-8 --timezone=UTC --root-shell=/usr/bin/bash
time moss-container -u 0 -d ${SFS} -- systemctl enable systemd-resolved systemd-networkd getty@tty1

echo ">>> Fix performance issues. Needs packaging/merging by moss"
time moss-container -u 0 -d ${SFS} -- systemd-hwdb update

echo ">>> Extract assets..."
cp -av ${SFS}/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${B}/bootx64.efi
cp -av ${SFS}/usr/lib/kernel/com.serpentos.* ${B}/kernel

#echo ">>> Set up overlayFS mounts..."
#rm -rf ${W}/overlay.*
#mkdir -pv ${W}/overlay.upper
#mkdir -pv ${W}/overlay.mount
#mkdir -pv ${W}/overlay.work

#mount -v -t overlay -o lowerdir=${M},upperdir=${W}/overlay.upper,workdir=${W}/overlay.work,redirect_dir=on overlay ${W}/overlay.mount || die-and-cleanup "Failed to mount overlay"

#echo ">>> Add moss volatile repository to ${W}/overlay.mount/ ..."
#time moss -D ${W}/overlay.mount repo add volatile https://dev.serpentos.com/volatile/x86_64/stone.index || die-and-cleanup "Adding moss repo failed!"

echo ">>> Install dracut in ${SFS}/ ..."
time moss -D ${SFS} install "${initrd[@]}" -y || die-and-cleanup "Failed to install initrd packages!"

echo ">>> Regenerate dracut..."
kver=$(ls ${SFS}/usr/lib/modules)
time moss-container -u 0 -d ${SFS}/ -- dracut --early-microcode --hardlink -N --nomdadmconf --nolvmconf --kver ${kver} --add "bash dash systemd lvm dm dmsquash-live" --fwdir /usr/lib/firmware --tmpdir /tmp --zstd --strip /initrd
mv -v ${SFS}/initrd ${B}/initrd

#echo ">>> Tear down overlayFS mount..."
#umount -Rlv ${W}/overlay.mount

echo ">>> Clean up ${SFS}/ ..."
time moss -D ${SFS} remove "${initrd[@]}" -y || die-and-cleanup "Failed to remove initrd packages from ${T}/ !"
time moss -D ${SFS} install -y "${PACKAGES[@]}" || die-and-cleanup "Installing packages failed!"

# Keep only latest state (= currently installed)
time moss -D ${SFS} state prune -k1 -y || die-and-cleanup "Failed to prune moss state in ${T}/ !"
# Remove downloaded .stones
rm -rf ${SFS}/.moss/cache/downloads/*


# transfer prepared new rootfs to rootfs.img
#cp -avx ${T}/* ${T}/.moss ${M}/ # <- segfaults for me on Solus
echo ">>> Transfer ${SFS}/ contents to rootfs.img mounted on ${M}/ ..."
IMGSIZE=$(du -BMiB -s ${T}|cut -f1|sed -e 's|MiB||g')
echo ">>> IMAGSIZE=${IMGSIZE}"
# Setup the root image to be twice as large as the SFS folder total size in MiB
fallocate -l $((${IMGSIZE} * 2))MiB ${T}/rootfs.img
# don't want/need journaling on the fs
mkfs.ext3 -F ${T}/rootfs.img
mount -vo loop ${T}/rootfs.img ${M}

time tar -C ${SFS} -cf - ./  | tar -C ${M} --totals --checkpoint=20000 -xpf -
# save memory once the FS has been created
rm -rf ${SFS}
umount -Rlv ${M}/

#echo ">>> Shrink rootfs.img size to minimum..."
resize2fs -Mfp ${T}/rootfs.img

echo ">>> Force a filesystem check on rootfs.img..."
e2fsck -fvy ${T}/rootfs.img

echo ">>> Generate the LiveOS image structure..."

mkdir -pv ${T}/LiveOS
ln -v ${T}/rootfs.img ${T}/LiveOS/
#mksquashfs ${W}/LiveOS/ ${W}/squashfs.img -comp zstd -root-becomes LiveOS -keep-as-directory -all-root
time mksquashfs ${T}/LiveOS/ ${T}/squashfs.img -root-becomes LiveOS -keep-as-directory -all-root -b 1M -info -progress -comp lz4 #-Xhc
rm -f ${T}/LiveOS/rootfs.img
ln -v ${T}/squashfs.img ${T}/LiveOS/

mkdir -pv ${T}/root
mv -v ${T}/LiveOS ${T}/root/.

echo ">>> Create and mount the efi.mg backing file..."
fallocate -l 45M ${T}/efi.img
mkfs.vfat -F 12 ${T}/efi.img -n EFIBOOTISO
mount -vo loop ${T}/efi.img ${M}

echo ">>> Set up EFI image..."
mkdir -pv ${T}/mount/EFI/Boot
cp -v ${B}/bootx64.efi ${M}/EFI/Boot/bootx64.efi
sync
mkdir -pv ${T}/mount/loader/entries
cp -v ${W}/live-os.conf ${M}/loader/entries/.
cp -v ${B}/kernel ${M}/kernel
cp -v ${B}/initrd ${M}/initrd
umount -Rlv ${M}

echo ">>> Put the new EFI image in the correct place..."
mkdir -pv ${T}/root/EFI/Boot
mv -v ${T}/efi.img ${T}/root/EFI/Boot/efiboot.img

echo ">>> Create the ISO file..."
xorriso -as mkisofs \
    -o ${W}/snekvalidator.iso \
    -R -J -v -d -N \
    -x snekvalidator.iso \
    -hide-rr-moved \
    -no-emul-boot \
    -eltorito-platform efi \
    -eltorito-boot EFI/Boot/efiboot.img \
    -isohybrid-gpt-basdat \
    -V "SERPENTISO" -A "SERPENTISO" \
    ${T}/root

cleanup

unset RUST_BACKTRACE=1
unset B
unset F
unset M
unset T
unset W
