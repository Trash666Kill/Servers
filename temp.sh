#!/bin/bash

# Resolve firelux.py relative to this script's own location, so c.sh keeps
# working regardless of where it's called from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRELUX="${SCRIPT_DIR}/firelux.py"

if [ ! -f "$FIRELUX" ]; then
    echo "ERROR: firelux.py not found at ${FIRELUX}" >&2
    exit 1
fi

firelux() { python3 "$FIRELUX" "$@"; }

# *br_lan0 to vlan710
# SSH, VNC e SMB para srv79266 (172.16.10.1)
firelux forward \
  --iface br_lan0 --oface vlan710 \
  --source 172.16.2.0/24 --dest 172.16.10.1 \
  --proto tcp --port 4242 5900 445 --apply

# SSH e SMB para srv74209 (172.16.10.2)
firelux forward \
  --iface br_lan0 --oface vlan710 \
  --source 172.16.2.0/24 --dest 172.16.10.2 \
  --proto tcp --port 4242 445 --apply

# *vlan910 to vlan710
# MPD, MyMPD e Navidrome para srv79266 (172.16.10.1)
firelux forward \
  --iface vlan910 --oface vlan710 \
  --source 192.168.10.0/24 --dest 172.16.10.1 \
  --proto tcp --port 6600 5644 4533 --apply

# *Allow Debian repos to Servers
firelux allow-fqdn \
  --name debian_repo \
  --source 172.16.10.0/24 \
  --iface vlan710 \
  --fqdn deb.debian.org security.debian.org debian.map.fastlydns.net \
  --proto tcp \
  --port 80 443 \
  --apply

# *Allow LXC repos to Servers
firelux allow-fqdn \
  --name lxc_img_repo \
  --source 172.16.10.0/24 \
  --iface vlan710 \
  --fqdn images.linuxcontainers.org \
  --proto tcp \
  --port 80 443 \
  --apply

# vlan710 to br_lan0
# SSH do srv79266 (172.16.10.1) para Woody Workstation (172.16.2.2)
firelux forward \
  --iface vlan710 --oface br_lan0 \
  --source 172.16.10.1 --dest 172.16.2.2 \
  --proto tcp --port 22 --apply

# *vlan710 to br_wan0 (Internet Gateway)
# Cloudflare Tunnel
firelux forward \
  --iface vlan710 --oface br_wan0 --source 172.16.10.1 \
  --proto tcp udp --port 7844 --apply

# *Allow WhatsApp to br_lan0
# TCP: web, mensagens, fallback de mídia
firelux allow-fqdn \
  --name whatsapp \
  --source 172.16.2.0/24 \
  --iface br_lan0 \
  --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \
  --proto tcp \
  --port 443 5222 5223 5228 4244 \
  --apply
# UDP: STUN (setup de chamadas), mesmo set de IPs do grupo acima
firelux allow-fqdn \
  --name whatsapp \
  --source 172.16.2.0/24 \
  --iface br_lan0 \
  --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \
  --proto udp \
  --port 3478 \
  --apply
# UDP: mídia RTP (faixa efêmera)
firelux forward \
  --iface br_lan0 --oface @wan_ifaces --source 172.16.2.0/24 \
  --proto udp --port 1024-65535 --apply

# *Allow WhatsApp to vlan910
# TCP: web, mensagens, fallback de mídia
firelux allow-fqdn \
  --name whatsapp \
  --source 192.168.10.0/24 \
  --iface vlan910 \
  --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \
  --proto tcp \
  --port 443 5222 5223 5228 4244 \
  --apply
# UDP: STUN (setup de chamadas), mesmo set de IPs do grupo acima
firelux allow-fqdn \
  --name whatsapp \
  --source 192.168.10.0/24 \
  --iface vlan910 \
  --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \
  --proto udp \
  --port 3478 \
  --apply
# UDP: mídia RTP (faixa efêmera)
firelux forward \
  --iface vlan910 --oface @wan_ifaces --source 192.168.10.0/24 \
  --proto udp --port 1024-65535 --apply