#!/bin/bash

### WARNING: SUPER ROUGH PROTOTYPE

set -e
set -x

rm -rf root
rm -rf disk.img

fallocate -l 20GB disk.img
parted disk.img << EOF
mklabel GPT
mkpart "Extended Boot Loader Partition" fat32 1MiB 500MiB
mkpart "EFI System Partition" fat32 500MiB 600MiB
mkpart "Serpent OS Root Partition" ext2 600MiB 100%
set 2 esp on
set 1 bls_boot on
type-uuid 3 "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
EOF
LODEVICE=$(losetup -f disk.img --show -P)

mkdir root

mkfs.vfat -F 32 ${LODEVICE}p1
mkfs.vfat -F 32 ${LODEVICE}p2
mkfs.ext4 -F ${LODEVICE}p3

mount ${LODEVICE}p3 root
mkdir root/boot
mkdir root/esp
mount ${LODEVICE}p1 root/boot
mount ${LODEVICE}p2 root/esp
mkdir root/esp/EFI
mkdir root/esp/EFI/systemd
mkdir root/esp/EFI/Boot

echo "Loopback is at ${LODEVICE}"
sync

# get moss in.
moss -D root/ ar protosnek -p 0 https://dev.serpentos.com/protosnek/x86_64/stone.index
moss -D root/ ar volatile -p 10 https://dev.serpentos.com/volatile/x86_64/stone.index
moss -D root it $(cat pkglist) -y

# OS kernel assets
mkdir root/boot/com.serpentos
cp root/usr/lib/kernel/com.serpentos.* root/boot/com.serpentos/kernel-static
cp root/usr/lib/kernel/initrd-* root/com.serpentos/boot/initrd-static

mkdir root/boot/loader/entries -p
cp installed-os.conf root/boot/loader/entries/.

# systemd boot
cp root/usr/lib/systemd/boot/efi/systemd-bootx64.efi root/esp/EFI/systemd/systemd-bootx64.efi
cp root/usr/lib/systemd/boot/efi/systemd-bootx64.efi root/esp/EFI/Boot/bootx64.efi

ls -lRa root/boot
ls -lRa root/esp
umount root/boot
umount root/esp
umount root
losetup -d ${LODEVICE}

chmod a+rw disk.img
