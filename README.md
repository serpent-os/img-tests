# Here be dragons 🔥🐉

🚨🚧🚧🚧🚨

As Serpent OS is under heavy development, the image generation scripts in this repository are provided as is,
with no explicit or implied warranty or support.

If you break your computer because you used these scripts or Serpent OS in its current state, you get to keep both pieces.

## Create systemd-nspawn compatible `./sosroot` install

    ./create-sosroot.sh

## Create virt-manager/libvirtd compatible `/var/lib/machines/sosroot/` install

    DESTDIR="/var/lib/machines/sosroot" ./create-sosroot.sh

## Create virtiofs-based virt-manager VM install

    cd virt-manager-vm
    ./create-virtio-vm.sh

## Create QEMU-KVM ISO image

    cd kvm
    sudo ./img.sh
    qemu-system-x86_64 -enable-kvm -cdrom snekvalidator.iso -bios /usr/share/edk2-ovmf/x64/OVMF.fd -m 4096m -serial stdio
