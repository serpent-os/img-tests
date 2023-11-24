#!/bin/bash
set -e
set -x

echo "Launching Serpent OS Prototype (UEFI)"
qemu-system-x86_64 -enable-kvm -m 2048m  -bios ./OVMF.fd -cpu host -drive format=raw,file=./disk.img

