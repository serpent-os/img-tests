#!/usr/bin/env bash
#
# SPDX-License-Identifier: MPL-2.0
#
# Copyright: © 2024 Serpent OS Developers
#

source ../basic-setup.sh

SOSROOT="${VMDIR:-${PWD}/sosroot}"
SOSNAME="${VMNAME:-serpent_virtiofs}"
ENABLE_SWAY="${ENABLE_SWAY:-false}"

showStartMessage() {
    cat <<EOF

You can now start the ${SOSNAME} VM via the virt-manager UI!

----

EOF
}

showHelp() {
    cat <<EOF

If you want to store your machine somewhere else than ${SOSROOT},
just call the script with

    VMDIR="/some/where/else" ./create-virtio-vm.sh

If you want to name your machine something else than ${SOSNAME},
just call the script with 
    
    VMNAME="some_other_name" ./create-virtio-vm.sh

In case you directly want to install Sway as a desktop environment,
call the script with

    ENABLE_SWAY=true ./create-virtio-vm.sh

Should you have multiple GPUs in your system and you encounter
artifacts or no screen content at all, check in the VM display
settings that the correct GPU is being used.

EOF
}

if [ "$1" == "help" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    showHelp
    cleanEnv
    unset VMDIR
    unset VMNAME
    unset ENABLE_SWAY
    exit 1
fi

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
if sudo virsh desc "${SOSNAME}" &> /dev/null; then
    sudo virsh destroy "${SOSNAME}" || true
    sudo virsh undefine "${SOSNAME}" --keep-nvram || die "'virsh undefine serpent' failed, exiting."
fi

MSG="Setting up virt-mananger ${SOSNAME} instance from template..."
printInfo "${MSG}"
FOUNDPAYLOAD="$(find /usr/share -name OVMF_CODE.fd |grep -i ovmf/)"
# Defaults to the location in Solus
UEFIPAYLOAD="${FOUNDPAYLOAD:-/usr/share/edk2-ovmf/x64/OVMF_CODE.fd}"
MSG="Found \$UEFIPAYLOAD: ${UEFIPAYLOAD}..."
printInfo "${MSG}"
sed -e "s|###SOSNAME###|${SOSNAME}|g" \
    -e "s|###SOSROOT###|${SOSROOT}|g" \
    -e "s|###UEFIPAYLOAD###|${UEFIPAYLOAD}|g" \
    serpentos.tmpl > serpentos.xml

virsh -c qemu:///system define serpentos.xml

showStartMessage
showHelp
cleanEnv
unset VMDIR
unset VMNAME
unset ENABLE_SWAY
