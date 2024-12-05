# Set the default compression type for the ISO
compression := "lz4"

# Allocate default memory size for QEMU
memory := "4096m"

# Define the path to the image creation script
img_script := "./img.sh"

# Specify the default target directory
target := "desktop"

# Define default desktop flavour
flavor := "gnome"

# Define the path to the generated ISO file
iso := "snekvalidator.iso"

# Specify the path to the QEMU firmware file
firmware := "/usr/share/qemu/edk2-x86_64-code.fd"

# Build the ISO using the default compression type and flavour
build:
    cd {{target}} && sudo {{img_script}} -c {{compression}} -p {{flavor}}_pkglist

# Boot the ISO using QEMU with the specified settings
boot:
    qemu-system-x86_64 -enable-kvm -m {{memory}} -cdrom {{target}}/{{iso}} -drive if=pflash,format=raw,readonly=on,file={{firmware}} -device virtio-vga-gl,xres=1920,yres=1080 -display sdl,gl=on,show-cursor=off

# Build the ISO and then boot it using QEMU
build-and-boot: build boot
