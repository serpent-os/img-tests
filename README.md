## Create systemd-nspawn compatible `./sosroot` install

    ./create-sosroot.sh

## Create virt-manager/libvirtd compatible `/var/lib/machines/sosroot/` install

    DESTDIR="/var/lib/machines/sosroot" ./create-sosroot.sh

## Create installable QEMU-KVM ISO image

    cd kvm
    sudo ./img.sh
    qemu-system-x86_64 -enable-kvm -cdrom snekvalidator.iso -bios /usr/share/edk2-ovmf/x64/OVMF.fd -m 2048m -serial stdio
