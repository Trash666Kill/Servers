#!/bin/bash

# Close on any error
set -e

# Tune NIC ring parameters (automatic 50% max or custom values)
tuning() {
    # Internal helper function to calculate and apply tuning for a single interface
    _apply_tuning() {
        local iface="$1"
        local req_rx="$2"
        local req_tx="$3"

        if [ -z "$iface" ]; then
            return 0
        fi

        local final_rx="$req_rx"
        local final_tx="$req_tx"

        # If RX or TX was not specified, query ethtool for pre-set maximums
        if [ -z "$final_rx" ] || [ -z "$final_tx" ]; then
            local ethtool_out
            if ! ethtool_out=$(ethtool -g "$iface" 2>/dev/null); then
                printf "\033[31m*\033[0m ERROR: FAILED TO FETCH RING PARAMETERS FOR INTERFACE %s\n" "$iface" >&2
                return 1
            fi

            local preset_section
            preset_section=$(printf "%s\n" "$ethtool_out" | awk '/Pre-set maximums:/,/Current hardware settings:/')

            # Extract and calculate 50% for RX if auto
            if [ -z "$final_rx" ]; then
                local max_rx
                max_rx=$(printf "%s\n" "$preset_section" | awk '$1 == "RX:" {print $2}')
                if [ -n "$max_rx" ] && [ "$max_rx" -eq "$max_rx" ] 2>/dev/null; then
                    final_rx=$(( max_rx / 2 ))
                else
                    printf "\033[31m*\033[0m ERROR: COULD NOT PARSE MAX RX FOR INTERFACE %s\n" "$iface" >&2
                    return 1
                fi
            fi

            # Extract and calculate 50% for TX if auto
            if [ -z "$final_tx" ]; then
                local max_tx
                max_tx=$(printf "%s\n" "$preset_section" | awk '$1 == "TX:" {print $2}')
                if [ -n "$max_tx" ] && [ "$max_tx" -eq "$max_tx" ] 2>/dev/null; then
                    final_tx=$(( max_tx / 2 ))
                else
                    printf "\033[31m*\033[0m ERROR: COULD NOT PARSE MAX TX FOR INTERFACE %s\n" "$iface" >&2
                    return 1
                fi
            fi
        fi

        # Apply settings
        if ethtool -G "$iface" rx "$final_rx" tx "$final_tx" >/dev/null 2>&1; then
            printf "\033[32m*\033[0m SUCCESS: APPLIED RX %s TX %s ON INTERFACE %s\n" "$final_rx" "$final_tx" "$iface"
        else
            printf "\033[31m*\033[0m ERROR: FAILED TO SET RX %s TX %s ON INTERFACE %s\n" "$final_rx" "$final_tx" "$iface" >&2
            return 1
        fi
    }

    if [ "$#" -eq 0 ]; then
        printf "\033[33m*\033[0m WARNING: NO INTERFACE SPECIFIED FOR TUNING\n" >&2
        return 1
    fi

    local current_iface=""
    local custom_rx=""
    local custom_tx=""

    # Parse arguments iteratively
    while [ "$#" -gt 0 ]; do
        case "$1" in
            rx)
                shift
                custom_rx="$1"
                ;;
            tx)
                shift
                custom_tx="$1"
                ;;
            *)
                # Process queued interface before starting a new one
                if [ -n "$current_iface" ]; then
                    _apply_tuning "$current_iface" "$custom_rx" "$custom_tx"
                    custom_rx=""
                    custom_tx=""
                fi
                current_iface="$1"
                ;;
        esac
        shift
    done

    # Process final interface in sequence
    if [ -n "$current_iface" ]; then
        _apply_tuning "$current_iface" "$custom_rx" "$custom_tx"
    fi
}

# Physical interfaces
physical() {
    lan0() {
        ip link set dev "$LAN0" up
    }

    # Call
    lan0
    # Tuning
    #tuning enp1s0 rx 2048 tx 2048 enp7s0
}

# Gateways required for UTM to work
main_gw() {
    # Default Layer 1 Subnet
    br_lan0() {
        # Interface name constants
        FORMATTED_MAC="dc:a6:32:c9:d9:58"
        BRIDGE_IFACE="br_lan0"

        ip link add name "$BRIDGE_IFACE" type bridge
        ip link set dev "$BRIDGE_IFACE" type bridge vlan_filtering 0
        ip link set dev "$BRIDGE_IFACE" type bridge stp_state 0
        ip link set dev "$BRIDGE_IFACE" address "$FORMATTED_MAC"
        ip link set dev "$LAN0" master "$BRIDGE_IFACE"
        ip link set dev "$BRIDGE_IFACE" up
        ip addr add "$LAN0_IPV4"/"$LAN0_IPV4_PREFIX" dev "$BRIDGE_IFACE"
        ip addr add "$LAN0_IPV6"/"$LAN0_IPV6_PREFIX" dev "$BRIDGE_IFACE"
    }

    # Call
    br_lan0
}

# Subsidiary gateways according to the needs of the environment
subsidiary_gw() {
    #Server
    vlan710() {
        ip link add link "$LAN0" name vlan710 type vlan id 710
        ip link set dev vlan710 up
        ip addr add 172.16.10.254/24 dev vlan710
        ip addr add fda3:d6a1:a4ec:710::254/64 dev vlan710
    }

    #Virtual Machine
    vlan714() {
        ip link add link "$LAN0" name vlan714 type vlan id 714
        ip link set dev vlan714 up
        ip addr add 172.16.14.254/24 dev vlan714
        ip addr add fda3:d6a1:a4ec:714::254/64 dev vlan714
    }

    #Container
    vlan718() {
        ip link add link "$LAN0" name vlan718 type vlan id 718
        ip link set dev vlan718 up
        ip addr add 172.16.18.254/24 dev vlan718
        ip addr add fda3:d6a1:a4ec:718::254/64 dev vlan718
    }

    #Workstation
    vlan910() {
        ip link add link "$LAN0" name vlan910 type vlan id 910
        ip link set dev vlan910 up
        ip addr add 192.168.10.254/24 dev vlan910
        ip addr add fda3:d6a1:a4ec:910::254/64 dev vlan910
    }

    #Wi-Fi (Controller)
    vlan922() {
        ip link add link "$LAN0" name vlan922 type vlan id 922
        ip link set dev vlan922 up
        ip addr add 192.168.22.254/24 dev vlan922
        ip addr add fda3:d6a1:a4ec:922::254/64 dev vlan922
    }

    #DMZ
    vlan966() {
        ip link add link "$LAN0" name vlan966 type vlan id 966
        ip link set dev vlan966 up
        ip addr add 192.168.66.254/24 dev vlan966
        ip addr add fda3:d6a1:a4ec:966::254/64 dev vlan966
    }

    # Call
    vlan710
    #vlan714
    #vlan718
    vlan910
    #vlan922
    vlan966
}

# Main function to orchestrate the setup
main() {
    physical
    main_gw
    subsidiary_gw
}

# Execute main function
main