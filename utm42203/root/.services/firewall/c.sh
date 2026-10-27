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

# Rede local roteada: sem DNAT. Os clientes conectam direto no IP real do
# servidor e o firewall (forward policy drop) só libera o que está listado
# aqui. Para restringir a clientes específicos, troque --source pelo host
# (ex.: --source 172.16.2.2).

SRV79266=172.16.10.1
SRV74209=172.16.10.2
LAN=172.16.2.0/24
WKS=192.168.10.0/24

# *br_lan0 to vlan710
#SSH + VNC + SMB/CIFS srv79266
firelux forward \
  --iface br_lan0 --oface vlan710 --source $LAN --dest $SRV79266 \
  --proto tcp --port 4242 5900 445 --apply
#SSH + SMB/CIFS + VNC srv74209
firelux forward \
  --iface br_lan0 --oface vlan710 --source $LAN --dest $SRV74209 \
  --proto tcp --port 4242 445 5900 --apply

#ICMP (ping) LAN -> servers
firelux forward \
  --iface br_lan0 --oface vlan710 --source $LAN --dest $SRV79266 \
  --proto icmp --apply
firelux forward \
  --iface br_lan0 --oface vlan710 --source $LAN --dest $SRV74209 \
  --proto icmp --apply

# *vlan910 to vlan710
#MPD Server + MyMPD Web + Navidrome srv79266
firelux forward \
  --iface vlan910 --oface vlan710 --source $WKS --dest $SRV79266 \
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

# *Allow Dev repos to Servers
firelux allow-fqdn \
  --name dev_repo \
  --source 172.16.10.0/24 \
  --iface vlan710 \
  --fqdn go.dev any-in-2615.1e100.net proxy.golang.org github.com sum.golang.org \
  --proto tcp \
  --port 80 443 \
  --apply

#vlan710 to br_lan0
#SSH Woody Workstation (servers -> 172.16.2.2:22 direto)
firelux forward \
  --iface vlan710 --oface br_lan0 --source 172.16.10.0/24 --dest 172.16.2.2 \
  --proto tcp --port 22 --apply

# *vlan710 to br_wan0 (Internet Gateway)
#Cloudflare Tunnel
firelux forward \
  --iface vlan710 --oface br_wan0 --source $SRV79266 \
  --proto tcp udp --port 7844 --apply

# *Allow WhatsApp to br_lan0
#TCP: web, mensagens, fallback de mídia
firelux allow-fqdn \
  --name whatsapp \
  --source 172.16.2.0/24 \
  --iface br_lan0 \
  --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \
  --proto tcp \
  --port 443 5222 5223 5228 4244 \
  --apply
#UDP: STUN (setup de chamadas), mesmo set de IPs do grupo acima
firelux allow-fqdn \
  --name whatsapp \
  --source 172.16.2.0/24 \
  --iface br_lan0 \
  --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \
  --proto udp \
  --port 3478 \
  --apply
#UDP: mídia RTP (faixa efêmera)
firelux forward \
  --iface br_lan0 --oface @wan_ifaces --source 172.16.2.0/24 \
  --proto udp --port 1024-65535 --apply

# *Allow WhatsApp to vlan910
#TCP: web, mensagens, fallback de mídia
firelux allow-fqdn \
  --name whatsapp \
  --source 192.168.10.0/24 \
  --iface vlan910 \
  --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \
  --proto tcp \
  --port 443 5222 5223 5228 4244 \
  --apply
#UDP: STUN (setup de chamadas), mesmo set de IPs do grupo acima
firelux allow-fqdn \
  --name whatsapp \
  --source 192.168.10.0/24 \
  --iface vlan910 \
  --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \
  --proto udp \
  --port 3478 \
  --apply
#UDP: mídia RTP (faixa efêmera)
firelux forward \
  --iface vlan910 --oface @wan_ifaces --source 192.168.10.0/24 \
  --proto udp --port 1024-65535 --apply