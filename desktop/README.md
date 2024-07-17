# Pre-alpha desktop image

Requires 8GiB of free RAM because it uses tmpfs storage to create the various images comprising the ISO.

## Specifying ISO compression type

    sudo -E COMPRESSION=zstd ./img.sh 
    You specified the compression type: zstd
    
    Valid compression types are:
    - lz4 (default, quick to build, size regressions are easily spotted in smoketests)
    - xz
    - zstd3 (recommended for quick builds that will get written to USB sticks)
    - zstd19 (recommended for release ISOs)
    - lz4hc

## Troubleshooting

> Ikey Doherty
> but yeah in future for this sorta thing, edit `live-os.conf` to add `console=ttyS0` and remove the `quiet` param
> then add `-serial stdio` to qemu
> for BIOS we'd see the error
> but qemu is a twat.
> so the EFI mode initialisation doesn't happen properly and we dont see these errors
> which is why we force getty1
> (cuz first setup doesnt work properly)
