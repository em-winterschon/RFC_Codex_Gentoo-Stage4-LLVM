#!/usr/bin/env python3
"""Collect and decode MikroTik SwOS state without writing device config."""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_ENDPOINTS = (
    "sys.b",
    "link.b",
    "sfp.b",
    "lacp.b",
    "snmp.b",
    "backup.swb",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Snapshot MikroTik SwOS HTTP API endpoints and write a decoded summary.",
    )
    parser.add_argument("--host", required=True, help="SwOS host or IP address")
    parser.add_argument("--username", default="admin", help="SwOS username")
    parser.add_argument(
        "--password-env",
        default="SWOS_PASSWORD",
        help="Environment variable containing the SwOS password",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="Directory for raw endpoint files and decoded summary JSON",
    )
    parser.add_argument(
        "--endpoint",
        action="append",
        dest="endpoints",
        help="Endpoint to collect; defaults to core read-only endpoints",
    )
    return parser.parse_args()


def swos_to_python_literal(text: str) -> Any:
    """Parse SwOS JavaScript-ish object literals into Python values."""
    text = re.sub(r"([,{])([A-Za-z_][A-Za-z0-9_]*):", r"\1'\2':", text.strip())
    return ast.literal_eval(text)


def hex_to_bytes(value: str) -> bytes | None:
    if len(value) % 2 != 0:
        return None
    try:
        return bytes.fromhex(value)
    except ValueError:
        return None


def decode_hex_text(value: str) -> str:
    raw = hex_to_bytes(value)
    if raw is None:
        return value
    raw = raw.split(b"\0", 1)[0]
    return raw.decode("utf-8", "replace")


def decode_mac(value: str) -> str:
    raw = hex_to_bytes(value)
    if raw is None or len(raw) != 6:
        return decode_hex_text(value)
    return ":".join(f"{octet:02x}" for octet in raw)


def decode_ipv4_little_endian(value: int) -> str:
    return ".".join(str((value >> shift) & 0xFF) for shift in (0, 8, 16, 24))


def fetch_digest(base_url: str, username: str, password: str, endpoint: str) -> bytes:
    password_manager = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    password_manager.add_password(None, base_url, username, password)
    opener = urllib.request.build_opener(urllib.request.HTTPDigestAuthHandler(password_manager))
    request = urllib.request.Request(f"{base_url}/{endpoint}")
    with opener.open(request, timeout=10) as response:
        return response.read()


def bit_is_set(mask: int, index: int) -> bool:
    return bool(mask & (1 << index))


def summarize(raw: dict[str, bytes]) -> dict[str, Any]:
    parsed: dict[str, Any] = {}
    for endpoint, body in raw.items():
        if endpoint == "backup.swb":
            continue
        parsed[endpoint] = swos_to_python_literal(body.decode("utf-8"))

    sys_b = parsed.get("sys.b", {})
    link_b = parsed.get("link.b", {})
    lacp_b = parsed.get("lacp.b", {})
    snmp_b = parsed.get("snmp.b", {})
    sfp_b = parsed.get("sfp.b", {})

    port_count = int(link_b.get("prt", 0) or 0)
    sfp_count = int(link_b.get("sfp", 0) or 0)
    sfp_offset = int(link_b.get("sfpo", max(port_count - sfp_count, 0)) or 0)
    names = [decode_hex_text(v) for v in link_b.get("nm", [])]
    speeds = link_b.get("spd", [])
    link_mask = int(link_b.get("lnk", 0) or 0)
    enabled_mask = int(link_b.get("en", 0) or 0)

    ports = []
    for idx in range(port_count):
        default_name = f"sfp{idx - sfp_offset + 1}" if idx >= sfp_offset else f"ge{idx + 1}"
        port = {
            "index": idx + 1,
            "name": names[idx] if idx < len(names) and names[idx] else default_name,
            "enabled": bit_is_set(enabled_mask, idx),
            "link": bit_is_set(link_mask, idx),
        }
        if idx < len(speeds):
            port["speed_code"] = speeds[idx]
        ports.append(port)

    lacp_modes = lacp_b.get("mode", [])
    lacp_groups = lacp_b.get("grp", [])
    lacp_partners = lacp_b.get("mac", [])
    lacp = []
    for idx in range(min(port_count, len(lacp_modes))):
        if int(lacp_modes[idx]) or int(lacp_groups[idx] if idx < len(lacp_groups) else 0):
            lacp.append(
                {
                    "port": ports[idx]["name"] if idx < len(ports) else idx + 1,
                    "mode": ["passive", "active", "static"][int(lacp_modes[idx])]
                    if int(lacp_modes[idx]) in (0, 1, 2)
                    else int(lacp_modes[idx]),
                    "group": int(lacp_groups[idx]) if idx < len(lacp_groups) else 0,
                    "partner": decode_mac(lacp_partners[idx])
                    if idx < len(lacp_partners)
                    else "",
                }
            )

    sfp_modules = []
    for idx in range(sfp_count):
        port_idx = sfp_offset + idx
        module: dict[str, Any] = {
            "port": ports[port_idx]["name"] if port_idx < len(ports) else f"sfp{idx + 1}",
        }
        for source_key, target_key in (
            ("vnd", "vendor"),
            ("pnr", "part_number"),
            ("rev", "revision"),
            ("ser", "serial"),
            ("dat", "date"),
            ("typ", "type"),
        ):
            values = sfp_b.get(source_key, [])
            if idx < len(values):
                module[target_key] = decode_hex_text(values[idx]).strip()
        sfp_modules.append(module)

    summary = {
        "host_identity": decode_hex_text(str(sys_b.get("id", ""))),
        "model": decode_hex_text(str(sys_b.get("brd", ""))),
        "serial_number": decode_hex_text(str(sys_b.get("sid", ""))),
        "version": f"{decode_hex_text(str(sys_b.get('ver', '')))}.{sys_b.get('bld', '')}".rstrip("."),
        "management_ip": decode_ipv4_little_endian(int(sys_b["ip"])) if "ip" in sys_b else None,
        "current_ip": decode_ipv4_little_endian(int(sys_b["cip"])) if "cip" in sys_b else None,
        "mac": decode_mac(str(sys_b.get("mac", ""))),
        "address_acquisition": int(sys_b.get("iptp", -1)),
        "management_port_enabled": bool(sys_b.get("mgmt", 0)),
        "allowed_from_ip": decode_ipv4_little_endian(int(sys_b.get("alla", 0))),
        "allowed_from_mask": int(sys_b.get("allm", 0) or 0),
        "snmp": {
            "enabled": bool(snmp_b.get("en", 0)),
            "community": decode_hex_text(str(snmp_b.get("com", ""))),
            "contact": decode_hex_text(str(snmp_b.get("ci", ""))),
            "location": decode_hex_text(str(snmp_b.get("loc", ""))),
        },
        "ports": ports,
        "lacp": lacp,
        "sfp_modules": sfp_modules,
        "collected_at_epoch": int(time.time()),
    }
    return summary


def main() -> int:
    args = parse_args()
    password = os.environ.get(args.password_env)
    if password is None:
        print(f"missing password env var: {args.password_env}", file=sys.stderr)
        return 2

    args.output_dir.mkdir(parents=True, exist_ok=True)
    base_url = f"http://{args.host}"
    endpoints = tuple(args.endpoints or DEFAULT_ENDPOINTS)
    raw: dict[str, bytes] = {}

    for endpoint in endpoints:
        try:
            body = fetch_digest(base_url, args.username, password, endpoint)
        except urllib.error.HTTPError as exc:
            print(f"{endpoint}: HTTP {exc.code}", file=sys.stderr)
            return 1
        raw[endpoint] = body
        (args.output_dir / endpoint).write_bytes(body)

    summary = summarize(raw)
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
