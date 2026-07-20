#!/bin/bash

# Close on any error
set -e

# Physical interfaces
physical() {
    nic0() {
        ip link set dev "$NIC0_ALT" up
    }

    # Call
    nic0
}

# Virtual interfaces
virtual() {
    br_tap110() {
        ip tuntap add tap110 mode tap
        ip link set dev tap110 up
        ip link add name br_tap110 type bridge
        ip link set dev br_tap110 type bridge stp_state 0
        ip link set dev tap110 master br_tap110
        ip link set dev br_tap110 up
        ip addr add 10.0.10.253/24 dev br_tap110
        ip addr add fdef:0102:5d30::254/64 dev br_tap110
    }

    add_ipv6_default_route() {
        local bridge_iface="$1"
        local ipv6

        ipv6=$(ip -6 neigh show dev "$bridge_iface" | awk '{print $1}')

        if [ -z "$ipv6" ]; then
            printf "\033[33m*\033[0m WARNING: NO IPV6 NEIGHBOR FOUND FOR INTERFACE %s\n" "$bridge_iface" >&2
        elif ! ip -6 route add default via "$ipv6" dev "$bridge_iface"; then
            printf "\033[33m*\033[0m WARNING: FAILED TO ADD DEFAULT IPV6 ROUTE VIA %s ON %s\n" "$ipv6" "$bridge_iface" >&2
        fi
    }

    br_tap967() {
        ip tuntap add tap967 mode tap
        ip link set dev tap967 up
        ip link add name br_tap967 type bridge
        ip link set dev br_tap967 type bridge stp_state 0
        ip link set dev tap967 master br_tap967
        ip link set dev br_tap967 up
        ip addr add 192.168.67.253/24 dev br_tap967
    }

    br_vlan710() {
        # Extract MAC address from interface name (format: enxAABBCCDDEEFF)
        RAW_MAC=$(printf "%s" "$NIC0_ALT" | sed 's/enx//')
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
        VLAN_IFACE="vlan710"
        BRIDGE_IFACE="br_vlan710"
        VLAN_ID=710

        ip link add link "$PHYSICAL_INTERFACE" name "$VLAN_IFACE" type vlan id "$VLAN_ID"
        ip link set dev "$VLAN_IFACE" up
        ip link add name "$BRIDGE_IFACE" type bridge
        ip link set dev "$BRIDGE_IFACE" type bridge vlan_filtering 0
        ip link set dev "$BRIDGE_IFACE" type bridge stp_state 0
        ip link set dev "$BRIDGE_IFACE" address "$FORMATTED_MAC"
        ip link set dev "$VLAN_IFACE" master "$BRIDGE_IFACE"
        ip link set dev "$BRIDGE_IFACE" up
        ip addr add "$IPV4"/"$MASK" dev "$BRIDGE_IFACE"
        ip route add default via "$GW" dev "$BRIDGE_IFACE"
        add_ipv6_default_route "$BRIDGE_IFACE"
    }

    # Call
    br_tap110
    br_tap967
    br_vlan710
}

# Main function to orchestrate the setup
main() {
    physical
    virtual
}

# Execute main function
main