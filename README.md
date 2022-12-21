```
    cd kvm
    sudo ./img.sh
    qemu-system-x86_64 -enable-kvm -cdrom snekvalidator.iso -bios /usr/share/edk2-ovmf/x64/OVMF.fd -m 2048m -serial stdio
```
