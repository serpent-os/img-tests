#!/usr/bin/env bash
#
# SPDX-License-Identifier: MPL-2.0
#
# Copyright: © 2024 Serpent OS Developers
#

SOSROOT="${VMDIR:-/mnt/serpentos}"
ENABLE_SWAY="${ENABLE_SWAY:-false}"

printInfo () {
    local INFO="${BOLD}INFO${RESET}"
    echo -e "${INFO} ${*}"
}

printWarning () {
    local WARNING="${YELLOW}${BOLD}WARNING${RESET}"
    echo -e "${WARNING} ${*}"
}

printError () {
    local ERROR="${RED}${BOLD}ERROR${RESET}"
    echo -e "${ERROR} ${*}"
}

die() {
    printError "${*}\n"
    exit 1
}

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
test -f ./pkglist || die "\nThis script MUST be run from within the virt-manager-vm/ dir with the ./pkglist file.\n"
test -f ../pkglist-base || die "\nThis script MUST be able to find the ../pkglist-base file.\n"
test -x /usr/bin/moss || die "\n${0} assumes moss is installed. See https://github.com/serpent-os/onboarding/\n"
test -x /usr/bin/virsh || die "\n${0} assumes virsh is installed.\n"
test -x /usr/bin/virt-manager || die "\n${0} assumes virt-manager is installed.\n"

# start with a common base of packages
readarray -t PACKAGES < ../pkglist-base
# add linux-kvm specific packages
PACKAGES+=($(cat ./pkglist))

if [ "${ENABLE_SWAY}" = "true" ]; then
    PACKAGES+=("sway")
fi

MSG="Removing previous VM configuration..."
printInfo "${MSG}"
if sudo virsh desc serpentos &> /dev/null; then
    sudo virsh destroy serpentos || true
    sudo virsh undefine serpentos || die "'virsh undefine serpent' failed, exiting."
fi

MSG="Removing old ${SOSROOT} directory..."
printInfo "${MSG}"
sudo rm -rf "${SOSROOT}" || die "${MSG} failed, exiting."

MSG="Creating new ${SOSROOT} directory..."
printInfo "${MSG}"
sudo mkdir -pv "${SOSROOT}" || die "${MSG} failed, exiting."

MSG="Adding volatile serpent os repository..."
printInfo "${MSG}"
sudo moss -D "${SOSROOT}" repo add volatile https://dev.serpentos.com/volatile/x86_64/stone.index -p10 || die "${MSG} failed, exiting."

MSG="Installing packages..."
printInfo "${MSG}"
sudo moss -D "${SOSROOT}" install "${PACKAGES[@]}"

MSG="Ensuring that an /etc directory exists in ${SOSROOT}..."
printInfo "${MSG}"
sudo mkdir -pv "${SOSROOT}"/etc/ || die "${MSG} failed, exiting."

MSG="Ensuring that various network protocols function..."
printInfo "${MSG}"
sudo cp -va /etc/protocols "${SOSROOT}"/etc/ || die "${MSG} failed, exiting."

sed "s|###SOSROOT###|${SOSROOT}|g" serpentos.tmpl > serpentos.xml

virsh -c qemu:///system define serpentos.xml

showHelp
