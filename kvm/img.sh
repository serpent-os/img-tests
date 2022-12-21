#!/bin/bash
set -e

# Pkg list
pkgs=$(cat pkglist)

# Root check
if [[ "${UID}" -ne 0 ]]; then
    echo "This script MUST be run as root"
    exit 1
fi

test -d mount && rmdir mount
test -d root && rmdir root
test -e rootfs.img && rm rootfs.img
test -d LiveOS && rm -rf LiveOS
test -d boot && rm -rf boot

# Stash boot assets
mkdir boot

# Get it right first time.
mkdir mount
chown root:root mount
chmod 00755 mount

# Setup the root image
fallocate -l 4GB rootfs.img
mkfs.ext3 -F rootfs.img
mount -o loop rootfs.img mount

# Add repositories
moss -D mount ar protosnek -p 0 https://dev.serpentos.com/protosnek/x86_64/stone.index
moss -D mount ar volatile -p 10 https://dev.serpentos.com/volatile/x86_64/stone.index

# Install the pkgs
moss -D mount it -y $pkgs

# TODO: Install dracut, rebuild the initrd from the "current" kernel
# Extract assets
cp mount/usr/lib/systemd/boot/efi/systemd-bootx64.efi boot/bootx64.efi
cp mount/usr/lib/kernel/com.serpentos.* boot/kernel

# Regenerate dracut. BLUH.
kver=$(ls mount/usr/lib/modules)
moss-container -u 0 -d mount -- dracut -N --nomdadmconf --nolvmconf --kver ${kver} --add "bash dash systemd lvm dm dmsquash-live" --fwdir /usr/lib/firmware --tmpdir /tmp --zstd /initrd
cp mount/initrd boot/initrd

# Cleanup!
rm -rf mount/.moss/cache/downloads/*

# Tear it down
sudo umount $(pwd)/mount

# Shrink size to minimum
resize2fs -M rootfs.img -f

# Force a check on it
e2fsck -fy rootfs.img

# Now gen the structure

mkdir LiveOS
mv rootfs.img LiveOS/.
mksquashfs LiveOS/ squashfs.img -comp zstd -root-becomes LiveOS -keep-as-directory -all-root
rm LiveOS/rootfs.img
mv squashfs.img LiveOS/.

mkdir root
mv LiveOS root/.

# Create the efi img
fallocate -l 25M efi.img
mkfs.vfat -F 12 efi.img -n EFIBOOTISO
mount -o loop efi.img mount

# Set it up...
mkdir -p mount/EFI/Boot
cp -a boot/bootx64.efi mount/EFI/Boot/bootx64.efi
sync
mkdir -p mount/loader/entries
cp live-os.conf mount/loader/entries/.
cp boot/kernel mount/kernel
cp boot/initrd mount/initrd
umount $(pwd)/mount

# Put it in place
mkdir -p root/EFI/Boot
mv efi.img root/EFI/Boot/efiboot.img

# Create the ISO
xorriso -as mkisofs \
    -o snekvalidator.iso \
    -R -J -v -d -N \
    -x snekvalidator.iso \
    -hide-rr-moved \
    -no-emul-boot \
    -eltorito-platform efi \
    -eltorito-boot EFI/Boot/efiboot.img \
    -V "SERPENTISO" -A "SERPENTISO" \
    root

# TODO: Generate an ISO
