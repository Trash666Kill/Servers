#!/bin/bash

# - Description: Starts a virtual machine using virsh and optionally restarts libvirtd.
# - Defines a function to restart the libvirtd service, which exits on failure.
# - Starts the VM named VM123456 using `virsh start`.
# - The `main` function calls the VM start routine; restart_libvirtd is defined but unused.
# - To manage other VMs, duplicate and edit the VM123456 function accordingly.

# Restart libvirtd service
restart_libvirtd() {
    local SERVICE=libvirtd
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

VM777095() {
    # Media Converter - Handbrake / noVNC
    virsh start VM777095
}

# Main function to orchestrate the setup
main() {
    restart_lxc

    vmachines="
    VM777095
    "

    for vmachine in $vmachines
    do
        $vmachine
        sleep 16
    done
}

# Execute main function
main