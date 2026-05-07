#!/usr/bin/env python3
"""Report Hetzner DNS zone inventory and connectivity validation targets."""

from __future__ import annotations

# ruff: noqa: E501

import argparse
import ipaddress
import json
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any
from urllib import error, parse, request

CONNECTIVITY_TYPES = {"A", "AAAA"}


def load_json_file(path: str) -> Any:
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def normalize_dns_name(value: str) -> str:
    return value.strip().strip("{}").strip().rstrip(".").lower()


def clean_counter(counter: Counter[str]) -> dict[str, int]:
    return {key: counter[key] for key in sorted(counter)}


def request_json(url: str, token: str) -> dict[str, Any]:
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = request.Request(url, headers=headers)
    try:
        with request.urlopen(req, timeout=30) as response:  # noqa: S310
            return json.loads(response.read().decode("utf-8"))
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Hetzner DNS GET {url} failed: HTTP {exc.code}: {body}") from exc


def load_token_groups(args: argparse.Namespace) -> list[dict[str, Any]]:
    if args.token_groups_json:
        payload = json.loads(args.token_groups_json)
    elif args.token_groups_file:
        payload = load_json_file(args.token_groups_file)
    elif os.getenv("HETZNER_DNS_TOKEN_GROUPS_JSON"):
        payload = json.loads(os.environ["HETZNER_DNS_TOKEN_GROUPS_JSON"])
    else:
        raise RuntimeError(
            "token groups are required via --token-groups-json, --token-groups-file, or env"
        )

    if not isinstance(payload, list):
        raise RuntimeError("token groups must be a list")

    groups: list[dict[str, Any]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise RuntimeError(f"token_groups[{index}] must be a mapping")
        name = str(item.get("name", "")).strip()
        if not name:
            raise RuntimeError(f"token_groups[{index}] missing name")
        zones = item.get("zones", [])
        if zones is None:
            zones = []
        if not isinstance(zones, list):
            raise RuntimeError(f"token_groups[{index}].zones must be a list")
        groups.append(
            {
                "name": name,
                "token_name": str(item.get("token_name", "")).strip(),
                "api_token": str(item.get("api_token", "")).strip(),
                "zones": [normalize_dns_name(str(zone)) for zone in zones if str(zone).strip()],
            }
        )
    return groups


def extract_list(
    payload: dict[str, Any], keys: tuple[str, ...], context: str
) -> list[dict[str, Any]]:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    raise RuntimeError(f"{context} response did not contain any of: {', '.join(keys)}")


def rrsets_to_records(rrsets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for rrset in rrsets:
        values = rrset.get("records", rrset.get("values", []))
        if isinstance(values, str):
            values = [values]
        if not isinstance(values, list):
            values = []
        for index, value in enumerate(values):
            if isinstance(value, dict):
                record_value = str(value.get("value", "")).strip()
            else:
                record_value = str(value).strip()
            records.append(
                {
                    "id": f"{rrset.get('id', '')}:{index}",
                    "name": rrset.get("name", ""),
                    "type": rrset.get("type", ""),
                    "value": record_value,
                    "ttl": rrset.get("ttl"),
                    "rrset_id": rrset.get("id", ""),
                }
            )
    return records


def extract_records(payload: dict[str, Any], context: str) -> list[dict[str, Any]]:
    rrsets = payload.get("rrsets")
    if isinstance(rrsets, list):
        return rrsets_to_records([item for item in rrsets if isinstance(item, dict)])
    return extract_list(payload, ("records", "results"), context)


def fetch_zones(api_endpoint: str, token: str) -> list[dict[str, Any]]:
    payload = request_json(f"{api_endpoint.rstrip('/')}/zones", token)
    return extract_list(payload, ("zones", "results"), "zones")


def fetch_zone_records(api_endpoint: str, token: str, zone_id: str) -> list[dict[str, Any]]:
    base_url = api_endpoint.rstrip("/")
    urls = [
        f"{base_url}/zones/{parse.quote(zone_id, safe='')}/rrsets",
        f"{base_url}/records?{parse.urlencode({'zone_id': zone_id})}",
        f"{base_url}/zones/{parse.quote(zone_id, safe='')}/records",
    ]
    last_error: RuntimeError | None = None
    for url in urls:
        try:
            payload = request_json(url, token)
            return extract_records(payload, "records")
        except RuntimeError as exc:
            last_error = exc
    raise last_error or RuntimeError(f"could not fetch records for zone id {zone_id}")


def fixture_group(fixture: dict[str, Any], token_group_name: str) -> dict[str, Any] | None:
    for group in fixture.get("token_groups", []):
        if isinstance(group, dict) and group.get("name") == token_group_name:
            return group
    return None


def fixture_zones(fixture: dict[str, Any], token_group_name: str) -> list[dict[str, Any]]:
    group = fixture_group(fixture, token_group_name)
    if not group:
        return []
    zones = group.get("zones", [])
    if not isinstance(zones, list):
        return []
    return [zone for zone in zones if isinstance(zone, dict)]


def fixture_records(
    fixture: dict[str, Any], token_group_name: str, zone_id: str
) -> list[dict[str, Any]]:
    group = fixture_group(fixture, token_group_name)
    if not group:
        return []
    records_by_zone_id = group.get("records_by_zone_id", {})
    if not isinstance(records_by_zone_id, dict):
        return []
    payload = records_by_zone_id.get(zone_id, [])
    if isinstance(payload, dict):
        payload = extract_records(payload, "fixture records")
    if not isinstance(payload, list):
        return []
    return [record for record in payload if isinstance(record, dict)]


def record_fqdn(record_name: str, zone_name: str) -> str:
    name = normalize_dns_name(record_name)
    zone = normalize_dns_name(zone_name)
    if name in ("", "@"):
        return zone
    if name == zone or name.endswith(f".{zone}"):
        return name
    return f"{name}.{zone}"


def validation_targets(fqdn: str, addresses: dict[str, list[str]]) -> list[dict[str, str]]:
    targets = [{"mode": "hostname", "target": fqdn}]
    for record_type in ("A", "AAAA"):
        for address in addresses.get(record_type, []):
            targets.append({"mode": "ip", "target": address})
    return targets


def sorted_host_entry(host: dict[str, Any]) -> dict[str, Any]:
    addresses = {
        record_type: sorted(set(values))
        for record_type, values in host["addresses"].items()
        if values
    }
    entry = {
        "fqdn": host["fqdn"],
        "zone": host["zone"],
        "token_group": host["token_group"],
        "addresses": addresses,
    }
    entry["validation_targets"] = validation_targets(host["fqdn"], addresses)
    return entry


def generate_dns_inventory_report(
    *,
    token_groups: list[dict[str, Any]],
    api_endpoint: str,
    fixture: dict[str, Any] | None = None,
) -> dict[str, Any]:
    summary_records_by_type: Counter[str] = Counter()
    zones_report: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    skipped_records: list[dict[str, str]] = []
    host_map: dict[tuple[str, str], dict[str, Any]] = {}
    zones_configured = 0
    zones_readable = 0
    records_total = 0

    for group in token_groups:
        group_name = group["name"]
        configured_zones = set(group["zones"])
        zones_configured += len(configured_zones)
        try:
            provider_zones = (
                fixture_zones(fixture, group_name)
                if fixture is not None
                else fetch_zones(api_endpoint, group["api_token"])
            )
        except RuntimeError as exc:
            errors.append(
                {
                    "token_group": group_name,
                    "zone": "",
                    "reason": "zone_list_failed",
                    "detail": str(exc),
                }
            )
            continue

        zones_by_name = {
            normalize_dns_name(str(zone.get("name", ""))): zone
            for zone in provider_zones
            if str(zone.get("name", "")).strip()
        }
        selected_zone_names = (
            sorted(configured_zones) if configured_zones else sorted(zones_by_name)
        )
        if not configured_zones:
            zones_configured += len(selected_zone_names)

        for zone_name in selected_zone_names:
            provider_zone = zones_by_name.get(zone_name)
            if not provider_zone:
                errors.append(
                    {"token_group": group_name, "zone": zone_name, "reason": "zone_not_found"}
                )
                zones_report.append(
                    {
                        "token_group": group_name,
                        "zone": zone_name,
                        "zone_id": "",
                        "readable": False,
                        "records_total": 0,
                        "records_by_type": {},
                    }
                )
                continue

            zone_id = str(provider_zone.get("id", "")).strip()
            if not zone_id:
                errors.append(
                    {"token_group": group_name, "zone": zone_name, "reason": "missing_zone_id"}
                )
                zones_report.append(
                    {
                        "token_group": group_name,
                        "zone": zone_name,
                        "zone_id": "",
                        "readable": False,
                        "records_total": 0,
                        "records_by_type": {},
                    }
                )
                continue

            try:
                records = (
                    fixture_records(fixture, group_name, zone_id)
                    if fixture is not None
                    else fetch_zone_records(api_endpoint, group["api_token"], zone_id)
                )
            except RuntimeError as exc:
                errors.append(
                    {
                        "token_group": group_name,
                        "zone": zone_name,
                        "reason": "records_fetch_failed",
                        "detail": str(exc),
                    }
                )
                zones_report.append(
                    {
                        "token_group": group_name,
                        "zone": zone_name,
                        "zone_id": zone_id,
                        "readable": False,
                        "records_total": 0,
                        "records_by_type": {},
                    }
                )
                continue

            zones_readable += 1
            zone_records_by_type: Counter[str] = Counter()
            for record in records:
                record_type = str(record.get("type", "")).strip().upper()
                record_name = str(record.get("name", "")).strip()
                record_value = str(record.get("value", "")).strip()
                if not record_type:
                    skipped_records.append(
                        {
                            "token_group": group_name,
                            "zone": zone_name,
                            "name": record_name,
                            "reason": "missing_record_type",
                        }
                    )
                    continue
                zone_records_by_type[record_type] += 1
                summary_records_by_type[record_type] += 1
                records_total += 1

                fqdn = record_fqdn(record_name, zone_name)
                if record_type not in CONNECTIVITY_TYPES:
                    skipped_records.append(
                        {
                            "token_group": group_name,
                            "zone": zone_name,
                            "name": fqdn,
                            "type": record_type,
                            "reason": "non_connectivity_record_type",
                        }
                    )
                    continue
                if fqdn.startswith("*."):
                    skipped_records.append(
                        {
                            "token_group": group_name,
                            "zone": zone_name,
                            "name": fqdn,
                            "type": record_type,
                            "reason": "wildcard_connectivity_record",
                        }
                    )
                    continue
                try:
                    ip_value = str(ipaddress.ip_address(record_value))
                except ValueError:
                    skipped_records.append(
                        {
                            "token_group": group_name,
                            "zone": zone_name,
                            "name": fqdn,
                            "type": record_type,
                            "reason": "invalid_ip_value",
                        }
                    )
                    continue

                host_key = (zone_name, fqdn)
                host = host_map.setdefault(
                    host_key,
                    {
                        "fqdn": fqdn,
                        "zone": zone_name,
                        "token_group": group_name,
                        "addresses": defaultdict(list),
                    },
                )
                host["addresses"][record_type].append(ip_value)

            zones_report.append(
                {
                    "token_group": group_name,
                    "zone": zone_name,
                    "zone_id": zone_id,
                    "readable": True,
                    "records_total": len(records),
                    "records_by_type": clean_counter(zone_records_by_type),
                }
            )

    flat_hosts = [sorted_host_entry(host) for host in host_map.values()]
    flat_hosts.sort(key=lambda item: (item["zone"], item["fqdn"]))
    hosts_by_zone: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for host in flat_hosts:
        hosts_by_zone[host["zone"]].append(host)

    return {
        "provider": "hetzner_cloud_dns",
        "api_endpoint": api_endpoint,
        "summary": {
            "zones_configured": zones_configured,
            "zones_readable": zones_readable,
            "records_total": records_total,
            "records_by_type": clean_counter(summary_records_by_type),
            "connectivity_hosts": len(flat_hosts),
            "errors": len(errors),
            "skipped_records": len(skipped_records),
        },
        "zones": sorted(zones_report, key=lambda item: (item["token_group"], item["zone"])),
        "connectivity_targets": {
            "hosts_by_zone": {zone: hosts for zone, hosts in sorted(hosts_by_zone.items())},
            "flat_hosts": flat_hosts,
        },
        "skipped_records": sorted(
            skipped_records,
            key=lambda item: (item.get("zone", ""), item.get("name", ""), item.get("reason", "")),
        ),
        "errors": sorted(
            errors,
            key=lambda item: (
                item.get("token_group", ""),
                item.get("zone", ""),
                item.get("reason", ""),
            ),
        ),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--api-endpoint",
        default=os.getenv("HETZNER_DNS_API_ENDPOINT", "https://api.hetzner.cloud/v1"),
    )
    parser.add_argument("--token-groups-json", default="")
    parser.add_argument("--token-groups-file", default="")
    parser.add_argument("--fixture-file", default="")
    parser.add_argument("--format", choices=("json", "text"), default="json")
    parser.add_argument("--output", default="")
    return parser.parse_args()


def render_text(report: dict[str, Any]) -> str:
    lines = [
        f"provider={report['provider']}",
        f"api_endpoint={report['api_endpoint']}",
        f"zones_configured={report['summary']['zones_configured']}",
        f"zones_readable={report['summary']['zones_readable']}",
        f"records_total={report['summary']['records_total']}",
        f"records_by_type={json.dumps(report['summary']['records_by_type'], sort_keys=True)}",
        f"connectivity_hosts={report['summary']['connectivity_hosts']}",
        f"errors={report['summary']['errors']}",
    ]
    for zone in report["zones"]:
        lines.append(
            f"zone {zone['token_group']} {zone['zone']} readable={str(zone['readable']).lower()} "
            f"records={zone['records_total']} types={json.dumps(zone['records_by_type'], sort_keys=True)}"
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    fixture = load_json_file(args.fixture_file) if args.fixture_file else None
    report = generate_dns_inventory_report(
        token_groups=load_token_groups(args),
        api_endpoint=args.api_endpoint.rstrip("/"),
        fixture=fixture,
    )

    if args.format == "json":
        output = json.dumps(report, indent=2, sort_keys=True) + "\n"
    else:
        output = render_text(report)

    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
