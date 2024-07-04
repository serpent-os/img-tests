#!/usr/bin/env bash
#
# SPDX-License-Identifier: MPL-2.0
#
# Copyright: © 2023-2024 Serpent OS Developers
#

# shared-setup.sh:
# script with shared utility functions for conveniently creating a
# clean serpent-os root directory  directory suitable for use as the
# root in serpent os systemd-nspawn container or linux-kvm kernel driven
# qemu-kvm virtual machine.

# target dirs
# use a default sosroot
SOSROOT="${DESTDIR:-${PWD}/sosroot}"
BOULDERCACHE="${HOME}/.cache/boulder"
#var/cache/boulder"

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
    printError "${*} failed, exiting.\n"
    exit 1
}

checkPrereqs () {
    printInfo "Checking prerequisites..."
    test -f ./pkglist-base || die "\nRun this script from the root of the img-tests/ repo clone!\n"
    test -x $(command -v moss) || die "\n${0} assumes moss is installed. See https://github.com/serpent-os/moss/\n"
}

# base packages
readarray -t PACKAGES < ./pkglist-base

#echo "${PACKAGES[@]}"
#die "Test of PACKAGES."

createNssswitchConf () {
    cat << EOF > ./nsswitch.conf
passwd:         files systemd
group:          files [SUCCESS=merge] systemd
shadow:         files systemd
gshadow:        files systemd

hosts:          mymachines resolve [!UNAVAIL=return] files myhostname dns
networks:       files

protocols:      db files
services:       db files
ethers:         db files
rpc:            db files
EOF
}

basicSetup () {
    # NB: This will fail if moss is an alias!
    local moss="$(command -v moss)"
    printInfo "Using moss binary found here: ${moss} ($(${moss} version))"

    MSG="Removing old ${SOSROOT} directory..."
    printInfo "${MSG}"
    sudo rm -rf "${SOSROOT}" || die "${MSG}"

    MSG="Creating new ${SOSROOT} directory w/baselayout skeleton..."
    printInfo "${MSG}"
    mkdir -pv "${SOSROOT}"/{etc,proc,run,sys,var,var/local,var/cache/boulder} || die "${MSG}"

    # No longer necessary -- moss triggers have been fixed to respect trigger dep order now
    #MSG="Ensuring that we get a working nss-systemd-compatible nssswitch.conf..."
    #printInfo "${MSG}"
    #createNssswitchConf || die "${MSG}"
    #sudo cp -v ./nsswitch.conf "${SOSROOT}"/etc/ || die "${MSG}"

    MSG="Ensuring that various network protocols function..."
    printInfo "${MSG}"
    cp -va /etc/protocols "${SOSROOT}"/etc/ || die "${MSG}"

    MSG="Adding volatile serpent os repository..."
    printInfo "${MSG}"
    ${moss} -D "${SOSROOT}" -y repo add volatile https://dev.serpentos.com/volatile/x86_64/stone.index -p0 || die "${MSG}"

    MSG="Installing packages..."
    printInfo "${MSG}"
    ${moss} -D "${SOSROOT}" -y --cache "${BOULDERCACHE}" install "${PACKAGES[@]}" || die "${MSG}"

    MSG="Setting up an empty root password by default..."
    printInfo "${MSG}"
    sudo chroot "${SOSROOT}" /usr/bin/passwd -d root
    rm -vf issue
    test -f "${SOSROOT}"/etc/issue && cp -v "${SOSROOT}"/etc/issue issue
    echo -e "By default, the root user has no password.\n\nUse the passwd command to change it.\n" >> issue
    mv -v issue "${SOSROOT}"/etc/issue

    MSG="Preparing local-x86_64 profile directory..."
    printInfo "${MSG}"
    mkdir -pv "${SOSROOT}/var/cache/boulder/repos/local-x86_64/" || die "${MSG}"

    MSG="Creating a moss stone.index file for the local-x86_64 profile..."
    printInfo "${MSG}"
    ${moss} -y index "${SOSROOT}/var/cache/boulder/repos/local-x86_64/" || die "${MSG}"

    MSG="Adding local-x86_64 profile to list of active repositories..."
    printInfo "${MSG}"
    sudo chroot ${SOSROOT} ls -l /var/cache/boulder/repos/local-x86_64
    sudo chroot ${SOSROOT} moss -y repo add local-x86_64 file:///var/cache/boulder/repos/local-x86_64/stone.index -p10 || die "${MSG}"
}

# clean up env
cleanEnv () {
    unset BOULDERCACHE
    unset MSG
    unset PACKAGES
    unset SOSROOT

    unset BOLD
    unset RED
    unset RESET
    unset YELLOW
}
