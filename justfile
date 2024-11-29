# Set the default compression type for the ISO
COMPRESSION := "lz4"

# Allocate default memory size for QEMU
MEMORY := "4096m"

# Define the path to the image creation script
IMG_SCRIPT := "./img.sh"

# Specify the default target directory
DEFAULT_TARGET := "desktop"

# Define the path to the generated ISO file
ISO := "snekvalidator.iso"

# Specify the path to the QEMU firmware file
QEMU_FIRMWARE := "/usr/share/qemu/edk2-x86_64-code.fd"

# Build the ISO using the default compression type
build target=DEFAULT_TARGET:
    cd {{target}} && sudo {{IMG_SCRIPT}} -c {{COMPRESSION}}

# Build the ISO with a specified compression type
build-with-compression type target=DEFAULT_TARGET:
    cd {{target}} && sudo {{IMG_SCRIPT}} -c {{type}}

# Boot the ISO using QEMU with the specified settings
boot target=DEFAULT_TARGET:
    qemu-system-x86_64 -enable-kvm -m {{MEMORY}} -cdrom {{target}}/{{ISO}} -drive if=pflash,format=raw,readonly=on,file={{QEMU_FIRMWARE}} -device virtio-vga-gl,xres=1920,yres=1080 -display gtk,gl=on,show-cursor=on

# Build the ISO and then boot it using QEMU
build-and-boot target=DEFAULT_TARGET:
    just build target={{target}}
    just boot target={{target}}
