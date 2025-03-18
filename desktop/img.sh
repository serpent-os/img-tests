#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2020-2023 Serpent OS Developers
#
# SPDX-License-Identifier: MPL-2.0
#
# AerynOS prototype linux-desktop ISO image generator
#
die () {
    echo -e "$*"
    exit 1
}

# Root check
if [[ "${UID}" -ne 0 ]]; then
    die "\nThis script MUST be run as root.\n"
fi

# Add escape codes for color
RED='\033[0;31m'
RESET='\033[0m'

declare -A COMPRESSION_ARGS
# The default because it's fast and it's easy to spot regressions in size
COMPRESSION_ARGS["lz4"]="lz4"
# yields 10% extra compression
COMPRESSION_ARGS["lz4hc"]="lz4 -Xhc"
# Almost as quick as lz4 and a fair bit smaller
COMPRESSION_ARGS["zstd3"]="zstd -Xcompression-level 3"
# Good for release images
COMPRESSION_ARGS["zstd19"]="zstd -Xcompression-level 19"
# Only here for comparison with zstd -19
COMPRESSION_ARGS["xz"]="xz -Xbcj x86"

function print_valid_compression_types() {
    echo "Valid compression types are:"
    for key in ${!COMPRESSION_ARGS[@]}; do
        echo "- $key"
    done
}

function usage() {
    echo -e "\nUsage: sudo ./img.sh -c <compression type> -o <output>.iso -p <package list>\n"
    print_valid_compression_types
    echo -e "\nThe default compression type is lz4 (quick, easy to spot size regressions).\n"
    echo -e "The best tradeoff between size and speed is zstd3.\n"
    echo -e "\nThe default output is 'aerynos' (becomes 'aerynos.iso')"
    echo -e "\nThe default package list is pkglist.\n"
}

# defaults
PACKAGE_LIST="pkglist"
OUTPUT="aerynos"

while getopts 'c:o:p:' opt
do
  case "$opt" in
  c)
    COMPRESSION="$OPTARG"
    if [[ -z "$COMPRESSION" ]]; then
        echo "No compression type specified."
        usage
        exit 1
    elif [[ -z "${COMPRESSION_ARGS[$COMPRESSION]}" ]]; then
        echo "Invalid compression type "$COMPRESSION" specified."
        usage
        exit 1
    else
        # we're good, carry on
        :
    fi
    ;;
  o)
    OUTPUT="$OPTARG"
    if [[ -z "${OUTPUT}" ]]; then
        echo "No <output>.iso filename specified."
        usage
        exit 1
    else
        # we're good, carry on
        :
    fi
    ;;
  p)
    PACKAGE_LIST="$OPTARG"
    if [[ -z "$PACKAGE_LIST" ]]; then
        echo "No package list specified."
        usage
        exit 1
    fi
    ;;
  ?)
    usage
    exit 1
    ;;
  esac
done

# Let the user set the COMPRESSION variable and document supported compressors in the README
export COMPRESSOR="${COMPRESSION:-lz4}"
echo "Using compression type: $COMPRESSOR"

WORK="$(dirname $(realpath $0))"
echo ">>> workdir \${WORK}: ${WORK}"
TMPFS="/tmp/aerynos_iso"
echo ">>> tmpfs dir \${TMPFS}: ${TMPFS}"

BINARIES=(
    fallocate
    mkfs.vfat
    mksquashfs
    moss
    mount
    sync
    systemd-nspawn
    xorriso
)
# up front check for necessary binaries
BINARY_NOT_FOUND=0
echo -e "\nChecking for necessary prerequisites..."
# 'all entries in the BINARIES array'
for b in ${BINARIES[@]}; do
    command -v ${b} > /dev/null 2>&1
    if [[ ! ${?} -eq 0 ]]; then
        echo -e "- ${b} ${RED}not found${RESET} in \$PATH."
        BINARY_NOT_FOUND=1
    else
        echo "- found ${b}"
    fi
done

if [[ ${BINARY_NOT_FOUND} -gt 0 ]]; then
    die "\nNecessary prerequisites not met, please install missing tool(s).\n"
else
    echo -e "\nAll necessary binaries found, generating AerynOS linux-desktop ISO image...\n"
fi

# Pkg list check
test -f "${WORK}/../pkglist-base" || die "\nThis script MUST be able to find the ../pkglist-base file.\n"
test -f "${WORK}/${PACKAGE_LIST}" || die "\nThe specified package list file ${PACKAGE_LIST} does not exist.\n"

# start with a common base of packages
readarray -t PACKAGES < "${WORK}/../pkglist-base"

# add linux-desktop specific packages
PACKAGES+=($(cat "${WORK}/${PACKAGE_LIST}"))

test -f ${WORK}/initrdlist || die "\nThis script MUST be run from within the desktop/ dir with the ./initrd file.\n"
readarray -t initrd < "${WORK}/initrdlist"

cleanup () {
    echo -e "\nCleaning up existing dirs, files and mount points..."
    # clean up dirs (if something fails here, let the remaining lines take care of it)
    rm -rf "${TMPFS}"/* || echo "- Removing ${TMPFS}/* failed."

    # umount existing mount recursively and lazily
    test -d "${TMPFS}"/* && { umount -Rlv "${TMPFS}"/* || echo "- Recursive unmounting of ${TMPFS}/* failed." ;}

    # clean leftover existing *.img
    test -e "${TMPFS}"/*.img && { rm -vf "${TMPFS}"/*.img || echo "- Removing leftover ${TMPFS}/*.img files failed." ;}

    echo "- Cleanup done."
}
cleanup

die_and_cleanup() {
    cleanup
    die $*
}

# From here on, exit from script on any non-zero exit status command result
set -e

export BOOT="${TMPFS}/boot"
export CACHE="${WORK}/cached_stones"
export MOUNT="${TMPFS}/mount"
export SFSDIR="${TMPFS}/aerynosfs"
export CHROOT="systemd-nspawn --as-pid2 --private-users=identity --user=0 --quiet"



# Use a permanent cache for downloaded .stones
mkdir -pv "${CACHE}"

# Stash boot assets
mkdir -pv "${BOOT}"

# Get it right first time.
mkdir -pv "${MOUNT}" "${SFSDIR}"
chown -Rc root:root "${MOUNT}" "${SFSDIR}"
# Only chmod directories
chmod -Rc u=rwX,g=rX,o=rX "${MOUNT}" "${SFSDIR}"

export RUST_BACKTRACE=1

export MOSS="moss -D ${SFSDIR} --cache ${CACHE}"

echo ">>> Add raw volatile repository to ${SFSDIR}/ ..."
time ${MOSS} repo add volatile https://packages.aerynos.dev/volatile/x86_64/stone.index || die_and_cleanup "Adding moss repo failed!"

echo ">>> Install packages to ${SFSDIR}/ ..."
time ${MOSS} install -y "${PACKAGES[@]}" || die_and_cleanup "Installing packages failed!"

echo ">>> Set up basic environment in ${SFSDIR}/ ..."
time ${CHROOT} -D "${SFSDIR}" systemd-firstboot --force --delete-root-password --locale=en_US.UTF-8 --timezone=UTC --root-shell=/usr/bin/bash && echo ">>>>> systemd-firstboot run done."

echo ">>> Configuring live user."
time ${CHROOT} -D "${SFSDIR}" useradd -c "Live User" -d "/home/live" -G "audio,adm,wheel,render,input,users" -m -U -s "/usr/bin/bash" live
cp -R ${WORK}/rootfs_extra/etc/* "${SFSDIR}/etc/."
chown -R root:root "${SFSDIR}/etc"
${CHROOT} -D "${SFSDIR}" chown -R live:live /home/live
${CHROOT} -D "${SFSDIR}" passwd -d live

echo ">>> Forcibly refreshing flatpak."
time ${CHROOT} -D "${SFSDIR}" flatpak update --system --appstream --no-deps --no-related -v

echo ">>> Extract assets..."
cp -av "${SFSDIR}/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "${BOOT}/bootx64.efi"
cp -av "${SFSDIR}"/usr/lib/kernel/*/vmlinuz "${BOOT}/kernel"

echo ">>> Install dracut in ${SFSDIR}/ ..."
time ${MOSS} install "${initrd[@]}" -y || die_and_cleanup "Failed to install initrd packages!"

echo ">>> Regenerate dracut..."
kver=$(ls "${SFSDIR}/usr/lib/modules")
time ${CHROOT} -D "${SFSDIR}/" dracut --early-microcode --hardlink -N --nomdadmconf --nolvmconf --kver ${kver} --add "bash dash systemd lvm dm dmsquash-live plymouth" --fwdir /usr/lib/firmware --tmpdir /tmp --zstd --strip /initrd -v
mv -v "${SFSDIR}/initrd" "${BOOT}/initrd"

echo ">>> Roll back and prune to keep only initially installed state and remove downloads ..."
time ${MOSS} state activate 1 -y || die_and_cleanup "Failed to activate initial state in ${TMPFS}/ !"
time ${MOSS} state prune -k 1 --include-newer -y || die_and_cleanup "Failed to prune moss state in ${TMPFS}/ !"

# Remove downloaded .stones to lower size of generated ISO
rm -rf "${SFSDIR}"/.moss/cache/downloads/*

SFSSIZE=$(du -BMiB -s ${TMPFS}|cut -f1|sed -e 's|MiB||g')
echo ">>> ${SFSDIR} size: ${SFSSIZE} MiB"

echo ">>> Generate the LiveOS image structure..."
mkdir -pv "${TMPFS}/root/LiveOS/"

# Show the contents that will get included to satisfy ourselves that the source dirs specified below are sufficient
ls -la "${SFSDIR}/"

echo ">>> Compress the LiveOS squashfs.img using the ${COMPRESSOR} compression preset..."
time mksquashfs "${SFSDIR}"/* "${SFSDIR}/.moss" "${TMPFS}/root/LiveOS/squashfs.img" \
  -root-becomes LiveOS -keep-as-directory -b 1M -progress -comp ${COMPRESSION_ARGS[$COMPRESSOR]}

echo ">>> Create and mount the efi.img backing file..."
EFI_SIZE=$(du -c "${BOOT}/bootx64.efi" "${BOOT}/kernel" "${BOOT}/initrd" "${WORK}/live-os.conf" | grep total | awk '{print $1}')
EFI_SIZE=$((EFI_SIZE + 1024)) # Add some buffer space
fallocate -l ${EFI_SIZE}K "${TMPFS}/efi.img"
mkfs.vfat -F 12 "${TMPFS}/efi.img" -n EFIBOOTISO
mount -vo loop "${TMPFS}/efi.img" "${MOUNT}"

echo ">>> Set up EFI image..."
mkdir -pv "${MOUNT}/EFI/Boot/"
cp -v "${BOOT}/bootx64.efi" "${MOUNT}/EFI/Boot/bootx64.efi"
sync
mkdir -pv "${MOUNT}/loader/entries/"
cp -v "${WORK}/live-os.conf" "${MOUNT}/loader/entries/"
cp -v "${BOOT}/kernel" "${MOUNT}/"
cp -v "${BOOT}/initrd" "${MOUNT}/"
umount -Rlv "${MOUNT}"

echo ">>> Put the new EFI image in the correct place..."
mkdir -pv "${TMPFS}/root/EFI/Boot"
cp -v "${TMPFS}/efi.img" "${TMPFS}/root/EFI/Boot/efiboot.img"

echo ">>> Copy the isolinux bootloader..."
mkdir -pv "${TMPFS}/root/isolinux/"
cp -v "${WORK}/../iso_assets/isolinux.bin" "${TMPFS}/root/isolinux/."

echo ">>> Create the ISO file..."
xorriso -as mkisofs \
    -o "${WORK}/${OUTPUT}.iso" \
    -R -J -v -d -N \
    -x "${OUTPUT}.iso" \
    -hide-rr-moved \
    -isohybrid-mbr ${WORK}/../iso_assets/isohdpfx.bin \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 \
    -boot-info-table \
    -no-emul-boot \
    -eltorito-alt-boot \
    -e EFI/Boot/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -V "AERYNOSLIVE" -A "AERYNOSLIVE" \
    "${TMPFS}/root"

# The gnarly sed operation is here because the uutils-coreutils `ls` does not output the unit next to the size
echo "Successfully built $(ls -s --block-size=M ${OUTPUT}.iso | sed 's|\([[:digit:]]+*\) \(.*\)$|\1M \2|g') using $COMPRESSION compression."

cleanup

for v in BOOT CACHE CHROOT COMPRESSOR MOSS MOUNT RUST_BACKTRACE SFSDIR TMPFS WORK; do
    unset "${v}" || true
done

exit 0
