#!/bin/bash

set -e

msg_info() { printf "\e[32m*\e[0m %s\n" "$1"; }
msg_warn() { printf "\e[33m*\e[0m %s\n" "$1"; }
msg_err()  { printf "\e[31m*\e[0m %s\n" "$1"; }

kernel_hardening() {
    msg_info "Applying Kernel Security Settings..."

    sysctl -w net.ipv4.ip_forward=1 > /dev/null

    sysctl -w net.ipv4.conf.all.rp_filter=2 > /dev/null
    sysctl -w net.ipv4.conf.default.rp_filter=2 > /dev/null

    sysctl -w net.ipv4.tcp_syncookies=1 > /dev/null

    sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 > /dev/null

    sysctl -w net.ipv4.icmp_ignore_bogus_error_responses=1 > /dev/null

    sysctl -w net.ipv4.conf.all.accept_source_route=0 > /dev/null
    sysctl -w net.ipv4.conf.default.accept_source_route=0 > /dev/null

    sysctl -w net.ipv4.conf.all.accept_redirects=0 > /dev/null
    sysctl -w net.ipv4.conf.default.accept_redirects=0 > /dev/null

    sysctl -w net.ipv4.conf.all.send_redirects=0 > /dev/null
    sysctl -w net.ipv4.conf.default.send_redirects=0 > /dev/null

    sysctl -w net.ipv4.conf.all.secure_redirects=0 > /dev/null
    sysctl -w net.ipv4.conf.default.secure_redirects=0 > /dev/null

    sysctl -w net.ipv4.tcp_timestamps=1 > /dev/null

    sysctl -w net.ipv4.tcp_window_scaling=1 > /dev/null

    sysctl -w net.ipv4.tcp_sack=1 > /dev/null

    sysctl -w net.ipv4.conf.all.log_martians=1 > /dev/null
    sysctl -w net.ipv4.conf.default.log_martians=1 > /dev/null

    sysctl -w net.ipv4.tcp_keepalive_time=600 > /dev/null
    sysctl -w net.ipv4.tcp_keepalive_intvl=60 > /dev/null
    sysctl -w net.ipv4.tcp_keepalive_probes=3 > /dev/null

    sysctl -w net.ipv4.conf.all.arp_ignore=1 > /dev/null
    sysctl -w net.ipv4.conf.all.arp_announce=2 > /dev/null

    sysctl -w net.ipv4.tcp_fin_timeout=10 > /dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=1 > /dev/null
    sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 > /dev/null

    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 > /dev/null
    sysctl -w net.ipv4.tcp_synack_retries=1 > /dev/null

    sysctl -w net.core.somaxconn=8192 > /dev/null
    sysctl -w net.core.netdev_max_backlog=5000 > /dev/null

    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null
    sysctl -w net.ipv6.conf.default.forwarding=1 > /dev/null

    # IPv6: NÃO tocar em accept_ra aqui.
    #
    # O wan_failover.py é a autoridade sobre accept_ra por interface. Ele
    # configura:
    #   - net.ipv6.conf.default.accept_ra=2   (antes de qualquer forwarding)
    #   - net.ipv6.conf.all.accept_ra=2
    #   - net.ipv6.conf.<br_wanN>.accept_ra=2 (por bridge WAN)
    # e as LANs mantêm o default da distro (geralmente 1, mas isso só vale
    # quando forwarding=0, então em um router é efetivamente ignorado).
    #
    # O valor correto depende do papel da interface:
    #   - WAN (recebe RA do ISP):      accept_ra=2
    #   - LAN (o router anuncia RA):   accept_ra=0  (configurado pelo radvd)
    # Como não temos como saber aqui quais interfaces são quais, deixamos
    # a decisão para quem tem esse conhecimento (wan_failover.py para WANs;
    # radvd/daemons de LAN para as demais).

    sysctl -w net.ipv6.conf.all.accept_redirects=0 > /dev/null
    sysctl -w net.ipv6.conf.default.accept_redirects=0 > /dev/null

    sysctl -w net.ipv6.conf.all.accept_source_route=0 > /dev/null
    sysctl -w net.ipv6.conf.default.accept_source_route=0 > /dev/null

    if ! lsmod | grep -q "^nf_conntrack"; then
        msg_info "nf_conntrack not loaded, attempting modprobe..."
        if ! modprobe nf_conntrack; then
            msg_warn "Failed to load nf_conntrack module, skipping conntrack tuning"
            return 0
        fi
        msg_info "nf_conntrack loaded successfully"
    fi

    if ! sysctl -w net.netfilter.nf_conntrack_max=1048576 > /dev/null 2>&1; then
        msg_warn "nf_conntrack_max: param unavailable, skipping"
    fi

    if ! sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close_wait=60 > /dev/null 2>&1; then
        msg_warn "nf_conntrack_tcp_timeout_close_wait: skipping"
    fi

    if ! sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=30 > /dev/null 2>&1; then
        msg_warn "nf_conntrack_tcp_timeout_time_wait: skipping"
    fi

    msg_info "Kernel hardening applied"
}

ids() {
    local SERVICE=firelux
    if systemctl list-units --full -all | grep -Fq "$SERVICE.service"; then
        systemctl restart "$SERVICE"
    fi
}

restart_nftables() {
    local SERVICE=nftables
    msg_info "Restarting $SERVICE..."
    if ! systemctl restart "$SERVICE"; then
        msg_err "ERROR: Failed to restart $SERVICE."
        exit 1
    fi
}

flush_nftables() {
    msg_info "Flushing ruleset..."
    nft flush ruleset
}

main_table() {
    msg_info "Creating table..."
    nft add table inet firelux
}

chains() {
    msg_info "Creating chains..."
    nft add chain inet firelux input   { type filter hook input   priority 0      \; policy drop \; }
    nft add chain inet firelux output  { type filter hook output  priority 0      \; policy drop \; }
    nft add chain inet firelux forward { type filter hook forward priority filter \; policy drop \; }
    nft add chain inet firelux prerouting  { type nat hook prerouting  priority dstnat \; policy accept \; }
    nft add chain inet firelux postrouting { type nat hook postrouting priority srcnat \; policy accept \; }
}

loopback_early() {
    msg_info "Allowing loopback (early, before all other rules)..."
    nft add rule inet firelux input  iif "lo" accept
    nft add rule inet firelux output oif "lo" accept
}

# ---------------------------------------------------------------------------
# CRITICAL INFRASTRUCTURE (DHCP client, ICMPv6 ND, established)
#
# These rules MUST be installed before `drop_invalid` and `wan_guard` so that:
#   - udhcpc renewals (DHCPv4 unicast from the leased IP) are not discarded
#     as "invalid" by conntrack. The initial DISCOVER uses 0.0.0.0:68 and
#     reaches us via broadcast-accepting raw sockets, but the RENEW at T1
#     is a plain unicast UDP packet and MUST traverse the normal stack.
#   - ICMPv6 Neighbor Discovery and Router Advertisements are never
#     subject to rate-limit or invalid-state drops. Without these, SLAAC
#     silently breaks after any conntrack churn.
#   - DHCPv6 client (ports 546/547) survives the same scrutiny.
#   - Established/related connections shortcut the rest of the rule set
#     (standard nftables best practice — invalid drops still run for
#     state==invalid because the shortcut only matches established,related).
# ---------------------------------------------------------------------------

infra_early() {
    msg_info "Installing early infrastructure rules (DHCP, ICMPv6 ND, established)..."

    # ── Established / related: fast path for returning traffic ────────────
    nft add rule inet firelux input   ct state established,related accept
    nft add rule inet firelux output  ct state established,related accept
    nft add rule inet firelux forward ct state established,related accept

    # ── DHCPv4 client — both phases ───────────────────────────────────────
    nft add rule inet firelux output udp sport 68 udp dport 67 accept
    nft add rule inet firelux input  udp sport 67 udp dport 68 accept

    # ── DHCPv6 client ─────────────────────────────────────────────────────
    nft add rule inet firelux output udp sport 546 udp dport 547 accept
    nft add rule inet firelux input  udp sport 547 udp dport 546 accept

    # ── ICMPv6 Neighbor Discovery & MLD ───────────────────────────────────
    nft add rule inet firelux input icmpv6 type { \
        nd-router-solicit, \
        nd-router-advert, \
        nd-neighbor-solicit, \
        nd-neighbor-advert, \
        ind-neighbor-solicit, \
        ind-neighbor-advert, \
        mld-listener-query, \
        mld-listener-report, \
        mld-listener-done, \
        mld2-listener-report \
    } accept

    nft add rule inet firelux output icmpv6 type { \
        nd-router-solicit, \
        nd-router-advert, \
        nd-neighbor-solicit, \
        nd-neighbor-advert, \
        ind-neighbor-solicit, \
        ind-neighbor-advert, \
        mld-listener-query, \
        mld-listener-report, \
        mld-listener-done, \
        mld2-listener-report \
    } accept

    nft add rule inet firelux forward icmpv6 type { \
        nd-neighbor-solicit, \
        nd-neighbor-advert \
    } accept
}

drop_invalid() {
    msg_info "Configuring Invalid State Drops and Protocol Protections..."

    nft add rule inet firelux input   ct state invalid drop
    nft add rule inet firelux forward ct state invalid drop
    nft add rule inet firelux output  ct state invalid drop

    nft add rule inet firelux input   ip  frag-off \& 0x1fff != 0 drop
    nft add rule inet firelux forward ip  frag-off \& 0x1fff != 0 drop
    nft add rule inet firelux input   frag frag-off \> 0 drop
    nft add rule inet firelux forward frag frag-off \> 0 drop

    nft add rule inet firelux input   ct state new meter conn_rate_in_v4   { ip  saddr timeout 60s limit rate over 100/second burst 50  packets } drop
    nft add rule inet firelux input   ct state new meter conn_rate_in_v6   { ip6 saddr timeout 60s limit rate over 100/second burst 50  packets } drop
    nft add rule inet firelux forward ct state new meter conn_rate_fwd_v4  { ip  saddr timeout 60s limit rate over 500/second burst 200 packets } drop
    nft add rule inet firelux forward ct state new meter conn_rate_fwd_v6  { ip6 saddr timeout 60s limit rate over 500/second burst 200 packets } drop

    nft add rule inet firelux input   tcp flags \& \(fin\|syn\|rst\|psh\|ack\|urg\) == 0x0 drop
    nft add rule inet firelux forward tcp flags \& \(fin\|syn\|rst\|psh\|ack\|urg\) == 0x0 drop

    nft add rule inet firelux input   tcp flags \& \(fin\|syn\|rst\|psh\|ack\|urg\) == fin\|psh\|urg drop
    nft add rule inet firelux forward tcp flags \& \(fin\|syn\|rst\|psh\|ack\|urg\) == fin\|psh\|urg drop

    nft add rule inet firelux input   tcp flags \& \(fin\|syn\) == fin\|syn drop
    nft add rule inet firelux forward tcp flags \& \(fin\|syn\) == fin\|syn drop

    nft add rule inet firelux input   tcp flags \& \(syn\|rst\) == syn\|rst drop
    nft add rule inet firelux forward tcp flags \& \(syn\|rst\) == syn\|rst drop

    nft add rule inet firelux input   tcp flags \& \(fin\|syn\|rst\|psh\|ack\|urg\) \< fin drop
    nft add rule inet firelux forward tcp flags \& \(fin\|syn\|rst\|psh\|ack\|urg\) \< fin drop
}

wan_set() {
    msg_info "Creating WAN interface set..."

    nft add set inet firelux wan_ifaces { type ifname \; flags interval \; }

    # Pré-popula br_wan0..br_wan9. O nftables resolve o nome da interface
    # em runtime, então listar todas é seguro e garante failover automático
    # sem recarregar regras.
    local -a WAN_LIST=()
    local i
    for i in {0..9}; do
        WAN_LIST+=("\"br_wan${i}\"")
    done

    local WAN_JOINED
    WAN_JOINED=$(IFS=,; echo "${WAN_LIST[*]}")

    nft add element inet firelux wan_ifaces "{ $WAN_JOINED }"

    msg_info "WAN set populated: $WAN_JOINED"
}

lan_set() {
    msg_info "Creating LAN interface set..."

    nft add set inet firelux lan_ifaces { type ifname \; flags interval \; }

    # Inclua aqui somente interfaces LAN onde o roteador deve SERVIR
    # DHCPv4, DHCPv6, DNS/DoT e NTP para clientes.
    #
    # Com base na topologia mostrada até agora, este conjunto cobre:
    #   - LAN principal
    #   - VLANs internas com clientes
    #
    # Interfaces deliberadamente NÃO incluídas por padrão:
    #   - WANs
    #   - DMZ (vlan966 / br_vlan966)
    #   - switch management (vlan76)
    #
    # Se você também quiser servir esses serviços em outras bridges/VLANs,
    # basta acrescentar os nomes abaixo.
    local -a LAN_LIST=(
        "\"br_lan0\""
        "\"vlan710\""
        "\"vlan910\""
        "\"vlan966\""
    )

    local LAN_JOINED
    LAN_JOINED=$(IFS=,; echo "${LAN_LIST[*]}")

    nft add element inet firelux lan_ifaces "{ $LAN_JOINED }"

    msg_info "LAN set populated: $LAN_JOINED"
}

wan_guard() {
    msg_info "Configuring WAN interface guard..."

    # Category 1 - FULL BLOCK on WAN (in + out + forward).
    local WAN_GUARD_FULL_TCP="444"
    local WAN_GUARD_FULL_UDP=""

    local PORT
    for PORT in $WAN_GUARD_FULL_TCP; do
        nft add rule inet firelux input    iifname @wan_ifaces tcp dport "$PORT" drop
        nft add rule inet firelux output   oifname @wan_ifaces tcp sport "$PORT" drop
        nft add rule inet firelux output   oifname @wan_ifaces tcp dport "$PORT" drop
        nft add rule inet firelux forward  oifname @wan_ifaces tcp dport "$PORT" drop
        nft add rule inet firelux forward  iifname @wan_ifaces tcp dport "$PORT" drop
    done

    for PORT in $WAN_GUARD_FULL_UDP; do
        nft add rule inet firelux input    iifname @wan_ifaces udp dport "$PORT" drop
        nft add rule inet firelux output   oifname @wan_ifaces udp sport "$PORT" drop
        nft add rule inet firelux output   oifname @wan_ifaces udp dport "$PORT" drop
        nft add rule inet firelux forward  oifname @wan_ifaces udp dport "$PORT" drop
        nft add rule inet firelux forward  iifname @wan_ifaces udp dport "$PORT" drop
    done

    # Category 2 - INBOUND/FORWARD BLOCK on WAN (router-as-server denied,
    # router-as-client allowed).
    local WAN_GUARD_SERVE_TCP="53 853"
    local WAN_GUARD_SERVE_UDP="53 67 123 547"

    for PORT in $WAN_GUARD_SERVE_TCP; do
        nft add rule inet firelux input    iifname @wan_ifaces tcp dport "$PORT" drop
        nft add rule inet firelux forward  iifname @wan_ifaces tcp dport "$PORT" drop
    done

    for PORT in $WAN_GUARD_SERVE_UDP; do
        nft add rule inet firelux input    iifname @wan_ifaces udp dport "$PORT" drop
        nft add rule inet firelux forward  iifname @wan_ifaces udp dport "$PORT" drop
    done
}

martians() {
    msg_info "Configuring martian packet drops on WAN..."

    nft add rule inet firelux input   iifname @wan_ifaces ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, 169.254.0.0/16, 100.64.0.0/10, 224.0.0.0/4, 240.0.0.0/4, 0.0.0.0/8 } drop
    nft add rule inet firelux forward iifname @wan_ifaces ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, 169.254.0.0/16, 100.64.0.0/10, 224.0.0.0/4, 240.0.0.0/4, 0.0.0.0/8 } drop

    # Em INPUT no WAN, NÃO derrubar fe80::/10:
    # RA, DHCPv6 e parte do ND chegam de origem link-local.
    nft add rule inet firelux input   iifname @wan_ifaces ip6 saddr { fc00::/7, ::1/128, ::/128, 100::/64, 2001:db8::/32, fec0::/10 } drop

    # Em FORWARD, pode continuar bloqueando link-local.
    nft add rule inet firelux forward iifname @wan_ifaces ip6 saddr { fc00::/7, fe80::/10, ::1/128, ::/128, 100::/64, 2001:db8::/32, fec0::/10 } drop
}

whitelist() {
    msg_info "Configuring whitelist Sets..."

    nft add set inet firelux whitelist_manual_v4 { type ipv4_addr \; flags interval \; }
    nft add rule inet firelux input   ip saddr @whitelist_manual_v4 accept
    nft add rule inet firelux forward ip saddr @whitelist_manual_v4 accept

    nft add set inet firelux whitelist_manual_v6 { type ipv6_addr \; flags interval \; }
    nft add rule inet firelux input   ip6 saddr @whitelist_manual_v6 accept
    nft add rule inet firelux forward ip6 saddr @whitelist_manual_v6 accept
}

blacklist() {
    msg_info "Configuring Blacklist Sets..."

    punishment() {
        nft add set inet firelux blacklist_punishment_v4 { type ipv4_addr \; flags interval, timeout \; }
        nft add rule inet firelux input   ip saddr @blacklist_punishment_v4 drop
        nft add rule inet firelux forward ip saddr @blacklist_punishment_v4 drop
        nft add rule inet firelux output  ip daddr @blacklist_punishment_v4 drop

        nft add set inet firelux blacklist_punishment_v6 { type ipv6_addr \; flags interval, timeout \; }
        nft add rule inet firelux input   ip6 saddr @blacklist_punishment_v6 drop
        nft add rule inet firelux forward ip6 saddr @blacklist_punishment_v6 drop
        nft add rule inet firelux output  ip6 daddr @blacklist_punishment_v6 drop
    }

    domain() {
        priority() {
            nft add set inet firelux blacklist_priority_v4 { type ipv4_addr \; flags interval \; }
            nft add rule inet firelux input   ip saddr @blacklist_priority_v4 drop
            nft add rule inet firelux forward ip saddr @blacklist_priority_v4 drop
            nft add rule inet firelux output  ip daddr @blacklist_priority_v4 drop

            nft add set inet firelux blacklist_priority_v6 { type ipv6_addr \; flags interval \; }
            nft add rule inet firelux input   ip6 saddr @blacklist_priority_v6 drop
            nft add rule inet firelux forward ip6 saddr @blacklist_priority_v6 drop
            nft add rule inet firelux output  ip6 daddr @blacklist_priority_v6 drop
        }

        bulk() {
            nft add set inet firelux blacklist_bulk_v4 { type ipv4_addr \; flags interval \; }
            nft add rule inet firelux input   ip saddr @blacklist_bulk_v4 drop
            nft add rule inet firelux forward ip saddr @blacklist_bulk_v4 drop
            nft add rule inet firelux output  ip daddr @blacklist_bulk_v4 drop

            nft add set inet firelux blacklist_bulk_v6 { type ipv6_addr \; flags interval \; }
            nft add rule inet firelux input   ip6 saddr @blacklist_bulk_v6 drop
            nft add rule inet firelux forward ip6 saddr @blacklist_bulk_v6 drop
            nft add rule inet firelux output  ip6 daddr @blacklist_bulk_v6 drop
        }

        priority
        bulk
    }

    country() {
        nft add set inet firelux blacklist_country_v4 { type ipv4_addr \; flags interval \; }
        nft add rule inet firelux input   ip saddr @blacklist_country_v4 drop
        nft add rule inet firelux forward ip saddr @blacklist_country_v4 drop
        nft add rule inet firelux output  ip daddr @blacklist_country_v4 drop

        nft add set inet firelux blacklist_country_v6 { type ipv6_addr \; flags interval \; }
        nft add rule inet firelux input   ip6 saddr @blacklist_country_v6 drop
        nft add rule inet firelux forward ip6 saddr @blacklist_country_v6 drop
        nft add rule inet firelux output  ip6 daddr @blacklist_country_v6 drop
    }

    auto() {
        nft add set inet firelux blacklist_auto_v4 { type ipv4_addr \; flags interval \; }
        nft add rule inet firelux input   ip saddr @blacklist_auto_v4 drop
        nft add rule inet firelux forward ip saddr @blacklist_auto_v4 drop
        nft add rule inet firelux output  ip daddr @blacklist_auto_v4 drop

        nft add set inet firelux blacklist_auto_v6 { type ipv6_addr \; flags interval \; }
        nft add rule inet firelux input   ip6 saddr @blacklist_auto_v6 drop
        nft add rule inet firelux forward ip6 saddr @blacklist_auto_v6 drop
        nft add rule inet firelux output  ip6 daddr @blacklist_auto_v6 drop
    }

    manual() {
        nft add set inet firelux blacklist_manual_v4 { type ipv4_addr \; flags interval \; }
        nft add rule inet firelux input   ip saddr @blacklist_manual_v4 drop
        nft add rule inet firelux forward ip saddr @blacklist_manual_v4 drop
        nft add rule inet firelux output  ip daddr @blacklist_manual_v4 drop

        nft add set inet firelux blacklist_manual_v6 { type ipv6_addr \; flags interval \; }
        nft add rule inet firelux input   ip6 saddr @blacklist_manual_v6 drop
        nft add rule inet firelux forward ip6 saddr @blacklist_manual_v6 drop
        nft add rule inet firelux output  ip6 daddr @blacklist_manual_v6 drop
    }

    punishment
    domain
    country
    auto
    manual
}

ddos_protection() {
    msg_info "Configuring DDoS Protection and Limits (WAN only)..."

    # INPUT: protege apenas tráfego que ENTRA pela WAN no roteador
    nft add rule inet firelux input iifname @wan_ifaces tcp flags syn \
        meter syn_flood_in_v4 { ip saddr timeout 43200s limit rate over 20/second } drop

    nft add rule inet firelux input iifname @wan_ifaces tcp flags syn \
        meter syn_flood_in_v6 { ip6 saddr timeout 43200s limit rate over 20/second } drop

    nft add rule inet firelux input iifname @wan_ifaces ct state new \
        meter conn_limit_in_v4 { ip saddr ct count over 100 } drop

    nft add rule inet firelux input iifname @wan_ifaces ct state new \
        meter conn_limit_in_v6 { ip6 saddr ct count over 100 } drop

    # FORWARD: protege apenas tráfego vindo DA WAN para dentro
    nft add rule inet firelux forward iifname @wan_ifaces tcp flags syn \
        meter syn_flood_fwd_v4 { ip saddr timeout 43200s limit rate over 20/second } drop

    nft add rule inet firelux forward iifname @wan_ifaces tcp flags syn \
        meter syn_flood_fwd_v6 { ip6 saddr timeout 43200s limit rate over 20/second } drop

    nft add rule inet firelux forward iifname @wan_ifaces ct state new \
        meter conn_limit_fwd_v4 { ip saddr ct count over 100 } drop

    nft add rule inet firelux forward iifname @wan_ifaces ct state new \
        meter conn_limit_fwd_v6 { ip6 saddr ct count over 100 } drop
}

brute_protection() {
    msg_info "Configuring Brute Protection (Honeypot, WAN only)..."

    local HONEYPOT_PORTS="21 22 23 25 110 143 445 465 587 1433 3000 3128 3306 3389 5432 5900 6379 8000 8080 8443 8888 9200 10000 27017"

    if [[ -z "$HONEYPOT_PORTS" ]]; then
        msg_warn "HONEYPOT_PORTS is empty, skipping brute_protection"
        return 0
    fi

    local NFT_PORT_SET
    NFT_PORT_SET="{ $(echo "$HONEYPOT_PORTS" | tr -s ' ' ',' | sed 's/^,//;s/,$//') }"

    msg_info "Honeypot ports: $NFT_PORT_SET"

    nft add rule inet firelux input iifname @wan_ifaces tcp dport "$NFT_PORT_SET" \
        limit rate 60/minute burst 20 packets log prefix \"INPUT_DROP: \" group 10 drop

    nft add rule inet firelux input iifname @wan_ifaces tcp dport "$NFT_PORT_SET" drop
}

host() {
    # NOTA:
    #   - DHCPv4 client, DHCPv6 client, ICMPv6 ND e established/related já
    #     foram aceitos em infra_early().
    #   - Aqui entram as regras complementares de host:
    #       * ICMP/ICMPv6 extras
    #       * DHCPv4 server para LAN
    #       * DHCPv6 server para LAN
    #       * DNS/DoT server para LAN
    #       * NTP server para LAN
    #       * DNS/NTP cliente upstream para a Internet
    #       * HTTP/HTTPS outbound
    #       * SSH de gerência
    #
    # Os serviços de borda (DNS/DoT/NTP/DHCP-server) continuam bloqueados no
    # WAN por wan_guard(). O set @lan_ifaces limita explicitamente esses
    # serviços apenas às interfaces LAN escolhidas em lan_set().

    icmp() {
        nft add rule inet firelux input  icmp type { echo-request, echo-reply, destination-unreachable, time-exceeded } accept
        nft add rule inet firelux output icmp type { echo-request, echo-reply, destination-unreachable, time-exceeded } accept
    }

    icmpv6_extras() {
        # ND, NS, NA, MLD já estão em infra_early. Aqui ficam apenas os tipos
        # restantes que não são de descoberta de vizinho mas são úteis para
        # funcionamento correto de PMTU/IPv6.
        nft add rule inet firelux input icmpv6 type { \
            destination-unreachable, \
            packet-too-big, \
            time-exceeded, \
            parameter-problem, \
            echo-request, \
            echo-reply \
        } accept

        nft add rule inet firelux output icmpv6 type { \
            destination-unreachable, \
            packet-too-big, \
            time-exceeded, \
            parameter-problem, \
            echo-request, \
            echo-reply \
        } accept

        nft add rule inet firelux forward icmpv6 type { \
            destination-unreachable, \
            packet-too-big, \
            time-exceeded, \
            parameter-problem, \
            echo-request, \
            echo-reply \
        } accept
    }

    dhcp4_server() {
        # Clientes LAN -> servidor DHCPv4 no roteador
        nft add rule inet firelux input  iifname @lan_ifaces udp sport 68 udp dport 67 accept

        # Servidor DHCPv4 no roteador -> clientes LAN
        nft add rule inet firelux output oifname @lan_ifaces udp sport 67 udp dport 68 accept
    }

    dhcp6_server() {
        # Clientes LAN -> servidor DHCPv6 no roteador
        nft add rule inet firelux input  iifname @lan_ifaces udp sport 546 udp dport 547 accept

        # Servidor DHCPv6 no roteador -> clientes LAN
        nft add rule inet firelux output oifname @lan_ifaces udp sport 547 udp dport 546 accept
    }

    dns() {
        # Router como cliente DNS upstream (IPv4 + IPv6)
        nft add rule inet firelux output udp dport 53 accept
        nft add rule inet firelux output tcp dport { 53, 853 } accept

        # Router como servidor DNS/DoT apenas na LAN (IPv4 + IPv6)
        nft add rule inet firelux input  iifname @lan_ifaces udp dport 53 accept
        nft add rule inet firelux input  iifname @lan_ifaces tcp dport { 53, 853 } accept
        nft add rule inet firelux output oifname @lan_ifaces udp sport 53 accept
        nft add rule inet firelux output oifname @lan_ifaces tcp sport { 53, 853 } accept
    }

    ntp() {
        # Router como cliente NTP upstream (IPv4 + IPv6)
        nft add rule inet firelux output udp dport 123 accept

        # Router como servidor NTP apenas na LAN (IPv4 + IPv6)
        nft add rule inet firelux input  iifname @lan_ifaces udp dport 123 accept
        nft add rule inet firelux output oifname @lan_ifaces udp sport 123 accept
    }

    web() {
        nft add rule inet firelux output tcp dport 80  accept
        nft add rule inet firelux output tcp dport 443 accept
    }

    ssh() {
        nft add rule inet firelux input  ip saddr 172.16.2.0/24 iif "br_lan0" tcp dport 444 accept
        nft add rule inet firelux output ip daddr 172.16.2.0/24 oif "br_lan0" tcp sport 444 accept

        nft add rule inet firelux input  ip6 saddr fda3:d6a1:a4ec:2::/64 iif "br_lan0" tcp dport 444 accept
        nft add rule inet firelux output ip6 daddr fda3:d6a1:a4ec:2::/64 oif "br_lan0" tcp sport 444 accept
    }

    icmp
    icmpv6_extras
    dhcp4_server
    dhcp6_server
    dns
    ntp
    web
    ssh
}

setup_logging() {
    msg_info "Configuring end-of-chain logging via NFLOG..."

    nft add rule inet firelux input   limit rate 20/minute burst 10 packets log group 10 prefix \"INPUT_DROP: \"
    nft add rule inet firelux forward limit rate 20/minute burst 10 packets log group 10 prefix \"FORWARD_DROP: \"
    nft add rule inet firelux output  limit rate 20/minute burst 10 packets log group 10 prefix \"OUTPUT_DROP: \"
}

main() {
    # ─────────────────────────────────────────────────────────────────────
    # ORDEM DE EXECUÇÃO — CRÍTICA
    #
    # 1. kernel_hardening, restart_nftables, flush_nftables, main_table,
    #    chains — setup inicial.
    # 2. loopback_early — loopback sempre liberado antes de tudo.
    # 3. infra_early  — DHCP client (v4/v6), ICMPv6 ND, established,related.
    # 4. drop_invalid — agora seguro: tráfego legítimo de infra já passou.
    # 5. wan_set      — set de interfaces WAN (br_wan0..br_wan9).
    # 6. lan_set      — set de interfaces LAN onde o router SERVE
    #                   DHCP/DNS/DoT/NTP para clientes.
    # 7. wan_guard    — bloqueios WAN (serviços de borda não respondem no WAN).
    # 8. martians     — bogons em WAN.
    # 9. whitelist / blacklist — listas de acesso.
    # 10. ddos_protection, brute_protection — proteção de borda.
    # 11. host        — liberações finais do próprio roteador.
    # 12. setup_logging — NFLOG no final de cada chain.
    # ─────────────────────────────────────────────────────────────────────
    local -a RULES=(
        kernel_hardening
        restart_nftables
        flush_nftables
        main_table
        chains
        loopback_early
        infra_early
        drop_invalid
        wan_set
        lan_set
        wan_guard
        martians
        whitelist
        blacklist
        ddos_protection
        brute_protection
        host
        setup_logging
    )

    for rule in "${RULES[@]}"; do
        "$rule"
        sleep 1
    done

    msg_info "FIREWALL APPLIED SUCCESSFULLY (IPv4 + IPv6)"
}

main