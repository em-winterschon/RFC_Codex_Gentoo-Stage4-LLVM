#!/usr/bin/env python3
"""NetBox is authoritative: compare NetBox, Ansible inventory, and Hetzner DNS."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any
from urllib import error, parse, request

CONNECTIVITY_TYPES = {"A", "AAAA", "CNAME"}
DEFAULT_AUDIT_DOMAINS = [
    "rfc1918.host",
    "rfc1918.dev",
    "rfc1918.ai",
    "rfc1918.io",
    "rfc1918.sh",
    "rfc1918.systems",
    "rfc1918.org",
    "vernetzen.io",
    "yukon.systems",
]
LABEL_RE = re.compile(r"^(?!-)[a-z0-9-]{1,63}(?<!-)$")


def load_json_file(path: str) -> Any:
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_token(path: str) -> str:
    return Path(path).read_text(encoding="utf-8").strip()


def normalize_dns_name(value: str) -> str:
    return value.strip().strip("{}").strip().rstrip(".").lower()


def normalize_domains(values: list[Any]) -> list[str]:
    return [normalize_dns_name(str(value)) for value in values if str(value).strip()]


def in_managed_domain(name: str, domains: list[str]) -> bool:
    fqdn = normalize_dns_name(name)
    return any(fqdn == domain or fqdn.endswith(f".{domain}") for domain in domains)


def dns_name_valid(name: str) -> bool:
    fqdn = normalize_dns_name(name)
    if not fqdn or len(fqdn) > 253:
        return False
    return all(LABEL_RE.match(label) for label in fqdn.split("."))


def invalid_reason(name: str) -> str:
    fqdn = normalize_dns_name(name)
    if not fqdn:
        return "empty_dns_name"
    if len(fqdn) > 253:
        return "dns_name_too_long"
    bad = [label for label in fqdn.split(".") if not LABEL_RE.match(label)]
    if bad:
        return "invalid_dns_label"
    return "invalid_dns_name"


def parse_ip(value: str) -> str | None:
    if not value:
        return None
    try:
        return str(ipaddress.ip_interface(value).ip)
    except ValueError:
        try:
            return str(ipaddress.ip_address(value))
        except ValueError:
            return None


def record_type_for_ip(value: str) -> str:
    return "A" if ipaddress.ip_address(value).version == 4 else "AAAA"


def request_json(url: str, headers: dict[str, str]) -> dict[str, Any]:
    req = request.Request(url, headers=headers)
    try:
        with request.urlopen(req, timeout=30) as response:  # noqa: S310
            return json.loads(response.read().decode("utf-8"))
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GET {url} failed: HTTP {exc.code}: {body}") from exc


def fetch_netbox_ip_addresses(api_url: str, token: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Token {token}"
    url = f"{api_url.rstrip('/')}/api/ipam/ip-addresses/?" + parse.urlencode({"limit": "1000"})
    while url:
        payload = request_json(url, headers)
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
    raise RuntimeError(f"{path}: expected a NetBox results object or list")


def coerce_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [item for item in re.split(r"[\s,]+", value.strip()) if item]
    if isinstance(value, list):
        return [str(item) for item in value if str(item).strip()]
    return []


def netbox_aliases(row: dict[str, Any]) -> list[str]:
    direct = coerce_list(row.get("dns_aliases"))
    custom_fields = row.get("custom_fields")
    if isinstance(custom_fields, dict):
        direct.extend(coerce_list(custom_fields.get("dns_aliases")))
    return sorted(set(normalize_dns_name(alias) for alias in direct if alias))


def add_rrset(
    rrsets: dict[tuple[str, str], set[str]],
    rows: list[dict[str, Any]],
    invalid: list[dict[str, str]],
    *,
    source_system: str,
    source: str,
    fqdn: str,
    record_type: str,
    values: list[str],
    managed_domains: list[str],
    canonical: str = "",
) -> None:
    fqdn = normalize_dns_name(fqdn)
    record_type = record_type.upper()
    if not fqdn or not in_managed_domain(fqdn, managed_domains):
        return
    if not dns_name_valid(fqdn):
        invalid.append(
            {
                "source_system": source_system,
                "source": source,
                "name": fqdn,
                "reason": invalid_reason(fqdn),
                "canonical": canonical,
            }
        )
        return
    clean_values = sorted(set(str(value).strip() for value in values if str(value).strip()))
    if not clean_values:
        return
    rrsets[(fqdn, record_type)].update(clean_values)
    rows.append(
        {
            "source_system": source_system,
            "source": source,
            "fqdn": fqdn,
            "type": record_type,
            "values": clean_values,
        }
    )


def build_netbox_records(ip_addresses: list[dict[str, Any]], managed_domains: list[str]) -> tuple[
    dict[tuple[str, str], set[str]],
    list[dict[str, Any]],
    list[dict[str, str]],
    list[dict[str, str]],
]:
    rrsets: dict[tuple[str, str], set[str]] = defaultdict(set)
    rows: list[dict[str, Any]] = []
    invalid: list[dict[str, str]] = []
    skipped: list[dict[str, str]] = []
    for row in ip_addresses:
        address_raw = str(row.get("address", "")).strip()
        dns_name = normalize_dns_name(str(row.get("dns_name", "") or ""))
        address = parse_ip(address_raw)
        if not dns_name:
            skipped.append(
                {"source_system": "netbox", "address": address_raw, "reason": "missing_dns_name"}
            )
            continue
        if not in_managed_domain(dns_name, managed_domains):
            skipped.append(
                {"source_system": "netbox", "fqdn": dns_name, "reason": "outside_managed_domain"}
            )
            continue
        if not address:
            skipped.append(
                {
                    "source_system": "netbox",
                    "fqdn": dns_name,
                    "reason": "invalid_or_missing_address",
                }
            )
            continue
        add_rrset(
            rrsets,
            rows,
            invalid,
            source_system="netbox",
            source=address_raw,
            fqdn=dns_name,
            record_type=record_type_for_ip(address),
            values=[address],
            managed_domains=managed_domains,
        )
        for alias in netbox_aliases(row):
            add_rrset(
                rrsets,
                rows,
                invalid,
                source_system="netbox",
                source=f"alias:{dns_name}",
                fqdn=alias,
                record_type="CNAME",
                values=[f"{dns_name}."],
                managed_domains=managed_domains,
                canonical=dns_name,
            )
    return rrsets, collapse_rows(rows), invalid, skipped


def load_ansible_inventory(path: str, ansible_config: str = "") -> dict[str, Any]:
    env = os.environ.copy()
    if ansible_config:
        env["ANSIBLE_CONFIG"] = ansible_config
    output = subprocess.check_output(
        ["ansible-inventory", "-i", path, "--list"], text=True, env=env
    )
    payload = json.loads(output)
    if not isinstance(payload, dict):
        raise RuntimeError("ansible-inventory output was not a JSON object")
    return payload


def ansible_inventory_from_file(path: str) -> dict[str, Any]:
    payload = load_json_file(path)
    if not isinstance(payload, dict):
        raise RuntimeError(f"{path}: expected ansible-inventory JSON object")
    return payload


def build_ansible_records(
    inventory: dict[str, Any], managed_domains: list[str], default_domain: str
) -> tuple[
    dict[tuple[str, str], set[str]],
    list[dict[str, Any]],
    list[dict[str, str]],
    list[dict[str, str]],
]:
    hostvars = inventory.get("_meta", {}).get("hostvars", {})
    if not isinstance(hostvars, dict):
        hostvars = {}
    rrsets: dict[tuple[str, str], set[str]] = defaultdict(set)
    rows: list[dict[str, Any]] = []
    invalid: list[dict[str, str]] = []
    skipped: list[dict[str, str]] = []
    for host, values in sorted(hostvars.items()):
        if not isinstance(values, dict):
            continue
        fqdn = normalize_dns_name(str(values.get("fqdn", "") or ""))
        derived = normalize_dns_name(f"{host}.{default_domain}")
        if not dns_name_valid(derived):
            invalid.append(
                {
                    "source_system": "ansible",
                    "source": f"inventory_hostname:{host}",
                    "name": derived,
                    "reason": invalid_reason(derived),
                    "canonical": fqdn,
                }
            )
        address = parse_ip(str(values.get("observed_service_ip", "") or "")) or parse_ip(
            str(values.get("ansible_host", "") or "")
        )
        if fqdn and address:
            add_rrset(
                rrsets,
                rows,
                invalid,
                source_system="ansible",
                source=host,
                fqdn=fqdn,
                record_type=record_type_for_ip(address),
                values=[address],
                managed_domains=managed_domains,
                canonical=fqdn,
            )
        elif fqdn:
            skipped.append(
                {"source_system": "ansible", "host": host, "fqdn": fqdn, "reason": "missing_ip"}
            )
        for alias in coerce_list(values.get("dns_aliases")):
            add_rrset(
                rrsets,
                rows,
                invalid,
                source_system="ansible",
                source=f"{host}:dns_aliases",
                fqdn=alias,
                record_type="CNAME",
                values=[f"{fqdn}."],
                managed_domains=managed_domains,
                canonical=fqdn,
            )
    return rrsets, collapse_rows(rows), invalid, skipped


def load_token_groups(args: argparse.Namespace) -> list[dict[str, Any]]:
    if args.hetzner_token_groups_json:
        payload = json.loads(args.hetzner_token_groups_json)
    elif args.hetzner_token_groups_file:
        payload = load_json_file(args.hetzner_token_groups_file)
    elif os.getenv("HETZNER_DNS_TOKEN_GROUPS_JSON"):
        payload = json.loads(os.environ["HETZNER_DNS_TOKEN_GROUPS_JSON"])
    else:
        raise RuntimeError("Hetzner DNS token groups are required")
    if not isinstance(payload, list):
        raise RuntimeError("Hetzner DNS token groups must be a list")
    groups: list[dict[str, Any]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise RuntimeError(f"token_groups[{index}] must be a mapping")
        name = str(item.get("name", "")).strip()
        if not name:
            raise RuntimeError(f"token_groups[{index}] missing name")
        groups.append(
            {
                "name": name,
                "token_name": str(item.get("token_name", "")).strip(),
                "api_token": str(item.get("api_token", "")).strip(),
                "zones": normalize_domains(item.get("zones", []) or []),
            }
        )
    return groups


def extract_list(payload: Any, keys: tuple[str, ...], context: str) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if not isinstance(payload, dict):
        raise RuntimeError(f"{context} response was not an object or list")
    for key in keys:
        value = payload.get(key)
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
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
            record_value = str(value.get("value", "") if isinstance(value, dict) else value).strip()
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


def fetch_hcloud_json(api_endpoint: str, token: str, path: str) -> dict[str, Any]:
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return request_json(f"{api_endpoint.rstrip('/')}{path}", headers)


def fixture_group(fixture: dict[str, Any], token_group_name: str) -> dict[str, Any] | None:
    for group in fixture.get("token_groups", []):
        if isinstance(group, dict) and group.get("name") == token_group_name:
            return group
    return None


def fixture_zones(fixture: dict[str, Any], token_group_name: str) -> list[dict[str, Any]]:
    group = fixture_group(fixture, token_group_name)
    zones = group.get("zones", []) if group else []
    return [zone for zone in zones if isinstance(zone, dict)] if isinstance(zones, list) else []


def fixture_records(
    fixture: dict[str, Any], token_group_name: str, zone_id: str
) -> list[dict[str, Any]]:
    group = fixture_group(fixture, token_group_name)
    records_by_zone_id = group.get("records_by_zone_id", {}) if group else {}
    if not isinstance(records_by_zone_id, dict):
        return []
    payload = records_by_zone_id.get(zone_id, [])
    if isinstance(payload, dict):
        return extract_records(payload, "fixture records")
    return (
        [record for record in payload if isinstance(record, dict)]
        if isinstance(payload, list)
        else []
    )


def record_fqdn(record_name: str, zone_name: str) -> str:
    name = normalize_dns_name(record_name)
    zone = normalize_dns_name(zone_name)
    if name in ("", "@"):
        return zone
    if name == zone or name.endswith(f".{zone}"):
        return name
    return f"{name}.{zone}"


def fetch_zone_records(api_endpoint: str, token: str, zone_id: str) -> list[dict[str, Any]]:
    base_url = api_endpoint.rstrip("/")
    urls = [
        f"/zones/{parse.quote(zone_id, safe='')}/rrsets",
        f"/records?{parse.urlencode({'zone_id': zone_id})}",
        f"/zones/{parse.quote(zone_id, safe='')}/records",
    ]
    last_error: RuntimeError | None = None
    for path in urls:
        try:
            return extract_records(fetch_hcloud_json(base_url, token, path), "records")
        except RuntimeError as exc:
            last_error = exc
    raise last_error or RuntimeError(f"could not fetch records for zone id {zone_id}")


def build_hetzner_records(
    *,
    token_groups: list[dict[str, Any]],
    api_endpoint: str,
    managed_domains: list[str],
    fixture: dict[str, Any] | None,
) -> tuple[
    dict[tuple[str, str], set[str]],
    list[dict[str, Any]],
    list[dict[str, str]],
    list[dict[str, str]],
    dict[str, int],
]:
    rrsets: dict[tuple[str, str], set[str]] = defaultdict(set)
    rows: list[dict[str, Any]] = []
    invalid: list[dict[str, str]] = []
    errors: list[dict[str, str]] = []
    zones_configured = 0
    zones_readable = 0
    for group in token_groups:
        group_name = group["name"]
        configured_zones = set(group["zones"])
        zones_configured += len(configured_zones)
        try:
            provider_zones = (
                fixture_zones(fixture, group_name)
                if fixture is not None
                else extract_list(
                    fetch_hcloud_json(api_endpoint, group["api_token"], "/zones"),
                    ("zones", "results"),
                    "zones",
                )
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
        for zone_name in sorted(configured_zones):
            provider_zone = zones_by_name.get(zone_name)
            if not provider_zone:
                errors.append(
                    {"token_group": group_name, "zone": zone_name, "reason": "zone_not_found"}
                )
                continue
            zone_id = str(provider_zone.get("id", "")).strip()
            if not zone_id:
                errors.append(
                    {"token_group": group_name, "zone": zone_name, "reason": "missing_zone_id"}
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
                continue
            zones_readable += 1
            for record in records:
                record_type = str(record.get("type", "")).strip().upper()
                if record_type not in CONNECTIVITY_TYPES:
                    continue
                fqdn = record_fqdn(str(record.get("name", "")).strip(), zone_name)
                if not in_managed_domain(fqdn, managed_domains):
                    continue
                value = str(record.get("value", "")).strip()
                add_rrset(
                    rrsets,
                    rows,
                    invalid,
                    source_system="hetzner",
                    source=f"{group_name}:{zone_name}:{record.get('id', '')}",
                    fqdn=fqdn,
                    record_type=record_type,
                    values=[value],
                    managed_domains=managed_domains,
                )
    return (
        rrsets,
        collapse_rows(rows),
        invalid,
        errors,
        {"zones_configured": zones_configured, "zones_readable": zones_readable},
    )


def collapse_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[tuple[str, str, str, str], set[str]] = defaultdict(set)
    for row in rows:
        key = (row["source_system"], row["source"], row["fqdn"], row["type"])
        merged[key].update(row["values"])
    return [
        {
            "source_system": source_system,
            "source": source,
            "fqdn": fqdn,
            "type": record_type,
            "values": sorted(values),
        }
        for (source_system, source, fqdn, record_type), values in sorted(merged.items())
    ]


def rrset_rows(rrsets: dict[tuple[str, str], set[str]], source_system: str) -> list[dict[str, Any]]:
    return [
        {
            "source_system": source_system,
            "fqdn": fqdn,
            "type": record_type,
            "values": sorted(values),
        }
        for (fqdn, record_type), values in sorted(rrsets.items())
    ]


def compare_rrsets(
    authoritative: dict[tuple[str, str], set[str]],
    other: dict[tuple[str, str], set[str]],
    *,
    missing_name: str,
    extra_name: str,
    mismatch_name: str,
) -> dict[str, list[dict[str, Any]]]:
    missing: list[dict[str, Any]] = []
    extra: list[dict[str, Any]] = []
    mismatches: list[dict[str, Any]] = []
    for key in sorted(authoritative):
        fqdn, record_type = key
        if key not in other:
            missing.append(
                {"fqdn": fqdn, "type": record_type, "netbox_values": sorted(authoritative[key])}
            )
        elif authoritative[key] != other[key]:
            mismatches.append(
                {
                    "fqdn": fqdn,
                    "type": record_type,
                    "netbox_values": sorted(authoritative[key]),
                    mismatch_name: sorted(other[key]),
                }
            )
    for key in sorted(other):
        if key not in authoritative:
            fqdn, record_type = key
            extra.append({"fqdn": fqdn, "type": record_type, extra_name: sorted(other[key])})
    return {missing_name: missing, extra_name: extra, mismatch_name: mismatches}


def render_markdown(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        "# NetBox DNS GAP Analysis",
        "",
        "NetBox is authoritative for hostnames, IP addresses, and DNS desired state.",
        "",
        "## Summary",
        "",
    ]
    for key in sorted(summary):
        lines.append(f"- `{key}`: {summary[key]}")
    lines.extend(["", "## Gaps", ""])
    for name, rows in report["gaps"].items():
        lines.append(f"### {name}")
        lines.append("")
        if not rows:
            lines.append("None.")
        else:
            for row in rows:
                label = (
                    row.get("fqdn")
                    or row.get("name")
                    or row.get("zone")
                    or row.get("source", "gap")
                )
                lines.append(f"- `{label}`: `{json.dumps(row, sort_keys=True)}`")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def generate_gap_analysis(
    *,
    netbox_ip_addresses: list[dict[str, Any]],
    ansible_inventory: dict[str, Any],
    hetzner_token_groups: list[dict[str, Any]],
    hetzner_api_endpoint: str,
    hetzner_fixture: dict[str, Any] | None,
    managed_domains: list[str],
    default_domain: str,
) -> dict[str, Any]:
    netbox_rrsets, netbox_rows, netbox_invalid, netbox_skipped = build_netbox_records(
        netbox_ip_addresses, managed_domains
    )
    ansible_rrsets, ansible_rows, ansible_invalid, ansible_skipped = build_ansible_records(
        ansible_inventory, managed_domains, default_domain
    )
    hetzner_rrsets, hetzner_rows, hetzner_invalid, hetzner_errors, hetzner_summary = (
        build_hetzner_records(
            token_groups=hetzner_token_groups,
            api_endpoint=hetzner_api_endpoint,
            managed_domains=managed_domains,
            fixture=hetzner_fixture,
        )
    )
    ansible_compare = compare_rrsets(
        netbox_rrsets,
        ansible_rrsets,
        missing_name="netbox_missing_from_ansible",
        extra_name="ansible_missing_from_netbox",
        mismatch_name="ansible_values",
    )
    hetzner_compare = compare_rrsets(
        netbox_rrsets,
        hetzner_rrsets,
        missing_name="hetzner_missing_records",
        extra_name="hetzner_extra_records",
        mismatch_name="hetzner_values",
    )
    gaps = {
        "invalid_dns_names": sorted(
            netbox_invalid + ansible_invalid + hetzner_invalid,
            key=lambda row: (row.get("name", ""), row.get("source", "")),
        ),
        "netbox_missing_from_ansible": ansible_compare["netbox_missing_from_ansible"],
        "ansible_missing_from_netbox": ansible_compare["ansible_missing_from_netbox"],
        "netbox_ansible_value_mismatches": ansible_compare["ansible_values"],
        "hetzner_missing_records": hetzner_compare["hetzner_missing_records"],
        "hetzner_value_mismatches": hetzner_compare["hetzner_values"],
        "hetzner_extra_records": hetzner_compare["hetzner_extra_records"],
        "hetzner_errors": sorted(
            hetzner_errors,
            key=lambda row: (
                row.get("token_group", ""),
                row.get("zone", ""),
                row.get("reason", ""),
            ),
        ),
    }
    summary = {
        "managed_domains": len(managed_domains),
        "netbox_dns_records": len(netbox_rrsets),
        "ansible_dns_records": len(ansible_rrsets),
        "hetzner_dns_records": len(hetzner_rrsets),
        "invalid_dns_names": len(gaps["invalid_dns_names"]),
        "netbox_missing_from_ansible": len(gaps["netbox_missing_from_ansible"]),
        "ansible_missing_from_netbox": len(gaps["ansible_missing_from_netbox"]),
        "netbox_ansible_value_mismatches": len(gaps["netbox_ansible_value_mismatches"]),
        "hetzner_missing_records": len(gaps["hetzner_missing_records"]),
        "hetzner_value_mismatches": len(gaps["hetzner_value_mismatches"]),
        "hetzner_extra_records": len(gaps["hetzner_extra_records"]),
        "hetzner_errors": len(gaps["hetzner_errors"]),
        "netbox_skipped": len(netbox_skipped),
        "ansible_skipped": len(ansible_skipped),
        **hetzner_summary,
    }
    return {
        "source_of_truth": "netbox",
        "provider": "hetzner_cloud_dns",
        "managed_domains": managed_domains,
        "summary": summary,
        "records": {
            "netbox": rrset_rows(netbox_rrsets, "netbox"),
            "ansible": rrset_rows(ansible_rrsets, "ansible"),
            "hetzner": rrset_rows(hetzner_rrsets, "hetzner"),
        },
        "source_rows": {"netbox": netbox_rows, "ansible": ansible_rows, "hetzner": hetzner_rows},
        "skipped": {"netbox": netbox_skipped, "ansible": ansible_skipped},
        "gaps": gaps,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--netbox-api-url", default=os.getenv("NETBOX_API_URL", "http://172.16.99.62")
    )
    parser.add_argument("--netbox-token", default=os.getenv("NETBOX_TOKEN", ""))
    parser.add_argument("--netbox-token-file", default=os.getenv("NETBOX_TOKEN_FILE", ""))
    parser.add_argument("--netbox-ip-addresses-file", default="")
    parser.add_argument("--ansible-inventory", default="")
    parser.add_argument("--ansible-inventory-json", default="")
    parser.add_argument("--ansible-config", default="")
    parser.add_argument(
        "--hetzner-api-endpoint",
        default=os.getenv("HETZNER_DNS_API_ENDPOINT", "https://api.hetzner.cloud/v1"),
    )
    parser.add_argument("--hetzner-token-groups-json", default="")
    parser.add_argument("--hetzner-token-groups-file", default="")
    parser.add_argument("--hetzner-fixture-file", default="")
    parser.add_argument("--managed-domains-json", default="")
    parser.add_argument("--default-domain", default="rfc1918.host")
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    parser.add_argument("--output", default="")
    parser.add_argument("--markdown-output", default="")
    parser.add_argument("--fail-on-gap", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    token = args.netbox_token or (
        load_token(args.netbox_token_file) if args.netbox_token_file else ""
    )
    netbox_ip_addresses = (
        netbox_ip_addresses_from_file(args.netbox_ip_addresses_file)
        if args.netbox_ip_addresses_file
        else fetch_netbox_ip_addresses(args.netbox_api_url, token)
    )
    if args.ansible_inventory_json:
        ansible_inventory = ansible_inventory_from_file(args.ansible_inventory_json)
    elif args.ansible_inventory:
        ansible_inventory = load_ansible_inventory(args.ansible_inventory, args.ansible_config)
    else:
        raise RuntimeError(
            "Ansible inventory is required via --ansible-inventory or --ansible-inventory-json"
        )
    managed_domains = (
        normalize_domains(json.loads(args.managed_domains_json))
        if args.managed_domains_json
        else DEFAULT_AUDIT_DOMAINS
    )
    report = generate_gap_analysis(
        netbox_ip_addresses=netbox_ip_addresses,
        ansible_inventory=ansible_inventory,
        hetzner_token_groups=load_token_groups(args),
        hetzner_api_endpoint=args.hetzner_api_endpoint.rstrip("/"),
        hetzner_fixture=(
            load_json_file(args.hetzner_fixture_file) if args.hetzner_fixture_file else None
        ),
        managed_domains=managed_domains,
        default_domain=normalize_dns_name(args.default_domain),
    )
    json_output = json.dumps(report, indent=2, sort_keys=True) + "\n"
    markdown_output = render_markdown(report)
    if args.markdown_output:
        Path(args.markdown_output).write_text(markdown_output, encoding="utf-8")
    output = markdown_output if args.format == "markdown" else json_output
    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    gap_count = sum(
        value
        for key, value in report["summary"].items()
        if key
        not in {
            "managed_domains",
            "netbox_dns_records",
            "ansible_dns_records",
            "hetzner_dns_records",
            "netbox_skipped",
            "ansible_skipped",
            "zones_configured",
            "zones_readable",
        }
    )
    return 1 if args.fail_on_gap and gap_count else 0


if __name__ == "__main__":
    raise SystemExit(main())
