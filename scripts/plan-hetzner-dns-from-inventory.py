#!/usr/bin/env python3
"""Generate Hetzner DNS desired state from inventory-intake host/VIP records."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


def require_yaml() -> Any:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - depends on local environment
        raise SystemExit("PyYAML is required. Install python yaml support first.") from exc
    return yaml


def load_json_file(path: str) -> Any:
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_yaml_file(path: Path) -> dict[str, Any]:
    yaml = require_yaml()
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise RuntimeError(f"{path}: expected a YAML mapping")
    return payload


def inventory_paths(paths: list[str]) -> list[Path]:
    discovered: list[Path] = []
    for raw_path in paths:
        path = Path(raw_path)
        if path.is_dir():
            discovered.extend(sorted(path.glob("*.yml")))
            discovered.extend(sorted(path.glob("*.yaml")))
        else:
            discovered.append(path)
    return [path for path in discovered if path.exists()]


def load_zone_groups(args: argparse.Namespace) -> list[dict[str, Any]]:
    if args.zone_groups_json:
        payload = json.loads(args.zone_groups_json)
    elif args.zone_groups_file:
        payload = load_json_file(args.zone_groups_file)
    elif os.getenv("HETZNER_DNS_ZONE_GROUPS_JSON"):
        payload = json.loads(os.environ["HETZNER_DNS_ZONE_GROUPS_JSON"])
    else:
        raise RuntimeError(
            "zone groups are required via --zone-groups-json, --zone-groups-file, or env"
        )

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
    return value.strip().strip("{}").strip().rstrip(".").lower()


def slugify(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "host"


def with_default_domain(name: str, default_domain: str) -> str:
    normalized = normalize_dns_name(name)
    if "." in normalized:
        return normalized
    return normalize_dns_name(f"{normalized}.{default_domain}")


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


def required_domain_match(fqdn: str, required_domains: list[str]) -> bool:
    return any(fqdn == domain or fqdn.endswith(f".{domain}") for domain in required_domains)


def add_record(
    *,
    rrsets: dict[tuple[str, str], dict[str, Any]],
    grouped_values: dict[tuple[str, str], set[str]],
    errors: list[dict[str, str]],
    skipped: list[dict[str, str]],
    zone_groups: list[dict[str, Any]],
    required_domains: list[str],
    managed_domains: list[str],
    fqdn: str,
    record_type: str,
    values: list[str],
    ttl: int,
    source: str,
) -> None:
    fqdn = normalize_dns_name(fqdn)
    record_type = record_type.upper()
    if managed_domains and not required_domain_match(fqdn, managed_domains):
        skipped.append(
            {
                "fqdn": fqdn,
                "type": record_type,
                "source": source,
                "reason": "outside_managed_domain",
            }
        )
        return

    match = zone_for_name(fqdn, zone_groups)
    if not match:
        reason = "no_matching_zone"
        row = {"fqdn": fqdn, "type": record_type, "source": source, "reason": reason}
        if required_domain_match(fqdn, required_domains):
            errors.append(row)
        else:
            skipped.append(row)
        return

    token_group, zone = match
    key = (fqdn, record_type)
    normalized_values = sorted(set(values))

    if record_type == "CNAME" and len(normalized_values) != 1:
        errors.append(
            {
                "fqdn": fqdn,
                "type": record_type,
                "source": source,
                "reason": "cname_requires_single_target",
            }
        )
        return

    existing_values = grouped_values.get(key)
    if existing_values is not None and existing_values != set(normalized_values):
        errors.append(
            {
                "fqdn": fqdn,
                "type": record_type,
                "source": source,
                "reason": "conflicting_rrset_values",
            }
        )
        return

    incompatible_type = "CNAME" if record_type in {"A", "AAAA"} else "A"
    if (fqdn, incompatible_type) in rrsets:
        errors.append(
            {
                "fqdn": fqdn,
                "type": record_type,
                "source": source,
                "reason": "cname_address_type_conflict",
            }
        )
        return

    grouped_values[key].update(normalized_values)
    rrsets[key] = {
        "action": "ensure",
        "token_group": token_group,
        "zone": zone,
        "fqdn": fqdn,
        "relative_name": relative_record_name(fqdn, zone),
        "type": record_type,
        "ttl": ttl,
        "source": source,
    }


def add_address_record(
    *,
    rrsets: dict[tuple[str, str], dict[str, Any]],
    grouped_values: dict[tuple[str, str], set[str]],
    errors: list[dict[str, str]],
    skipped: list[dict[str, str]],
    zone_groups: list[dict[str, Any]],
    required_domains: list[str],
    managed_domains: list[str],
    fqdn: str,
    address: str,
    ttl: int,
    source: str,
) -> None:
    if not address:
        errors.append({"fqdn": fqdn, "type": "A", "source": source, "reason": "missing_address"})
        return
    try:
        ip_address = parse_ip_address(address)
    except ValueError:
        errors.append(
            {"fqdn": fqdn, "type": "A", "source": source, "reason": "invalid_address"}
        )
        return
    record_type = "A" if ip_address.version == 4 else "AAAA"
    add_record(
        rrsets=rrsets,
        grouped_values=grouped_values,
        errors=errors,
        skipped=skipped,
        zone_groups=zone_groups,
        required_domains=required_domains,
        managed_domains=managed_domains,
        fqdn=fqdn,
        record_type=record_type,
        values=[str(ip_address)],
        ttl=ttl,
        source=source,
    )


def iter_inventory_sources(payload: dict[str, Any], default_domain: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for device in payload.get("devices", []) or []:
        if not isinstance(device, dict):
            continue
        name = str(device.get("name", "")).strip()
        address = str(device.get("management_ip", "")).strip()
        if not name or not address:
            continue
        fqdn = with_default_domain(str(device.get("fqdn") or slugify(name)), default_domain)
        aliases = [
            with_default_domain(str(alias), default_domain)
            for alias in device.get("dns_aliases", []) or []
            if str(alias).strip()
        ]
        rows.append(
            {
                "source": f"device:{name}",
                "fqdn": fqdn,
                "address": address,
                "aliases": aliases,
            }
        )

    for vip in payload.get("service_vips", []) or []:
        if not isinstance(vip, dict):
            continue
        name = str(vip.get("name", "")).strip()
        address = str(vip.get("address", "")).strip()
        if not name or not address:
            continue
        fqdn = with_default_domain(str(vip.get("fqdn") or slugify(name)), default_domain)
        aliases = [
            with_default_domain(str(alias), default_domain)
            for alias in vip.get("aliases", []) or []
            if str(alias).strip()
        ]
        rows.append(
            {
                "source": f"service_vip:{name}",
                "fqdn": fqdn,
                "address": address,
                "aliases": aliases,
            }
        )

    return rows


def generate_hosts_entries(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    address_records: dict[str, dict[str, str]] = defaultdict(dict)
    cname_targets: dict[str, str] = {}

    for record in records:
        if record["type"] in {"A", "AAAA"}:
            for value in record["values"]:
                address_records[value][record["fqdn"]] = str(record.get("source", ""))
        elif record["type"] == "CNAME" and record["values"]:
            cname_targets[record["fqdn"]] = normalize_dns_name(record["values"][0])

    target_to_aliases: dict[str, list[str]] = defaultdict(list)
    for alias, target in cname_targets.items():
        target_to_aliases[target.rstrip(".")].append(alias)

    def source_priority(source: str) -> int:
        if source.startswith("device:"):
            return 0
        if source.startswith("service_vip:"):
            return 1
        return 2

    def append_hostname(hostnames: list[str], fqdn: str) -> None:
        for candidate in (fqdn, fqdn.split(".", 1)[0]):
            if candidate and candidate not in hostnames:
                hostnames.append(candidate)

    entries: list[dict[str, Any]] = []
    for address, names_by_source in sorted(address_records.items(), key=lambda item: item[0]):
        hostnames: list[str] = []
        for fqdn, source in sorted(
            names_by_source.items(), key=lambda item: (source_priority(item[1]), item[0])
        ):
            append_hostname(hostnames, fqdn)
            for alias in sorted(set(target_to_aliases.get(fqdn, []))):
                append_hostname(hostnames, alias)
        entries.append({"address": address, "names": list(dict.fromkeys(hostnames))})
    return entries


def render_hosts_file(entries: list[dict[str, Any]]) -> str:
    return "\n".join(
        f"{entry['address']} {' '.join(entry['names'])}" for entry in entries
    ).rstrip() + "\n"


def generate_dns_plan(
    *,
    payloads: list[dict[str, Any]],
    zone_groups: list[dict[str, Any]],
    default_domain: str,
    required_domains: list[str],
    managed_domains: list[str],
    default_ttl: int,
    apply: bool,
    allow_delete: bool,
) -> dict[str, Any]:
    rrsets: dict[tuple[str, str], dict[str, Any]] = {}
    grouped_values: dict[tuple[str, str], set[str]] = defaultdict(set)
    skipped: list[dict[str, str]] = []
    errors: list[dict[str, str]] = []

    for payload in payloads:
        for row in iter_inventory_sources(payload, default_domain):
            add_address_record(
                rrsets=rrsets,
                grouped_values=grouped_values,
                errors=errors,
                skipped=skipped,
                zone_groups=zone_groups,
                required_domains=required_domains,
                managed_domains=managed_domains,
                fqdn=row["fqdn"],
                address=row["address"],
                ttl=default_ttl,
                source=row["source"],
            )
            for alias in row["aliases"]:
                add_record(
                    rrsets=rrsets,
                    grouped_values=grouped_values,
                    errors=errors,
                    skipped=skipped,
                    zone_groups=zone_groups,
                    required_domains=required_domains,
                    managed_domains=managed_domains,
                    fqdn=alias,
                    record_type="CNAME",
                    values=[f"{row['fqdn']}."],
                    ttl=default_ttl,
                    source=row["source"],
                )

    records: list[dict[str, Any]] = []
    for key, record in sorted(
        rrsets.items(), key=lambda item: (item[1]["zone"], item[1]["fqdn"], item[1]["type"])
    ):
        records.append({**record, "values": sorted(grouped_values[key])})

    hosts_entries = generate_hosts_entries(records)
    return {
        "apply": apply,
        "allow_delete": allow_delete,
        "source": "inventory-intake",
        "provider": "hetzner_cloud_dns",
        "summary": {
            "input_files": len(payloads),
            "records": len(records),
            "hosts_entries": len(hosts_entries),
            "skipped": len(skipped),
            "errors": len(errors),
            "required_domain_errors": sum(
                1 for error in errors if required_domain_match(error["fqdn"], required_domains)
            ),
        },
        "records": records,
        "hosts_entries": hosts_entries,
        "skipped": skipped,
        "errors": errors,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", help="inventory-intake YAML file or directory paths")
    parser.add_argument("--zone-groups-json", default="")
    parser.add_argument("--zone-groups-file", default="")
    parser.add_argument("--default-domain", default="rfc1918.host")
    parser.add_argument("--required-domain", action="append", default=[])
    parser.add_argument("--required-domains-json", default="")
    parser.add_argument("--managed-domain", action="append", default=[])
    parser.add_argument("--managed-domains-json", default="")
    parser.add_argument("--default-ttl", type=int, default=300)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--allow-delete", action="store_true")
    parser.add_argument("--hosts-output", default="")
    parser.add_argument("--format", choices=("json", "text"), default="json")
    parser.add_argument("--output", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    paths = inventory_paths(args.paths)
    if not paths:
        print("ERROR: no inventory files found", file=sys.stderr)
        return 2

    required_domain_inputs = (
        json.loads(args.required_domains_json)
        if args.required_domains_json
        else (args.required_domain or [args.default_domain])
    )
    required_domains = [
        normalize_dns_name(domain)
        for domain in required_domain_inputs
        if str(domain).strip()
    ]
    managed_domain_inputs = (
        json.loads(args.managed_domains_json) if args.managed_domains_json else args.managed_domain
    )
    managed_domains = [
        normalize_dns_name(domain) for domain in (managed_domain_inputs or []) if str(domain).strip()
    ]
    plan = generate_dns_plan(
        payloads=[load_yaml_file(path) for path in paths],
        zone_groups=load_zone_groups(args),
        default_domain=normalize_dns_name(args.default_domain),
        required_domains=required_domains,
        managed_domains=managed_domains,
        default_ttl=args.default_ttl,
        apply=args.apply,
        allow_delete=args.allow_delete,
    )

    if plan["errors"]:
        for error in plan["errors"]:
            print(
                "ERROR: "
                f"{error['reason']} fqdn={error['fqdn']} type={error['type']} "
                f"source={error['source']}",
                file=sys.stderr,
            )
        return 1

    if args.hosts_output:
        Path(args.hosts_output).write_text(render_hosts_file(plan["hosts_entries"]), encoding="utf-8")

    if args.format == "json":
        output = json.dumps(plan, indent=2, sort_keys=True) + "\n"
    else:
        lines = [
            f"apply={str(plan['apply']).lower()}",
            f"allow_delete={str(plan['allow_delete']).lower()}",
            f"records={plan['summary']['records']}",
            f"hosts_entries={plan['summary']['hosts_entries']}",
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
