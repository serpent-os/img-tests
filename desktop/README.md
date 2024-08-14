# Pre-alpha desktop image

Requires 8 GiB of free RAM because it uses tmpfs storage to create the various images comprising the ISO.

## Specifying ISO compression type

    $ sudo ./img.sh -c zstd
    Invalid compression type zstd specified.
    
    Usage: sudo ./img.sh -c <compression type>
    
    Valid compression types are:
    - lz4
    - xz
    - zstd3
    - zstd19
    - lz4hc
    
    The default compression type is lz4 (quick, used to spot size regressions).
    
    The best tradeoff between size and speed for local test ISO builds is zstd3.


# Booting a Serpent OS VM

    qemu-system-x86_64 -enable-kvm -m 4096m -cdrom snekvalidator.iso -drive if=pflash,format=raw,readonly=on,file=/usr/share/qemu/edk2-x86_64-code.fd -device virtio-vga-gl,xres=1920,yres=1080 -display gtk,gl=on,show-cursor=on


## Troubleshooting

> Ikey Doherty
> but yeah in future for this sorta thing, edit `live-os.conf` to add `console=ttyS0` and remove the `quiet` param
> then add `-serial stdio` to qemu
> for BIOS we'd see the error
> but qemu is a twat.
> so the EFI mode initialisation doesn't happen properly and we dont see these errors
> which is why we force getty1
> (cuz first setup doesnt work properly)
