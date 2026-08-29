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
        server
        workstation
        dmz
    )

    for rule in "${RULES[@]}"; do
        "$rule"
        sleep 1
    done

    msg_info "NETWORK RULES APPLIED SUCCESSFULLY"
}

main