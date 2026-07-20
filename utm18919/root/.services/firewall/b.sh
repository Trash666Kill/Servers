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
root@utm18919:~# cat /root/.services/firewall/b.sh
#!/bin/bash

# ---------------------------------------------------------------------------
# network.sh — Regras de NAT e forwarding por VLAN/bridge.
#
# Este arquivo assume que firewall.sh JÁ FOI EXECUTADO e estabeleceu:
#   - tabela inet firelux
#   - chains input/output/forward com policy drop
#   - chain postrouting com policy accept (para NAT)
#   - chain prerouting com policy accept (para NAT)
#   - set wan_ifaces pré-populado com br_wan0..br_wan9
#   - regras de established,related em forward (via infra_early)
#   - regras de ct state invalid drop em forward (via drop_invalid)
#
# As regras abaixo liberam tráfego NOVO (ct state new) de cada VLAN para
# as WANs. O retorno é coberto pelas regras de established,related já
# instaladas pelo firewall.sh — NÃO precisa duplicar aqui.
#
# IMPORTANTE: o forward está com policy DROP. Isso significa que qualquer
# tráfego que não casar com uma regra explícita de accept será descartado.
# Tráfego de VLAN -> WAN para ping (ICMP) precisa de uma regra explícita.
# ---------------------------------------------------------------------------

set -e

msg_info() { printf "\e[32m*\e[0m %s\n" "$1"; }
msg_warn() { printf "\e[33m*\e[0m %s\n" "$1"; }
msg_err()  { printf "\e[31m*\e[0m %s\n" "$1"; }

default_lan() {
    msg_info "Applying NAT and forward for br_lan0 (172.16.2.0/24)..."

    nft add rule inet firelux postrouting ip saddr 172.16.2.0/24 oifname @wan_ifaces masquerade
    nft add rule inet firelux postrouting ip6 saddr fda3:d6a1:a4ec:2::/64 oifname @wan_ifaces masquerade

    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces meta l4proto { icmp, ipv6-icmp } accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces udp dport 53 accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces tcp dport {80, 443} accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces udp dport {80, 443} accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces tcp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces udp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces tcp dport 4634 accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces udp dport 8443 accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces tcp dport 587 accept
    nft add rule inet firelux forward iifname "br_lan0" oifname @wan_ifaces tcp dport 993 accept
}

server() {
    msg_info "Applying NAT and forward for server VLAN (vlan710)..."

    nft add rule inet firelux postrouting ip saddr 172.16.10.0/24 oifname @wan_ifaces masquerade
    nft add rule inet firelux postrouting oif "vlan710" ip saddr 172.16.10.0/24 snat to 172.16.10.254
    nft add rule inet firelux postrouting ip6 saddr fda3:d6a1:a4ec:710::/64 oifname @wan_ifaces masquerade

    nft add rule inet firelux forward iifname "vlan710" oifname @wan_ifaces meta l4proto { icmp, ipv6-icmp } accept
    nft add rule inet firelux forward iifname "vlan710" oifname @wan_ifaces udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan710" oifname @wan_ifaces tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan710" oifname @wan_ifaces tcp dport {80, 443} accept
}

virtual_machine() {
    msg_info "Applying NAT and forward for VM VLAN (vlan714)..."

    nft add rule inet firelux postrouting ip saddr 172.16.14.0/24 oifname @wan_ifaces masquerade
    nft add rule inet firelux postrouting oif "vlan714" ip saddr 172.16.14.0/24 snat to 172.16.14.254
    nft add rule inet firelux postrouting ip6 saddr fda3:d6a1:a4ec:714::/64 oifname @wan_ifaces masquerade

    nft add rule inet firelux forward iifname "vlan714" oifname @wan_ifaces meta l4proto { icmp, ipv6-icmp } accept
    nft add rule inet firelux forward iifname "vlan714" oifname @wan_ifaces udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan714" oifname @wan_ifaces tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan714" oifname @wan_ifaces tcp dport {80, 443} accept
}

container() {
    msg_info "Applying NAT and forward for container VLAN (vlan718)..."

    nft add rule inet firelux postrouting ip saddr 172.16.18.0/24 oifname @wan_ifaces masquerade
    nft add rule inet firelux postrouting ip6 saddr fda3:d6a1:a4ec:718::/64 oifname @wan_ifaces masquerade

    nft add rule inet firelux forward iifname "vlan718" oifname @wan_ifaces meta l4proto { icmp, ipv6-icmp } accept
    nft add rule inet firelux forward iifname "vlan718" oifname @wan_ifaces udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan718" oifname @wan_ifaces tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan718" oifname @wan_ifaces tcp dport {80, 443} accept
}

workstation() {
    msg_info "Applying NAT and forward for workstation VLAN (vlan910)..."

    nft add rule inet firelux postrouting ip saddr 192.168.10.0/24 oifname @wan_ifaces masquerade
    nft add rule inet firelux postrouting ip6 saddr fda3:d6a1:a4ec:910::/64 oifname @wan_ifaces masquerade

    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces meta l4proto { icmp, ipv6-icmp } accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces tcp dport {80, 443} accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces udp dport {80, 443} accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces tcp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces udp dport {8080, 5060} accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces tcp dport 4634 accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces udp dport 8443 accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces tcp dport 587 accept
    nft add rule inet firelux forward iifname "vlan910" oifname @wan_ifaces tcp dport 993 accept
}

wifi_controller() {
    msg_info "Applying NAT and forward for Wi-Fi controller VLAN (vlan922)..."

    nft add rule inet firelux postrouting ip saddr 192.168.22.0/24 oifname @wan_ifaces masquerade
    nft add rule inet firelux postrouting ip6 saddr fda3:d6a1:a4ec:922::/64 oifname @wan_ifaces masquerade

    nft add rule inet firelux forward iifname "vlan922" oifname @wan_ifaces meta l4proto { icmp, ipv6-icmp } accept
    nft add rule inet firelux forward iifname "vlan922" oifname @wan_ifaces udp dport 53 accept
    nft add rule inet firelux forward iifname "vlan922" oifname @wan_ifaces tcp dport {53, 853} accept
    nft add rule inet firelux forward iifname "vlan922" oifname @wan_ifaces tcp dport {80, 443} accept
}

dmz() {
    msg_info "Applying NAT and forward for DMZ (192.168.66.0/26)..."

    nft add rule inet firelux postrouting ip saddr 192.168.66.0/26 oifname @wan_ifaces masquerade
    nft add rule inet firelux postrouting ip6 saddr fda3:d6a1:a4ec:966::/64 oifname @wan_ifaces masquerade

    # DMZ: liberação ampla para saída — intencional para expor serviços.
    # Tráfego de retorno é coberto por established,related em forward.
    nft add rule inet firelux forward iifname { "vlan966", "br_vlan966" } oifname @wan_ifaces accept
}

# These interfaces will be used in environments where the UTM is virtualized alongside other virtual guests. The aim is to minimize latency.
short_route() {
    # Virtual Machines and Containers
    tap110() {
        msg_info "Applying NAT and forward for VM/CT TAP (tap110)..."

        nft add rule inet firelux postrouting ip saddr 10.0.10.0/24 oifname @wan_ifaces masquerade
        nft add rule inet firelux postrouting oif "enp9s0" ip saddr 10.0.10.0/24 snat to 10.0.10.254

        nft add rule inet firelux forward iifname "enp9s0" oifname @wan_ifaces meta l4proto { icmp, ipv6-icmp } accept
        nft add rule inet firelux forward iifname "enp9s0" oifname @wan_ifaces udp dport 53 accept
        nft add rule inet firelux forward iifname "enp9s0" oifname @wan_ifaces tcp dport {53, 853} accept
        nft add rule inet firelux forward iifname "enp9s0" oifname @wan_ifaces tcp dport {80, 443} accept
        # Cloudflared
        nft add rule inet firelux forward iifname "enp9s0" oifname @wan_ifaces tcp dport 7844 accept
        nft add rule inet firelux forward iifname "enp9s0" oifname @wan_ifaces udp dport 7844 accept
    }

    tap967() {
        msg_info "Applying NAT and forward for DMZ guests TAP (192.168.67.0/24)..."

        nft add rule inet firelux postrouting ip saddr 192.168.67.0/24 oifname @wan_ifaces masquerade

        # DMZ: liberação ampla para saída — intencional para expor serviços.
        # Tráfego de retorno é coberto por established,related em forward.
        nft add rule inet firelux forward iifname enp10s0 oifname @wan_ifaces accept
    }

    # Call
    tap110
    tap967
}

# ---------------------------------------------------------------------------
# Sanidade: antes de aplicar as regras, verifica se o set wan_ifaces existe.
# Se não existir, o firewall.sh não foi executado (ou falhou) e as regras
# `oifname @wan_ifaces` falhariam silenciosamente, causando perda total de
# conectividade para fora.
# ---------------------------------------------------------------------------
preflight() {
    msg_info "Preflight: checking that firewall.sh already ran..."

    if ! nft list set inet firelux wan_ifaces >/dev/null 2>&1; then
        msg_err "ERROR: set 'wan_ifaces' not found in table inet firelux."
        msg_err "       Run firewall.sh BEFORE network.sh."
        exit 1
    fi

    # Também valida que a chain forward existe — defesa em profundidade.
    if ! nft list chain inet firelux forward >/dev/null 2>&1; then
        msg_err "ERROR: chain 'forward' not found in table inet firelux."
        msg_err "       Run firewall.sh BEFORE network.sh."
        exit 1
    fi

    msg_info "Preflight OK — firewall.sh state detected."
}

main() {
    local -a RULES=(
        preflight
        default_lan
        short_route
        server
        workstation
    )

    for rule in "${RULES[@]}"; do
        "$rule"
        sleep 1
    done

    msg_info "NETWORK RULES APPLIED SUCCESSFULLY"
}

main