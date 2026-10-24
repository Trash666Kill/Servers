#!/usr/bin/env python3
"""
firelux.py - Generates (and optionally applies) nftables rules, with
three subcommands:

  allow-fqdn  Allow a host/subnet to reach FQDN(s), keeping the matching
              dnsmasq nftset= directive in sync (this is the original
              tool: same nft-set-per-FQDN-group + dnsmasq integration).

  forward     Generic forward rule between two interfaces, optionally
              scoped to a source host/subnet - replaces set_forward /
              set_forward_saddr from network_dynamic.sh.

  dnat        Generic DNAT (prerouting) rule - replaces set_dnat from
              network_dynamic.sh.

Unlike the bash helpers in network_dynamic.sh, every subcommand here is
idempotent: each rule gets a unique nft `comment`, checked before adding,
so re-running the same call twice does not duplicate rules in the chain.

By default the script runs in DRY-RUN mode: it prints the nft commands
(and, for allow-fqdn, the dnsmasq main.conf lines) that would be applied,
but changes nothing. Use --apply to actually execute.

Examples:

    ./firelux.py allow-fqdn \
        --source 172.16.10.0/24 --iface vlan710 \
        --fqdn deb.debian.org security.debian.org \
        --proto tcp --port 80 443 --apply

    ./firelux.py forward \
        --iface br_lan0 --oface vlan710 --proto tcp --port 4242 --apply

    ./firelux.py forward \
        --iface vlan710 --oface br_wan0 --source 172.16.10.1 \
        --proto tcp udp --port 7844 --apply

    ./firelux.py dnat \
        --iface br_lan0 --dest 172.16.2.0/24 \
        --proto tcp --port 4242 --target-ip 172.16.10.1 --apply

Requirements: nft (and, for allow-fqdn, dnsmasq + systemctl) available on
PATH; root privileges for --apply.
"""

import argparse
import hashlib
import ipaddress
import re
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------
# Log helpers (same visual/message pattern used across the project's
# bash scripts: colored bullet + "Action: details..." + non-fatal
# "WARNING: Failed to ..." on command failures)
# ---------------------------------------------------------------------

def msg_info(msg): print(f"\033[32m*\033[0m {msg}")
def msg_warn(msg): print(f"\033[33m*\033[0m {msg}")
def msg_err(msg):  print(f"\033[31m*\033[0m {msg}", file=sys.stderr)


def run(cmd, apply_, warn_on_failure=True):
    """Prints the command; actually executes it only if apply_=True.
    On failure, logs a WARNING and returns False instead of raising,
    matching the '|| msg_warn "WARNING: ..."' pattern used in the
    bash scripts, so one failed rule doesn't abort the whole run."""
    printable = cmd if isinstance(cmd, str) else " ".join(cmd)
    prefix = "  [EXEC]" if apply_ else "  [DRY-RUN]"
    print(f"{prefix} {printable}")
    if not apply_:
        return True
    result = subprocess.run(cmd, shell=isinstance(cmd, str))
    if result.returncode != 0 and warn_on_failure:
        msg_warn(f"WARNING: Failed to apply rule: {printable}")
    return result.returncode == 0


def table_exists(table):
    r = subprocess.run(["nft", "list", "table", "inet", table], capture_output=True, text=True)
    return r.returncode == 0


def chain_exists(table, chain):
    r = subprocess.run(["nft", "list", "chain", "inet", table, chain], capture_output=True, text=True)
    return r.returncode == 0


def nft_set_exists(table, name):
    r = subprocess.run(["nft", "list", "set", "inet", table, name], capture_output=True, text=True)
    return r.returncode == 0


def rule_exists_in_chain(table, chain, comment):
    r = subprocess.run(
        ["nft", "-a", "list", "chain", "inet", table, chain],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return False
    # nft always shows the comment quoted in the listing, regardless of
    # how it was passed when the rule was created.
    return f'comment "{comment}"' in r.stdout


def preflight(table, chains):
    """Sanity check equivalent to the bash scripts' preflight(): makes
    sure the base firewall (table + the relevant chain(s)) is already in
    place before trying to add rules to it."""
    if isinstance(chains, str):
        chains = [chains]
    msg_info("Preflight: checking firewall architecture...")
    if not table_exists(table):
        msg_err(f"ERROR: table inet {table} not found. Ensure the firewall is running.")
        sys.exit(1)
    for chain in chains:
        if not chain_exists(table, chain):
            msg_err(f"ERROR: chain '{chain}' not found in table inet {table}. Ensure the firewall is running.")
            sys.exit(1)
    msg_info("Preflight OK.")


# ---------------------------------------------------------------------
# Shared validators
# ---------------------------------------------------------------------

def validate_source(value):
    try:
        ipaddress.ip_network(value, strict=False)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"'{value}' is not a valid IP/subnet: {exc}")
    return value


def validate_host(value):
    try:
        ipaddress.ip_address(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"'{value}' is not a valid IP address: {exc}")
    return value


def validate_fqdn(value):
    pattern = r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(\.(?!-)[A-Za-z0-9-]{1,63})+\.?$"
    if not re.match(pattern, value):
        raise argparse.ArgumentTypeError(f"'{value}' does not look like a valid FQDN")
    return value.rstrip(".")


def sanitize_name(value):
    name = re.sub(r"[^a-zA-Z0-9_]", "_", value)
    if not re.match(r"^[a-zA-Z_]", name):
        name = f"_{name}"
    return name


def validate_port(value):
    """Accepts either a single port ('443') or an inclusive range
    ('1024-65535'), matching nft's own dport syntax - so ranges like the
    RTP media range don't need a manual nft call anymore."""
    if re.fullmatch(r"\d{1,5}", value):
        port = int(value)
        if not (0 <= port <= 65535):
            raise argparse.ArgumentTypeError(f"port '{value}' is out of range (0-65535)")
        return value

    m = re.fullmatch(r"(\d{1,5})-(\d{1,5})", value)
    if m:
        lo, hi = int(m.group(1)), int(m.group(2))
        if not (0 <= lo <= 65535 and 0 <= hi <= 65535):
            raise argparse.ArgumentTypeError(f"port range '{value}' is out of range (0-65535)")
        if lo >= hi:
            raise argparse.ArgumentTypeError(f"port range '{value}' must have start < end")
        return value

    raise argparse.ArgumentTypeError(
        f"'{value}' is not a valid port or port range (e.g. 443 or 1024-65535)")


def auto_name(fqdns):
    """Derives a group/set name from the first label of the first FQDN
    + a short hash of all FQDNs (sorted), to avoid collisions between
    groups that share the first label but point to different domains,
    and to reuse the same set when the same FQDN set is allowed again
    (e.g. for another VLAN)."""
    first_label = fqdns[0].split(".")[0]
    digest = hashlib.sha1("|".join(sorted(fqdns)).encode()).hexdigest()[:6]
    return sanitize_name(f"{first_label}_{digest}")


# ---------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------

TOP_LEVEL_EXAMPLES = """\
Examples:
  firelux.py allow-fqdn --source 172.16.10.0/24 --iface vlan710 \\
      --fqdn deb.debian.org security.debian.org --proto tcp --port 80 443 --apply

  firelux.py forward --iface br_lan0 --oface vlan710 --proto tcp --port 4242 --apply

  firelux.py dnat --iface br_lan0 --dest 172.16.2.0/24 --proto tcp --port 4242 \\
      --target-ip 172.16.10.1 --target-iface vlan710 --apply

Run a subcommand with -h for more of its own examples (e.g. 'firelux.py dnat -h').
"""

ALLOW_FQDN_EXAMPLES = """\
Examples:
  # Allow the server VLAN to reach the Debian mirrors on 80/443
  firelux.py allow-fqdn \\
      --source 172.16.10.0/24 --iface vlan710 \\
      --fqdn deb.debian.org security.debian.org \\
      --proto tcp --port 80 443 --apply

  # Allow a single workstation host (not the whole VLAN) to reach LXC image servers
  firelux.py allow-fqdn \\
      --source 192.168.10.5/32 --iface vlan910 \\
      --fqdn images.linuxcontainers.org \\
      --proto tcp --port 80 443 --apply

  # WhatsApp: TCP (messaging/media/web) and UDP (call setup) sharing one set
  firelux.py allow-fqdn \\
      --name whatsapp --source 172.16.2.0/24 --iface br_lan0 \\
      --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \\
      --proto tcp --port 443 5222 5223 5228 4244 --apply

  firelux.py allow-fqdn \\
      --name whatsapp --source 172.16.2.0/24 --iface br_lan0 \\
      --fqdn whatsapp.com whatsapp.net wa.me fbcdn.net facebook.com \\
      --proto udp --port 3478 --apply

  # Preview only (default, no --apply): just prints the nft/dnsmasq changes
  firelux.py allow-fqdn --source 172.16.10.0/24 --iface vlan710 \\
      --fqdn deb.debian.org --proto tcp --port 443
"""

FORWARD_EXAMPLES = """\
Examples:
  # Whole-iface forward, no source filter (replaces set_forward)
  firelux.py forward --iface br_lan0 --oface vlan710 --proto tcp --port 4242 --apply

  # Multiple ports in one call
  firelux.py forward --iface vlan910 --oface vlan710 --proto tcp --port 6600 5644 4533 --apply

  # Scoped to a single source host (replaces set_forward_saddr)
  firelux.py forward --iface vlan710 --oface br_wan0 --source 172.16.10.1 \\
      --proto tcp udp --port 7844 --apply

  # Port range (e.g. RTP media for calls), same syntax nft itself uses
  firelux.py forward --iface br_lan0 --oface @wan_ifaces --source 172.16.2.0/24 \\
      --proto udp --port 1024-65535 --apply

  # No NAT needed on a routed local network: open only a specific server
  # (and, optionally, only for specific clients) with --source/--dest
  firelux.py forward --iface br_lan0 --oface vlan710 \\
      --source 172.16.2.0/24 --dest 172.16.10.1 --proto tcp --port 4242 445 --apply

  # ICMP (ping) between two interfaces, no ports needed
  firelux.py forward --iface br_lan0 --oface vlan910 --proto icmp --apply
"""

DNAT_EXAMPLES = """\
Examples:
  # Clients hitting the gateway 172.16.2.254:4242 go to srv79266
  # (also creates the matching forward rule)
  firelux.py dnat --iface br_lan0 --dest 172.16.2.254 \\
      --proto tcp --port 4242 --target-ip 172.16.10.1 --target-iface vlan710 --apply

  # Second server on a different external port (4243 -> 4242 internally).
  # Reusing the same dest/proto/port with another target is rejected:
  # nftables only honours the first matching DNAT.
  firelux.py dnat --iface br_lan0 --dest 172.16.2.254 \\
      --proto tcp --port 4243 --target-ip 172.16.10.2 --target-port 4242 \\
      --target-iface vlan710 --apply

  # Granular: only 172.16.2.2 may use this DNAT (others are dropped by the
  # forward policy). Same dest:port may map to different servers as long
  # as --source differs.
  firelux.py dnat --iface br_lan0 --source 172.16.2.2 --dest 172.16.2.254 \\
      --proto tcp --port 4242 --target-ip 172.16.10.2 --target-iface vlan710 --apply
"""


def build_parser():
    parser = argparse.ArgumentParser(
        description="nftables rule generator: FQDN-based allow rules (with dnsmasq "
                     "nftset sync), generic forward rules, and generic DNAT rules.",
        epilog=TOP_LEVEL_EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # --- allow-fqdn ---------------------------------------------------
    p1 = sub.add_parser(
        "allow-fqdn",
        help="Allow a host/subnet to reach FQDN(s) via nftables + dnsmasq nftset.",
        epilog=ALLOW_FQDN_EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p1.add_argument("--name", type=sanitize_name,
                     help="Group/nft set name (e.g. deb_ips). If omitted, it is "
                          "auto-generated from the first label of the first --fqdn "
                          "plus a short hash of the FQDN set.")
    p1.add_argument("--source", required=True, type=validate_source,
                     help="Source host or subnet (e.g. 172.16.10.5 or 172.16.10.0/24).")
    p1.add_argument("--iface", required=True,
                     help="Source interface/VLAN (iifname), e.g. vlan710.")
    p1.add_argument("--fqdn", required=True, nargs="+", type=validate_fqdn,
                     help="One or more FQDNs to allow (e.g. deb.debian.org security.debian.org).")
    p1.add_argument("--proto", required=True, nargs="+", choices=["tcp", "udp", "icmp"],
                     help="Protocol(s): tcp, udp and/or icmp.")
    p1.add_argument("--port", nargs="+", type=validate_port, default=[],
                     help="Destination port(s) (required if proto includes tcp/udp). "
                          "Accepts single ports and/or ranges, e.g. --port 443 5222 or "
                          "--port 1024-65535.")
    p1.add_argument("--ip-version", choices=["4", "6", "dual"], default="4",
                     help="IP family of the set (default: 4).")
    p1.add_argument("--table", default="firelux", help="nftables table (default: firelux).")
    p1.add_argument("--wan-set", default="wan_ifaces", help="WAN interfaces set (default: wan_ifaces).")
    p1.add_argument("--timeout", default="6h", help="Timeout of the set's dynamic entries (default: 6h).")
    p1.add_argument("--dnsmasq-conf", default="/etc/dnsmasq.d/main.conf",
                     help="dnsmasq config file to update.")
    p1.add_argument("--apply", action="store_true",
                     help="Actually execute (nft + write main.conf + restart dnsmasq). Without it, dry-run only.")
    p1.add_argument("--no-restart", action="store_true",
                     help="Do not restart dnsmasq after editing main.conf (only relevant with --apply).")

    # --- forward --------------------------------------------------------
    p2 = sub.add_parser(
        "forward",
        help="Generic forward rule between two interfaces, replaces "
             "set_forward / set_forward_saddr from network_dynamic.sh.",
        epilog=FORWARD_EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p2.add_argument("--iface", required=True, help="Source interface (iifname), e.g. br_lan0.")
    p2.add_argument("--oface", required=True,
                     help="Destination interface (oifname), e.g. vlan710, br_wan0 or @wan_ifaces.")
    p2.add_argument("--source", type=validate_source,
                     help="Optional source host/subnet filter (ip saddr). Omit to allow the "
                          "whole --iface (like set_forward); provide it to scope to one "
                          "host/subnet (like set_forward_saddr).")
    p2.add_argument("--dest", type=validate_source,
                     help="Optional destination host/subnet filter (ip daddr). Omit to allow "
                          "any destination behind --oface; provide it to open only a "
                          "specific server, e.g. --dest 172.16.10.1.")
    p2.add_argument("--proto", required=True, nargs="+", choices=["tcp", "udp", "icmp"],
                     help="Protocol(s): tcp, udp and/or icmp.")
    p2.add_argument("--port", nargs="+", type=validate_port, default=[],
                     help="Destination port(s) (required if proto includes tcp/udp). "
                          "Accepts single ports and/or ranges, e.g. --port 443 or "
                          "--port 1024-65535.")
    p2.add_argument("--table", default="firelux", help="nftables table (default: firelux).")
    p2.add_argument("--apply", action="store_true",
                     help="Actually execute the nft command. Without it, dry-run only.")

    # --- dnat -------------------------------------------------------
    p3 = sub.add_parser(
        "dnat",
        help="Generic DNAT (prerouting) rule, replaces set_dnat from network_dynamic.sh.",
        epilog=DNAT_EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p3.add_argument("--iface", required=True, help="Source interface (iifname), e.g. br_lan0.")
    p3.add_argument("--source", type=validate_source,
                     help="Optional client host/subnet allowed to use this DNAT (ip saddr). "
                          "Omit to allow any host on --iface. The auto-generated forward "
                          "rule is scoped the same way.")
    p3.add_argument("--dest", required=True, type=validate_source,
                     help="Original destination IP/subnet as seen by clients (ip daddr), "
                          "e.g. 172.16.2.254 (the gateway itself).")
    p3.add_argument("--proto", required=True, choices=["tcp", "udp"], help="Protocol: tcp or udp.")
    p3.add_argument("--port", required=True, type=int, help="Entry port.")
    p3.add_argument("--target-ip", required=True, type=validate_host,
                     help="Internal target IP.")
    p3.add_argument("--target-port", type=int,
                     help="Internal target port (defaults to --port, same as set_dnat's $6).")
    p3.add_argument("--target-iface", required=True,
                     help="Interface where the internal target lives (oifname for the "
                          "auto-generated forward rule), e.g. vlan710.")
    p3.add_argument("--table", default="firelux", help="nftables table (default: firelux).")
    p3.add_argument("--apply", action="store_true",
                     help="Actually execute the nft command. Without it, dry-run only.")

    return parser


def parse_args():
    parser = build_parser()
    args = parser.parse_args()

    if args.command in ("allow-fqdn", "forward"):
        if any(proto in ("tcp", "udp") for proto in args.proto) and not args.port:
            parser.error("--port is required when --proto includes tcp and/or udp")

    if args.command == "allow-fqdn" and args.name is None:
        args.name = auto_name(args.fqdn)

    return args


# ---------------------------------------------------------------------
# allow-fqdn: nft set/rule generation
# ---------------------------------------------------------------------

def set_names(base_name, ip_version):
    if ip_version == "4":
        return {"4": base_name}
    if ip_version == "6":
        return {"6": base_name}
    return {"4": f"{base_name}_v4", "6": f"{base_name}_v6"}


def build_nft_plan(args):
    """Returns a list of (description, command[list]) to execute in order,
    the dict of set names, and whether any set was (re)created in this run.

    A set can be missing even when dnsmasq's main.conf already has the
    matching nftset= line - e.g. after the nftables table was flushed and
    rebuilt (network.sh re-run) while main.conf was untouched. In that
    case dnsmasq is still bound to the old (now gone) kernel object, so a
    restart is required even though the config file itself didn't change.
    """
    plan = []
    sets = set_names(args.name, args.ip_version)
    created_set = False

    for fam, sname in sets.items():
        addr_type = "ipv4_addr" if fam == "4" else "ipv6_addr"
        if not nft_set_exists(args.table, sname):
            plan.append((
                f"Creating set '{sname}' ({addr_type})...",
                ["nft", "add", "set", "inet", args.table, sname,
                 f"{{ type {addr_type}; flags interval, timeout; timeout {args.timeout}; }}"],
            ))
            created_set = True
        else:
            msg_info(f"Set '{sname}' already exists in inet {args.table} - skipping creation")

        daddr_kw = ["ip", "daddr"] if fam == "4" else ["ip6", "daddr"]

        for proto in args.proto:
            # iface, source and ports are all part of the comment (not just
            # name+fam+proto): the same FQDN set can be reused by more than
            # one VLAN/source, and re-running with extra ports for the same
            # combo must not be mistaken for an already-applied rule.
            ports_key = ",".join(args.port) if args.port else "any"
            comment = f"fqdn_allow:{args.name}:{args.iface}:{args.source}:{fam}:{proto}:{ports_key}"
            if rule_exists_in_chain(args.table, "forward", comment):
                msg_info(f"Rule '{comment}' already exists - skipping")
                continue

            cmd = [
                "nft", "add", "rule", "inet", args.table, "forward",
                "iifname", args.iface,
                "oifname", f"@{args.wan_set}",
                "ip", "saddr", args.source,
                *daddr_kw, f"@{sname}",
            ]

            if proto == "icmp":
                cmd += ["meta", "l4proto", "{ icmp, ipv6-icmp }"]
            else:
                ports = ",".join(str(pt) for pt in args.port)
                cmd += [proto, "dport", f"{{ {ports} }}"]

            cmd += ["accept", "comment", f'"{comment}"']
            plan.append((f"Configuring forward rule ({proto}, ipv{fam})...", cmd))

    return plan, sets, created_set


def build_dnsmasq_lines(args, sets):
    lines = []
    for fqdn in args.fqdn:
        for fam, sname in sets.items():
            lines.append(f"nftset=/{fqdn}/{fam}#inet#{args.table}#{sname}")
    return lines


def update_dnsmasq_conf(path, group_name, new_lines, apply_):
    path = Path(path)
    existing = path.read_text().splitlines() if path.exists() else []

    marker_start = f"# --- fqdn_allow: {group_name} (managed by firelux.py) ---"
    marker_end = f"# --- end fqdn_allow: {group_name} ---"

    to_add = [ln for ln in new_lines if ln not in existing]

    if not to_add:
        msg_info(f"main.conf already contains all nftset= lines for '{group_name}'")
        return False

    block = [marker_start] + to_add + [marker_end]
    print(f"  [{'EXEC' if apply_ else 'DRY-RUN'}] appending to {path}:")
    for ln in block:
        print(f"      {ln}")

    if not apply_:
        return True

    with path.open("a") as f:
        f.write("\n" + "\n".join(block) + "\n")
    return True


def restart_dnsmasq(apply_, no_restart):
    """Restarts (not reloads) dnsmasq. A plain 'reload' sends SIGHUP,
    which only re-reads /etc/hosts, dhcp-hostsfile, dhcp-optsfile and
    clears the cache - it does not reprocess main.conf or nftset=
    directives, so it never re-attaches dnsmasq to a recreated nft set."""
    if not apply_ or no_restart:
        return
    msg_info("Validating dnsmasq config (dnsmasq --test)...")
    test = subprocess.run(["dnsmasq", "--test"], capture_output=True, text=True)
    if test.returncode != 0:
        msg_err("dnsmasq --test failed! main.conf was NOT restarted. Fix the config before restarting the service.")
        msg_err(test.stderr.strip())
        sys.exit(1)
    msg_info("Config valid - restarting dnsmasq service...")
    run(["systemctl", "restart", "dnsmasq"], apply_, warn_on_failure=True)


def cmd_allow_fqdn(args):
    preflight(args.table, "forward")

    msg_info(
        f"Group: {args.name} | source: {args.source} via {args.iface} | "
        f"fqdn(s): {', '.join(args.fqdn)} | proto: {', '.join(args.proto)}"
        + (f" | port(s): {', '.join(map(str, args.port))}" if args.port else "")
    )

    plan, sets, created_set = build_nft_plan(args)

    print("\n== nftables ==")
    if not plan:
        msg_info("Nothing to do - sets and rules already exist.")
    for desc, cmd in plan:
        msg_info(desc)
        run(cmd, args.apply)

    print("\n== dnsmasq ==")
    dnsmasq_lines = build_dnsmasq_lines(args, sets)
    conf_changed = update_dnsmasq_conf(args.dnsmasq_conf, args.name, dnsmasq_lines, args.apply)

    if created_set and not conf_changed:
        msg_warn("Set(s) were (re)created this run but main.conf already had the matching "
                  "nftset= line(s) - dnsmasq may still be bound to the old (gone) kernel "
                  "object, so a restart is needed anyway.")

    if conf_changed or created_set:
        restart_dnsmasq(args.apply, args.no_restart)


# ---------------------------------------------------------------------
# forward
# ---------------------------------------------------------------------

def cmd_forward(args):
    preflight(args.table, "forward")

    src_label = args.source if args.source else "any"
    # Only appended when --dest is given, so comments of forward rules
    # created before this option existed keep matching (no duplicates).
    dst_tag = f":dst={args.dest}" if args.dest else ""
    dst_label = args.dest if args.dest else "any"
    msg_info(
        f"iface: {args.iface} -> oface: {args.oface} | source: {src_label} | "
        f"dest: {dst_label} | "
        f"proto: {', '.join(args.proto)}"
        + (f" | port(s): {', '.join(map(str, args.port))}" if args.port else "")
    )

    print("\n== nftables ==")
    for proto in args.proto:
        # ports are part of the comment too, not just iface/oface/source/proto:
        # re-running with a different port set for the same combo must add a
        # new rule, not be mistaken for an already-applied one.
        ports_key = ",".join(args.port) if args.port else "any"
        comment = f"fwd:{args.iface}:{args.oface}:{src_label}:{proto}:{ports_key}{dst_tag}"
        if rule_exists_in_chain(args.table, "forward", comment):
            msg_info(f"Rule '{comment}' already exists - skipping")
            continue

        cmd = ["nft", "add", "rule", "inet", args.table, "forward",
               "iifname", args.iface, "oifname", args.oface]
        if args.source:
            cmd += ["ip", "saddr", args.source]
        if args.dest:
            cmd += ["ip", "daddr", args.dest]

        if proto == "icmp":
            cmd += ["meta", "l4proto", "{ icmp, ipv6-icmp }"]
        else:
            ports = ",".join(str(pt) for pt in args.port)
            cmd += [proto, "dport", f"{{ {ports} }}"]

        cmd += ["accept", "comment", f'"{comment}"']
        msg_info(f"Configuring forward rule ({proto})...")
        run(cmd, args.apply)


# ---------------------------------------------------------------------
# dnat
# ---------------------------------------------------------------------

def find_dnat_conflicts(table, args, target_port, src_tag):
    """nftables evaluates a chain top-down and the first matching DNAT wins.
    Two rules with the same (iface, dest, proto, port[, source]) but a
    different target are therefore never both reachable: the second one is
    dead. Returns the comments of already-installed rules that clash with
    the one we are about to add."""
    r = subprocess.run(["nft", "-a", "list", "chain", "inet", table, "prerouting"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return []
    key = [args.iface, str(args.dest), args.proto, str(args.port)]
    conflicts = []
    for c in re.findall(r'comment "(dnat:[^"]+)"', r.stdout):
        parts = c.split(":")
        # dnat : iface : dest : proto : port : target_ip : target_port [: src=X]
        if len(parts) < 7 or parts[1:5] != key:
            continue
        existing_src = parts[7] if len(parts) > 7 else ""
        if existing_src != src_tag.lstrip(":"):
            continue  # different source scope: not a clash
        if (parts[5], parts[6]) != (args.target_ip, str(target_port)):
            conflicts.append(c)
    return conflicts


def cmd_dnat(args):
    preflight(args.table, ["prerouting", "forward"])

    target_port = args.target_port if args.target_port else args.port
    # Only appended when --source is given, so comments of rules created
    # before this option existed keep matching (no duplicates on re-run).
    src_tag = f":src={args.source}" if args.source else ""

    print("\n== nftables (dnat) ==")
    dnat_comment = (f"dnat:{args.iface}:{args.dest}:{args.proto}:{args.port}:"
                    f"{args.target_ip}:{target_port}{src_tag}")

    if rule_exists_in_chain(args.table, "prerouting", dnat_comment):
        msg_info(f"Rule '{dnat_comment}' already exists - skipping")
    else:
        conflicts = find_dnat_conflicts(args.table, args, target_port, src_tag)
        if conflicts:
            msg_err("ERROR: this DNAT would be shadowed by (or shadow) an existing rule "
                    "with the same match but a different target:")
            for c in conflicts:
                msg_err(f"  {c}")
            msg_err("Use a different --port, a different --dest, or scope it with --source. "
                    "Nothing was changed for this call.")
            sys.exit(1)

        # Source-scoped rules are INSERTed (top of chain) so they are
        # evaluated before any generic (no --source) rule for the same
        # dest/port; generic rules are appended as before.
        verb = "insert" if args.source else "add"
        cmd = ["nft", verb, "rule", "inet", args.table, "prerouting",
               "iifname", args.iface]
        if args.source:
            cmd += ["ip", "saddr", args.source]
        cmd += ["ip", "daddr", args.dest,
                args.proto, "dport", str(args.port),
                "dnat", "to", f"{args.target_ip}:{target_port}",
                "comment", f'"{dnat_comment}"']
        scope = f" from {args.source}" if args.source else ""
        msg_info(f"Configuring DNAT{scope}: {args.iface} {args.dest}:{args.port} -> "
                 f"{args.target_ip}:{target_port} ({args.proto})...")
        run(cmd, args.apply)

    # A DNAT rule only rewrites the destination during prerouting; it does
    # not by itself let the (now re-addressed) packet through the forward
    # chain, which has policy drop. So every DNAT needs a matching forward
    # rule - and since we already know the exact post-NAT ip:port, this
    # rule is scoped to that single host/port (and to --source, if given)
    # rather than the whole iface->oface pair.
    print("\n== nftables (forward) ==")
    fwd_comment = (f"dnat-fwd:{args.iface}:{args.target_iface}:{args.target_ip}:"
                   f"{args.proto}:{target_port}{src_tag}")
    if rule_exists_in_chain(args.table, "forward", fwd_comment):
        msg_info(f"Rule '{fwd_comment}' already exists - skipping")
        return

    fwd_cmd = ["nft", "add", "rule", "inet", args.table, "forward",
               "iifname", args.iface, "oifname", args.target_iface]
    if args.source:
        fwd_cmd += ["ip", "saddr", args.source]
    fwd_cmd += ["ip", "daddr", args.target_ip,
                args.proto, "dport", str(target_port),
                "accept", "comment", f'"{fwd_comment}"']
    msg_info(f"Configuring matching forward rule: {args.iface} -> {args.target_iface} "
             f"(daddr {args.target_ip}, {args.proto}/{target_port}"
             + (f", saddr {args.source}" if args.source else "") + ")...")
    run(fwd_cmd, args.apply)


# ---------------------------------------------------------------------
# main
# ---------------------------------------------------------------------

def main():
    args = parse_args()

    if not args.apply:
        msg_warn("DRY-RUN mode - nothing will be changed. Use --apply to execute for real.\n")

    if args.command == "allow-fqdn":
        cmd_allow_fqdn(args)
    elif args.command == "forward":
        cmd_forward(args)
    elif args.command == "dnat":
        cmd_dnat(args)

    print()
    msg_info("Done." if args.apply else "Dry-run complete - review the output above and re-run with --apply.")


if __name__ == "__main__":
    main()