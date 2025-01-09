## Alpha desktop image generation

Requires 8 GiB of free RAM because it uses tmpfs storage to create the various images comprising the ISO.

### ISO compression types
 
The default compression type is `lz4` (quick, used to spot size regressions).
    
The best tradeoff between size and speed for local test ISO builds is `zstd3` (particularly if your system has many cores).

Release ISOs are built with `zstd19`.

Multithreaded XZ -9 with ELF format dictionary for better compression is available as `xz`.


## Build and boot options


```
just help # <- run this command
Supported options:
    just [img_script] [target] [flavor] [compression] [output] [memory] [firmware] recipe
    (most people should only use the flavor, compression, output, or firmware options)
Examples:
    just build  # will build a quick, lz4 compressed gnome "gnome-snek-lz4.iso" by default
    just flavor="gnome" compression="zstd3" output="serpent-gnome-test" build
    just output="serpent-gnome-test" memory="8192m" firmware="/usr/share/edk2-ovmf/x64/OVMF_CODE.fd" boot
    just flavor="cosmic" build-and-boot
Available recipes:
    boot           # Boot the specified ISO using QEMU with the specified settings
    build          # Build a test flavor iso using compression type (and rename it as appropriate)
    build-and-boot # Build a flavor iso using compression type and then boot it using QEMU with specified firmware
    clean          # Clean out existing .iso files in {{target}} (desktop/ by default)
    help           # Print nice help text with syntax and examples.
    release        # Build release ISOs for the GNOME and COSMIC flavours
```

### Troubleshooting (preserved for historical purposes)

> Ikey Doherty
> but yeah in future for this sorta thing, edit `live-os.conf` to add `console=ttyS0` and remove the `quiet` param
> then add `-serial stdio` to qemu
> for BIOS we'd see the error
> but qemu is a twat.
> so the EFI mode initialisation doesn't happen properly and we dont see these errors
> which is why we force getty1
> (cuz first setup doesnt work properly)
