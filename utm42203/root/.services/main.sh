#!/bin/bash

# - Description: Orchestrates network and firewall configuration for virtual machines.
# - Executes network.sh and firewall.sh, with an optional function to restart services.
# - Ensures each script has execute permission and exits on errors using set -e.
# - To add new scripts or services, copy and edit functions like network or others.

# Close on any error
set -e

# Paths to the scripts
SWAP_SCRIPT="/root/.services/swap.sh"
NETWORK_FOLDER="/root/.services/network"
FIREWALL_FOLDER="/root/.services/firewall"

set_printk() {
    local PARAM="kernel.printk"
    local VALUE="4 4 1 7"

    # Attempt to set the kernel parameter value
    sysctl -w "$PARAM"="$VALUE"

    # Check the exit code of the last command
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to set parameter %s.\n" "$PARAM"
        printf "  Check if you are running the command with root privileges (sudo).\n"
        return 1 # Returns an error, but does not close the terminal
    fi

    printf "\e[32m✔\e[0m Parameter '%s' successfully set to '%s'.\n" "$PARAM" "$VALUE"
}

swap() {
    if [[ -f "$SWAP_SCRIPT" ]]; then
        if [[ -x "$SWAP_SCRIPT" ]]; then
            printf "\e[33m*\e[0m Running $SWAP_SCRIPT...\n"
            bash "$SWAP_SCRIPT"
            if [[ $? -ne 0 ]]; then
                printf "\e[31m*\e[0m Error: $SWAP_SCRIPT failed to execute successfully.\n"
                exit 1
            fi
        else
            printf "\e[31m*\e[0m Error: $SWAP_SCRIPT does not have execute permission.\n"
            exit 1
        fi
    else
        printf "\e[31m*\e[0m Error: $SWAP_SCRIPT not found.\n"
        exit 1
    fi
}

domain() {
    # Extract and update the domain.
    DOMAIN=$(awk -F'=' '/^DOMAIN/ {print $2}' /etc/environment)
    sed -i -e "s/^domain=.*/domain=$DOMAIN/" \
    -e "s|^local=.*|local=/$DOMAIN/|" \
    /etc/dnsmasq.d/main.conf
}

network() {
    # Array of firewall scripts
    scripts=(
        "$NETWORK_FOLDER/interfaces.sh"
        "$NETWORK_FOLDER/sync-wan.sh"
        "$NETWORK_FOLDER/sync-timezone.sh"
    )

    # Loop through each script and execute it
    for script in "${scripts[@]}"; do
        bash "$script"
        sleep 1
    done
}

ssh() {
    local SERVICE=ssh
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

# Function to orchestrate the firewall levels
firewall() {
    # Array of firewall scripts
    scripts=(
        "$FIREWALL_FOLDER/a.sh"
        "$FIREWALL_FOLDER/b.sh"
        "$FIREWALL_FOLDER/c.sh"
    )

    # Loop through each script and execute it
    for script in "${scripts[@]}"; do
        bash "$script"
        sleep 1
    done
}

dhcp_dns() {
    local SERVICE=dnsmasq
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

ntp() {
    local SERVICE=chrony
    systemctl restart "$SERVICE"
    if [[ $? -ne 0 ]]; then
        printf "\e[31m*\e[0m Error: Failed to restart $SERVICE.\n"
        exit 1
    fi
}

wan_failover() {
    local SERVICE="wan-failover.service"
    local ATTEMPTS=10
    local SLEEP_SECS=3
    local i

    systemctl reset-failed "$SERVICE" || true

    for ((i=1; i<=ATTEMPTS; i++)); do
        if systemctl restart "$SERVICE"; then
            sleep 1
            if systemctl is-active --quiet "$SERVICE"; then
                printf "\e[32m✔\e[0m %s started successfully.\n" "$SERVICE"
                return 0
            fi
        fi

        printf "\e[33m*\e[0m Attempt %d/%d to start %s failed. Retrying...\n" \
            "$i" "$ATTEMPTS" "$SERVICE"
        sleep "$SLEEP_SECS"
    done

    printf "\e[31m*\e[0m Error: Failed to start %s after %d attempts.\n" \
        "$SERVICE" "$ATTEMPTS"
    journalctl -u "$SERVICE" -n 50 --no-pager || true
    exit 1
}

# Main function to orchestrate the setup
main() {
    SERVICES="
    set_printk
    domain
    network
    ssh
    ntp
    firewall
    dhcp_dns
    wan_failover
    "

    for SERVICE in $SERVICES
    do
        $SERVICE
        sleep 2
    done
}

# Execute main function
main

# Successfully completed
notify_success() {
    # Silently turns off the PWR LED.
    echo 0 | sudo tee /sys/class/leds/PWR/brightness > /dev/null

    # Displays the success message
    printf '\e[32m*\e[0m All scripts and services executed successfully!\n'
}

# Execute happiness
notify_success

exit 0