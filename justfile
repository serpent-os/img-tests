# Define the path to the image creation script
img_script := "./img.sh"

# Specify the default target directory
target := "desktop"

# Define default desktop flavour
flavor := "gnome"

# Set the default compression type for the ISO
compression := "lz4"

# Define the name of the generated ISO file (saved as output.iso)
output := flavor + "-snek-" + compression

# Allocate default memory size for QEMU
memory := "4096m"

# Specify the path to the QEMU firmware file
firmware := "/usr/share/qemu/edk2-x86_64-code.fd"

# Print nice help text with syntax and examples.
help:
    @echo 'Supported options:'
    @echo '    just [img_script] [target] [flavor] [compression] [output] [memory] [firmware] recipe'
    @echo '    (most people should only use the flavor, compression, output, or firmware options)'
    @echo 'Examples:'
    @echo '    just build  # will build a quick, lz4 compressed gnome "gnome-snek-lz4.iso" by default'
    @echo '    just flavor="gnome" compression="zstd3" output="serpent-gnome-test" build'
    @echo '    just output="serpent-gnome-test" memory="8192m" firmware="/usr/share/edk2-ovmf/x64/OVMF_CODE.fd" boot'
    @echo '    just flavor="cosmic" build-and-boot'
    @just -l

# Build a test flavor iso using compression type (and rename it as appropriate)
build:
    cd {{target}} && sudo {{img_script}} -c {{compression}} -o {{output}} -p {{flavor}}_pkglist

# Boot the specified ISO using QEMU with the specified settings
boot:
    qemu-system-x86_64 -enable-kvm -m {{memory}} -cdrom {{target}}/{{output}}.iso -drive if=pflash,format=raw,readonly=on,file={{firmware}} -device virtio-vga-gl,xres=1920,yres=1080 -display sdl,gl=on,show-cursor=off -cpu host

# Build a flavor iso using compression type and then boot it using QEMU with specified firmware
build-and-boot: build boot

# Build release ISOs for the GNOME and COSMIC flavours
release:
    just build flavor="gnome" compression="zstd3"
    just build flavor="cosmic" compression="zstd3"

[confirm('This will delete ALL found .iso images -- continue?')]
_clean:
    @cd {{target}} && sudo rm -vf *.iso

_list-isos:
    cd {{target }} && ls -AFcghlot --block-size=M *.iso

# Clean out existing .iso files in {{target}} (desktop/ by default)
clean: _list-isos && _clean
