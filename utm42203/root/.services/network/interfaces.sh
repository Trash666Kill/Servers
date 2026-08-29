#!/bin/bash

# Close on any error
set -e

# Physical interfaces
physical() {
    lan0() {
        ip link set dev "$LAN0_ALT" up
    }

    # Call
    lan0
}

# Gateways required for UTM to work
main_gw() {
    # Default Layer 1 Subnet
    br_lan0() {
        # Extract MAC address from interface name (format: enxAABBCCDDEEFF)
        RAW_MAC=$(printf "%s" "$LAN0_ALT" | sed 's/enx//')
        FORMATTED_MAC=$(printf "%s" "$RAW_MAC" | sed 's/../&:/g;s/:$//')

        # Find the real interface name by matching MAC address in sysfs
        PHYSICAL_INTERFACE=$(grep -rl "$FORMATTED_MAC" /sys/class/net/*/address 2>/dev/null \
            | awk -F'/' '{print $5}' \
            | head -1)

        # Abort if no matching interface was found
        if [ -z "$PHYSICAL_INTERFACE" ]; then
            printf "\033[31m*\033[0m ERROR: NO VALID INTERFACE FOUND FOR MAC %s\n" "$FORMATTED_MAC" >&2
            return 1
        fi

        # Interface name constants
        BRIDGE_IFACE="br_lan0"

        ip link add name "$BRIDGE_IFACE" type bridge
        ip link set dev "$BRIDGE_IFACE" type bridge vlan_filtering 0
        ip link set dev "$BRIDGE_IFACE" type bridge stp_state 0
        ip link set dev "$BRIDGE_IFACE" address "$FORMATTED_MAC"
        ip link set dev "$LAN0_ALT" master "$BRIDGE_IFACE"
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
        ip link add link "$LAN0_ALT" name vlan710 type vlan id 710
        ip link set dev vlan710 up
        ip addr add 172.16.10.254/24 dev vlan710
        ip addr add fda3:d6a1:a4ec:710::254/64 dev vlan710
    }

    #Virtual Machine
    vlan714() {
        ip link add link "$LAN0_ALT" name vlan714 type vlan id 714
        ip link set dev vlan714 up
        ip addr add 172.16.14.254/24 dev vlan714
        ip addr add fda3:d6a1:a4ec:714::254/64 dev vlan714
    }

    #Container
    vlan718() {
        ip link add link "$LAN0_ALT" name vlan718 type vlan id 718
        ip link set dev vlan718 up
        ip addr add 172.16.18.254/24 dev vlan718
        ip addr add fda3:d6a1:a4ec:718::254/64 dev vlan718
    }

    #Workstation
    vlan910() {
        ip link add link "$LAN0_ALT" name vlan910 type vlan id 910
        ip link set dev vlan910 up
        ip addr add 192.168.10.254/24 dev vlan910
        ip addr add fda3:d6a1:a4ec:910::254/64 dev vlan910
    }

    #Wi-Fi (Controller)
    vlan922() {
        ip link add link "$LAN0_ALT" name vlan922 type vlan id 922
        ip link set dev vlan922 up
        ip addr add 192.168.22.254/24 dev vlan922
        ip addr add fda3:d6a1:a4ec:922::254/64 dev vlan922
    }

    #DMZ
    vlan966() {
        ip link add link "$LAN0_ALT" name vlan966 type vlan id 966
        ip link set dev vlan966 up
        ip addr add 192.168.66.254/24 dev vlan966
        ip addr add fda3:d6a1:a4ec:966::254/64 dev vlan966
    }

    # Call
    vlan710
    vlan714
    vlan718
    vlan910
    vlan922
    vlan966
}

# These interfaces will be used in environments where the UTM is virtualized alongside other virtual guests. The aim is to minimize latency.
short_route() {
    # Server
    br_tap110() {
        ip link set dev enx525400459eb5 up
        ip addr add 10.0.10.254/24 dev enx525400459eb5
    }

    # DMZ
    br_tap967() {
        ip link set dev enx525400f4c454 up
        ip addr add 192.168.67.254/24 dev enx525400f4c454
    }

    # Call
    br_tap110
    br_tap967
}

# Main function to orchestrate the setup
main() {
    physical
    main_gw
    subsidiary_gw
    short_route
}

# Execute main function
main