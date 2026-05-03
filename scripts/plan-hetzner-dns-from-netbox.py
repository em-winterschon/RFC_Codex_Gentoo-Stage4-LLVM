#!/usr/bin/env python3
"""Generate a dry-run Hetzner DNS RRset plan from NetBox IP addresses."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any
from urllib import parse, request


def load_json_file(path: str) -> Any:
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_token(path: str) -> str:
    return Path(path).read_text(encoding="utf-8").strip()


def request_json(url: str, token: str) -> dict[str, Any]:
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Token {token}"
    req = request.Request(url, headers=headers)
    with request.urlopen(req, timeout=30) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def fetch_netbox_ip_addresses(api_url: str, token: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    base_url = api_url.rstrip("/")
    url = f"{base_url}/api/ipam/ip-addresses/?" + parse.urlencode({"limit": "1000"})
    while url:
        payload = request_json(url, token)
        results = payload.get("results", [])
        if not isinstance(results, list):
            raise RuntimeError("NetBox ip-addresses response did not contain a results list")
        rows.extend(item for item in results if isinstance(item, dict))
        next_url = payload.get("next")
        url = str(next_url) if next_url else ""
    return rows


def netbox_ip_addresses_from_file(path: str) -> list[dict[str, Any]]:
    payload = load_json_file(path)
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict) and isinstance(payload.get("results"), list):
        return [item for item in payload["results"] if isinstance(item, dict)]
    raise RuntimeError(f"{path}: expected a NetBox results object or a list of IP address objects")


def load_zone_groups(args: argparse.Namespace) -> list[dict[str, Any]]:
    if args.zone_groups_json:
        payload = json.loads(args.zone_groups_json)
    elif args.zone_groups_file:
        payload = load_json_file(args.zone_groups_file)
    elif os.getenv("HETZNER_DNS_ZONE_GROUPS_JSON"):
        payload = json.loads(os.environ["HETZNER_DNS_ZONE_GROUPS_JSON"])
    else:
        raise RuntimeError("zone groups are required via --zone-groups-json, --zone-groups-file, or env")

    if not isinstance(payload, list):
        raise RuntimeError("zone groups must be a list")
    groups: list[dict[str, Any]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise RuntimeError(f"zone_groups[{index}] must be a mapping")
        name = str(item.get("name", "")).strip()
        zones = item.get("zones", [])
        if not name:
            raise RuntimeError(f"zone_groups[{index}] missing name")
        if not isinstance(zones, list) or not zones:
            raise RuntimeError(f"zone_groups[{index}] zones must be a non-empty list")
        clean_zones = [normalize_dns_name(str(zone)) for zone in zones if str(zone).strip()]
        groups.append({"name": name, "zones": clean_zones})
    return groups


def normalize_dns_name(value: str) -> str:
    return value.strip().rstrip(".").lower()


def zone_for_name(fqdn: str, zone_groups: list[dict[str, Any]]) -> tuple[str, str] | None:
    matches: list[tuple[int, str, str]] = []
    for group in zone_groups:
        for zone in group["zones"]:
            if fqdn == zone or fqdn.endswith(f".{zone}"):
                matches.append((len(zone), group["name"], zone))
    if not matches:
        return None
    _, group_name, zone = sorted(matches, reverse=True)[0]
    return group_name, zone


def relative_record_name(fqdn: str, zone: str) -> str:
    if fqdn == zone:
        return "@"
    suffix = f".{zone}"
    if fqdn.endswith(suffix):
        return fqdn[: -len(suffix)]
    return fqdn


def parse_ip_address(value: str) -> ipaddress._BaseAddress:
    return ipaddress.ip_interface(value).ip


def generate_dns_plan(
    *,
    ip_addresses: list[dict[str, Any]],
    zone_groups: list[dict[str, Any]],
    default_ttl: int,
    apply: bool,
    allow_delete: bool,
) -> dict[str, Any]:
    rrsets: dict[tuple[str, str], dict[str, Any]] = {}
    skipped: list[dict[str, str]] = []
    grouped_values: dict[tuple[str, str], set[str]] = defaultdict(set)

    for row in ip_addresses:
        address = str(row.get("address", "")).strip()
        dns_name = normalize_dns_name(str(row.get("dns_name", "") or ""))
        if not dns_name:
            skipped.append({"address": address, "dns_name": "", "reason": "missing_dns_name"})
            continue
        if not address:
            skipped.append({"address": "", "dns_name": dns_name, "reason": "missing_address"})
            continue
        try:
            ip_address = parse_ip_address(address)
        except ValueError:
            skipped.append({"address": address, "dns_name": dns_name, "reason": "invalid_address"})
            continue
        match = zone_for_name(dns_name, zone_groups)
        if not match:
            skipped.append({"address": address, "dns_name": dns_name, "reason": "no_matching_zone"})
            continue

        token_group, zone = match
        record_type = "A" if ip_address.version == 4 else "AAAA"
        key = (dns_name, record_type)
        grouped_values[key].add(str(ip_address))
        rrsets[key] = {
            "action": "ensure",
            "token_group": token_group,
            "zone": zone,
            "fqdn": dns_name,
            "relative_name": relative_record_name(dns_name, zone),
            "type": record_type,
            "ttl": default_ttl,
        }

    records: list[dict[str, Any]] = []
    for key, record in sorted(rrsets.items(), key=lambda item: (item[1]["zone"], item[1]["fqdn"], item[1]["type"])):
        records.append({**record, "values": sorted(grouped_values[key])})

    return {
        "apply": apply,
        "allow_delete": allow_delete,
        "source": "netbox",
        "provider": "hetzner_cloud_dns",
        "summary": {
            "input_ip_addresses": len(ip_addresses),
            "records": len(records),
            "skipped": len(skipped),
        },
        "records": records,
        "skipped": skipped,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--netbox-api-url", default=os.getenv("NETBOX_API_URL", "http://172.16.99.62"))
    parser.add_argument("--netbox-token", default=os.getenv("NETBOX_TOKEN", ""))
    parser.add_argument("--netbox-token-file", default=os.getenv("NETBOX_TOKEN_FILE", ""))
    parser.add_argument("--netbox-ip-addresses-file", default="")
    parser.add_argument("--zone-groups-json", default="")
    parser.add_argument("--zone-groups-file", default="")
    parser.add_argument("--default-ttl", type=int, default=300)
    parser.add_argument("--apply", action="store_true", help="Reserved for future write path; plan output remains non-mutating.")
    parser.add_argument("--allow-delete", action="store_true", help="Reserved for future delete plans.")
    parser.add_argument("--format", choices=("json", "text"), default="json")
    parser.add_argument("--output", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    token = args.netbox_token
    if not token and args.netbox_token_file:
        token = load_token(args.netbox_token_file)

    ip_addresses = (
        netbox_ip_addresses_from_file(args.netbox_ip_addresses_file)
        if args.netbox_ip_addresses_file
        else fetch_netbox_ip_addresses(args.netbox_api_url, token)
    )
    plan = generate_dns_plan(
        ip_addresses=ip_addresses,
        zone_groups=load_zone_groups(args),
        default_ttl=args.default_ttl,
        apply=args.apply,
        allow_delete=args.allow_delete,
    )

    if args.format == "json":
        output = json.dumps(plan, indent=2, sort_keys=True) + "\n"
    else:
        lines = [
            f"apply={str(plan['apply']).lower()}",
            f"allow_delete={str(plan['allow_delete']).lower()}",
            f"records={plan['summary']['records']}",
            f"skipped={plan['summary']['skipped']}",
        ]
        for record in plan["records"]:
            lines.append(
                f"{record['action']} {record['zone']} {record['relative_name']} "
                f"{record['type']} {record['ttl']} {' '.join(record['values'])}"
            )
        output = "\n".join(lines) + "\n"

    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
