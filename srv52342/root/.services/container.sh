#!/bin/bash

# Restart lxc service
restart_lxc() {
    local SERVICE=lxc
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

# It starts containers and handles failures without interrupting the flow
start_container() {
    local NAME="$1"
    lxc-start --name "$NAME"
    local EXIT_CODE=$?

    if [[ $EXIT_CODE -ne 0 ]]; then
        printf "\e[31m*\e[0m Warning: Container '%s' failed to start (exit code: %d). Continuing...\n" "$NAME" "$EXIT_CODE"
        return 0
    fi

    printf "\e[32m*\e[0m Container '%s' started successfully.\n" "$NAME"
    return 0
}

# Main function to orchestrate the setup
main() {
    restart_lxc

    start_container "ct160716"
    start_container "ct615237"
    start_container "ct485153"
}

# Execute main function
main