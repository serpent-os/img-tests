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

source ./basic-setup.sh

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
exec sudo systemd-nspawn --bind=${BOULDERCACHE}/ -D ${SOSROOT}/ -b
EOF
}

checkPrereqs
basicSetup
showHelp
# Make it simple to boot into the created sosroot at a later point
createBootScript
cleanEnv
