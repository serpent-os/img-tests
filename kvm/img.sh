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
test -e rootfs.img && rm rootfs.img
test -d LiveOS && rmdir LiveOS

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

# TODO: Generate an ISO
