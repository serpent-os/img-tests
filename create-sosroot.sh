#!/usr/bin/env bash
#
# SPDX-License-Identifier: MPL-2.0
#
# Copyright: © 2023 Serpent OS Developers
#

# create-sosroot.sh:
# script for conveniently creating a clean /var/lib/machines/sosroot/
# directory suitable for use as the root in serpent os systemd-nspawn
# container or linux-kvm kernel driven qemu-kvm virtual machine.

# target dirs
# use a default sosroot
SOSROOT="${DESTDIR:-./sosroot}"
BOULDERCACHE="/var/cache/boulder"

# utility functions
BOLD='\033[1m'
RED='\033[0;31m'
RESET='\033[0m'
YELLOW='\033[0;33m'

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

# prerequisite checks
test -f ./pkglist-base || die "\nRun this script from the root of the img-tests/ repo clone!\n"
test -x /usr/bin/moss || die "\n${0} assumes moss is installed. See https://github.com/serpent-os/onboarding/\n"

# base packages
readarray -t PACKAGES < ./pkglist-base

#echo "${PACKAGES[@]}"
#die "Test of PACKAGES."

showHelp() {
    cat <<EOF

----

You can now start a systemd-nspawn container with:

 sudo systemd-nspawn --bind=${BOULDERCACHE}/ -D ${SOSROOT}/ -b

Do a 'systemctl poweroff' inside the container to shut it down.

The container can also be shut down with:

 sudo machinectl stop sosroot

in a shell outside the container.

If you want to be able to use your sosroot/ with virt-manager,
you can set the DESTDIR variable when calling ${0} like so:

    DESTDIR="/var/lib/machines/sosroot" create-sosroot.sh

EOF
}

# Make it more convenient to boot into the created sosroot/ later on
createBootScript () {
    cat <<EOF > boot-systemd-nspawn-container.sh
#!/usr/bin/env bash
#
exec sudo systemd-nspawn --bind=${BOULDERCACHE}/ -D ${SOROOT}/ -b
EOF
}

MSG="Removing old ${SOSROOT} directory..."
printInfo "${MSG}"
sudo rm -rf "${SOSROOT}" || die "${MSG} failed, exiting."

MSG="Creating new ${SOSROOT} directory..."
printInfo "${MSG}"
sudo mkdir -pv "${SOSROOT}" || die "${MSG} failed, exiting."

MSG="Adding volatile serpent os repository..."
printInfo "${MSG}"
sudo moss -D "${SOSROOT}" repo add volatile https://dev.serpentos.com/volatile/x86_64/stone.index -p0 || die "${MSG} failed, exiting."

MSG="Installing packages..."
printInfo "${MSG}"
sudo moss -D "${SOSROOT}" install "${PACKAGES[@]}"

MSG="Preparing local-x86_64 profile directory..."
printInfo "${MSG}"
sudo mkdir -pv ${BOULDERCACHE}/repos/local-x86_64/ || die "${MSG} failed, exiting."

MSG="Creating a moss stone.index file for the local-x86_64 profile..."
printInfo "${MSG}"
sudo moss index ${BOULDERCACHE}/repos/local-x86_64/ || die "${MSG} failed, exiting."

MSG="Adding local-x86_64 profile to list of active repositories..."
printInfo "${MSG}"
sudo moss -D "${SOSROOT}" repo add local-x86_64 file://${BOULDERCACHE}/repos/local-x86_64/stone.index -p10 || die "${MSG} failed, exiting."

MSG="Ensuring that an /etc directory exists in ${SOSROOT}..."
printInfo "${MSG}"
sudo mkdir -pv "${SOSROOT}"/etc/ || die "${MSG} failed, exiting."

MSG="Ensuring that various network protocols function..."
printInfo "${MSG}"
sudo cp -va /etc/protocols "${SOSROOT}"/etc/ || die "${MSG} failed, exiting."

showHelp
# Make it simple to boot into the created sosroot at a later point
createBootScript

# clean up env
unset BOULDERCACHE
unset MSG
unset PACKAGES
unset SOSROOT

unset BOLD
unset RED
unset RESET
unset YELLOW
