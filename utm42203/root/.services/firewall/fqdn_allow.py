#!/usr/bin/env python3
"""
fqdn_allow.py - Generates (and optionally applies) nftables + dnsmasq rules
to allow a host/subnet to reach one or more FQDNs, following the same
pattern already used manually for 'deb_ips' in network.sh / main.conf.

Rule expressed by this script:
    "Host/subnet <source>, on interface <iface>, needs to reach
     <fqdn(s)> via <proto(s)> [port(s)]"

Typical usage:

    ./fqdn_allow.py \
        --source 172.16.10.0/24 \
        --iface vlan710 \
        --fqdn deb.debian.org security.debian.org \
        --proto tcp --port 80 443 \
        --apply

By default the script runs in DRY-RUN mode: it prints the nft commands
and the lines that would be written to main.conf, but changes nothing.
Use --apply to actually execute.

Requirements: nft, dnsmasq and systemctl available on PATH; root
privileges for --apply.
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


def nft_set_exists(table, name):
    r = subprocess.run(
        ["nft", "list", "set", "inet", table, name],
        capture_output=True, text=True,
    )
    return r.returncode == 0


def nft_rule_exists(table, comment):
    r = subprocess.run(
        ["nft", "-a", "list", "chain", "inet", table, "forward"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return False
    # nft always shows the comment quoted in the listing, regardless of
    # how it was passed when the rule was created.
    return f'comment "{comment}"' in r.stdout


# ---------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------

def validate_source(value):
    try:
        ipaddress.ip_network(value, strict=False)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"'{value}' is not a valid IP/subnet: {exc}")
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


def auto_name(fqdns):
    """Derives a group/set name from the first label of the first FQDN
    + a short hash of all FQDNs (sorted), to avoid collisions between
    groups that share the first label but point to different domains,
    and to reuse the same set when the same FQDN set is allowed again
    (e.g. for another VLAN)."""
    first_label = fqdns[0].split(".")[0]
    digest = hashlib.sha1("|".join(sorted(fqdns)).encode()).hexdigest()[:6]
    return sanitize_name(f"{first_label}_{digest}")


def parse_args():
    p = argparse.ArgumentParser(
        description="Allow a host/subnet to reach FQDN(s) via nftables + dnsmasq nftset.",
    )
    p.add_argument("--name", type=sanitize_name,
                    help="Group/nft set name (e.g. deb_ips). If omitted, it is "
                         "auto-generated from the first label of the first --fqdn "
                         "plus a short hash of the FQDN set.")
    p.add_argument("--source", required=True, type=validate_source,
                    help="Source host or subnet (e.g. 172.16.10.5 or 172.16.10.0/24).")
    p.add_argument("--iface", required=True,
                    help="Source interface/VLAN (iifname), e.g. vlan710.")
    p.add_argument("--fqdn", required=True, nargs="+", type=validate_fqdn,
                    help="One or more FQDNs to allow (e.g. deb.debian.org security.debian.org).")
    p.add_argument("--proto", required=True, nargs="+", choices=["tcp", "udp", "icmp"],
                    help="Protocol(s): tcp, udp and/or icmp.")
    p.add_argument("--port", nargs="+", type=int, default=[],
                    help="Destination port(s) (required if proto includes tcp/udp).")
    p.add_argument("--ip-version", choices=["4", "6", "dual"], default="4",
                    help="IP family of the set (default: 4).")
    p.add_argument("--table", default="firelux", help="nftables table (default: firelux).")
    p.add_argument("--wan-set", default="wan_ifaces", help="WAN interfaces set (default: wan_ifaces).")
    p.add_argument("--timeout", default="6h", help="Timeout of the set's dynamic entries (default: 6h).")
    p.add_argument("--dnsmasq-conf", default="/etc/dnsmasq.d/main.conf",
                    help="dnsmasq config file to update.")
    p.add_argument("--apply", action="store_true",
                    help="Actually execute (nft + write main.conf + restart dnsmasq). Without it, dry-run only.")
    p.add_argument("--no-restart", action="store_true",
                    help="Do not restart dnsmasq after editing main.conf (only relevant with --apply).")
    args = p.parse_args()

    if any(proto in ("tcp", "udp") for proto in args.proto) and not args.port:
        p.error("--port is required when --proto includes tcp and/or udp")

    if args.name is None:
        args.name = auto_name(args.fqdn)

    return args


# ---------------------------------------------------------------------
# nft rule generation
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
            # iface and source are part of the comment (not just name+fam+proto):
            # the same FQDN set can be reused by more than one VLAN/source,
            # and each combination needs its own forward rule.
            comment = f"fqdn_allow:{args.name}:{args.iface}:{args.source}:{fam}:{proto}"
            if nft_rule_exists(args.table, comment):
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


# ---------------------------------------------------------------------
# dnsmasq: nftset= lines
# ---------------------------------------------------------------------

def build_dnsmasq_lines(args, sets):
    lines = []
    for fqdn in args.fqdn:
        for fam, sname in sets.items():
            lines.append(f"nftset=/{fqdn}/{fam}#inet#{args.table}#{sname}")
    return lines


def update_dnsmasq_conf(path, group_name, new_lines, apply_):
    path = Path(path)
    existing = path.read_text().splitlines() if path.exists() else []

    marker_start = f"# --- fqdn_allow: {group_name} (managed by fqdn_allow.py) ---"
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
    """Restarts (not reloads) dnsmasq. A plain 'reload' does not
    reliably re-arm nftset= mappings on some dnsmasq versions, leaving
    the directive present in main.conf but inactive in the running
    daemon until a full restart."""
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


# ---------------------------------------------------------------------
# main
# ---------------------------------------------------------------------

def main():
    args = parse_args()

    if not args.apply:
        msg_warn("DRY-RUN mode - nothing will be changed. Use --apply to execute for real.\n")

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

    print()
    msg_info("Done." if args.apply else "Dry-run complete - review the output above and re-run with --apply.")


if __name__ == "__main__":
    main()