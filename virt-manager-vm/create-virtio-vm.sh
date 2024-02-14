#!/usr/bin/env bash
#
# SPDX-License-Identifier: MPL-2.0
#
# Copyright: © 2024 Serpent OS Developers
#

source ../basic-setup.sh

SOSROOT="${VMDIR:-/mnt/serpentos}"
ENABLE_SWAY="${ENABLE_SWAY:-false}"

showHelp() {
    cat <<EOF

----

You can now start a virtiofs machine via the virt-manager UI!

If you want to store your machine somewhere else than ${SOSROOT},
just call the script with

    VMDIR="/some/where/else" ./create-virtio-vm.sh

In case you directly want to install Sway as a desktop environment,
call the script with

    ENABLE_SWAY=true ./create-virtio-vm.sh

Should you have multiple GPUs in your system and you encounter
artifacts or no screen content at all, check in the VM display
settings that the correct GPU is being used.

EOF
}


# Pkg list check
checkPrereqs
test -f ./pkglist || die "\nThis script MUST be run from within the virt-manager-vm/ dir with the ./pkglist file.\n"
test -x /usr/bin/virsh || die "\n${0} assumes virsh is installed.\n"
test -x /usr/bin/virt-manager || die "\n${0} assumes virt-manager is installed.\n"

# start with a common base of packages
readarray -t PACKAGES < ../pkglist-base
# add linux-kvm specific packages
PACKAGES+=($(cat ./pkglist))

if [ "${ENABLE_SWAY}" = "true" ]; then
    PACKAGES+=("sway")
fi

basicSetup

MSG="Removing previous VM configuration..."
printInfo "${MSG}"
if sudo virsh desc serpentos &> /dev/null; then
    sudo virsh destroy serpentos || true
    sudo virsh undefine serpentos --keep-nvram || die "'virsh undefine serpent' failed, exiting."
fi

MSG="Setting up virt-mananger serpentos instance from template..."
printInfo "${MSG}"
FOUNDPAYLOAD="$(find /usr/share -name OVMF_CODE.fd)"
# Defaults to the location in Solus
UEFIPAYLOAD="${FOUNDPAYLOAD:-/usr/share/edk2-ovmf/x64/OVMF_CODE.fd}"
sed -e "s|###SOSROOT###|${SOSROOT}|g" -e "s|###UEFIPAYLOAD###|${UEFIPAYLOAD}|g" serpentos.tmpl > serpentos.xml

virsh -c qemu:///system define serpentos.xml

showHelp
cleanEnv
unset VMDIR
unset ENABLE_SWAY
