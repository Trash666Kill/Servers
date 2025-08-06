#!/bin/bash

# - Description: Starts a container using lxc and optionally restarts lxc.
# - Defines a function to restart the lxc service, which exits on failure.
# - Starts the CT named CT123456 using `lxc-start`.
# - The `main` function calls the CT start routine; restart_lxc is defined but unused.
# - To manage other CTs, duplicate and edit the CT123456 function accordingly.

# Restart lxc service
restart_lxc() {
    local SERVICE=lxc
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

CT212810() {
    # Music Streaming - Navidrome
    lxc-start --name CT212810
}

CT915942() {
    # Video Streamin - Jellyfin
    lxc-start --name CT915942
}

CT879677() {
    # Web P2P Client - Transmission
    lxc-start --name CT879677
}

CT442878() {
    # Music Streaming - MPD Server with USB DAC passthrough
    lxc-start --name CT442878
}

CT418656() {
    # AI Code Editor - Windsurf
    lxc-start --name CT418656
}

# Main function to orchestrate the setup
main() {
    restart_lxc

    containers="
    CT212810
    CT915942
    CT442878
    CT418656
    "

    for container in $containers
    do
        $container
        sleep 8
    done
}

# Execute main function
main