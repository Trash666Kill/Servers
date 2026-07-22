#!/bin/bash

# ---------------------------------------------------------------------------
# network_dynamic.sh — Regras Dinâmicas de DNAT e Forwarding.
#
# Este script fornece uma estrutura genérica e parametrizada para suportar
# múltiplas VLANs, ranges de IP e diferentes tipos de dispositivos/serviços.
# ---------------------------------------------------------------------------

set -e

# Helpers de Log no padrão do projeto
msg_info() { printf "\e[32m*\e[0m %s\n" "$1"; }
msg_warn() { printf "\e[33m*\e[0m %s\n" "$1"; }
msg_err()  { printf "\e[31m*\e[0m %s\n" "$1"; }

# ---------------------------------------------------------------------------
# Função Genérica de DNAT
# Argumentos:
#   $1 = Interface de Origem (ex: br_lan0, vlan910)
#   $2 = IP/Subnet de Destino Original (ex: 172.16.2.0/24)
#   $3 = Protocolo (tcp / udp)
#   $4 = Porta de Entrada (ex: 4242, 80)
#   $5 = IP Interno do Alvo (ex: 172.16.10.1)
#   $6 = Porta Interna do Alvo (Opcional - se omitida, assume a mesma do $4)
# ---------------------------------------------------------------------------
set_dnat() {
    local iifname="$1"
    local orig_daddr="$2"
    local proto="$3"
    local port="$4"
    local target_ip="$5"
    local target_port="${6:-$port}" # Usa a porta de entrada se a interna não for passada

    msg_info "Configuring DNAT: ${iifname} -> ${target_ip}:${target_port} (${proto}/${port})..."

    nft add rule inet firelux prerouting iifname "$iifname" ip daddr "$orig_daddr" "$proto" dport "$port" dnat to "${target_ip}:${target_port}" || \
        msg_warn "WARNING: Failed to apply DNAT rule for ${target_ip}"
}

# ---------------------------------------------------------------------------
# Função Genérica de Forward
# Argumentos:
#   $1 = Interface de Origem (In)
#   $2 = Interface de Destino (Out)
#   $3 = Protocolo (tcp / udp)
#   $4 = Porta (pode ser uma única porta "80" ou um set "{ 80, 443 }")
# ---------------------------------------------------------------------------
set_forward() {
    local iifname="$1"
    local oifname="$2"
    local proto="$3"
    local port="$4"

    msg_info "Configuring Forward: ${iifname} -> ${oifname} (${proto}/${port})..."

    nft add rule inet firelux forward iifname "$iifname" oifname "$oifname" "$proto" dport $port accept || \
        msg_warn "WARNING: Failed to apply Forward rule from ${iifname} to ${oifname}"
}

# ---------------------------------------------------------------------------
# Blocos de Dispositivos / VLANs
# ---------------------------------------------------------------------------

configure_servers() {
    msg_info "Processing Application Servers (VLAN 710)..."

    # Libera o Forward da LAN0 para a VLAN dos Servidores na porta 4242
    set_forward "br_lan0" "vlan710" "tcp" "4242"
    # Virtual Machines and Container
    set_forward "vlan910" "enp9s0" "tcp" "6600"
    set_forward "vlan910" "enp9s0" "tcp" "5644"

    # Aplica os DNATs apontando para os servidores internos correspondentes
    set_dnat "br_lan0" "172.16.2.0/24" "tcp" "4242" "172.16.10.1"
    set_dnat "br_lan0" "172.16.2.0/24" "tcp" "4242" "172.16.10.2"
    # Virtual Machines and Containers
    set_dnat "vlan910" "192.168.10.0/24" "tcp" "6600" "10.0.10.5"
    set_dnat "vlan910" "192.168.10.0/24" "tcp" "5644" "10.0.10.5"

}

# Verificação de sanidade local (Garante que a tabela principal existe)
preflight() {
    msg_info "Preflight: checking firewall architecture..."

    if ! nft list table inet firelux >/dev/null 2>&1; then
        msg_err "ERROR: table inet firelux not found. Ensure firewall is running."
        exit 1
    fi
}

# Bloco principal de execução
main() {
    local -a RULES=(
        preflight
        configure_servers
    )

    for rule in "${RULES[@]}"; do
        "$rule"
        sleep 1
    done

    msg_info "ALL DYNAMIC RULES CONFIGURATION PROCESS COMPLETED"
}

main