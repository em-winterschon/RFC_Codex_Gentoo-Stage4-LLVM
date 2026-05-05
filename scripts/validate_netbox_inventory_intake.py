#!/usr/bin/env python3
"""Validate structured NetBox inventory intake definitions.

This validator is intentionally local and dependency-light. It checks the repo
intake contract before any NetBox API write path is allowed to consume the
files.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


class IntakeValidationError(Exception):
    """Raised when intake files contain schema or referential errors."""


def require_yaml() -> Any:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - depends on local environment
        raise SystemExit("PyYAML is required. Install python yaml support first.") from exc
    return yaml


@dataclass
class ValidationResult:
    files: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    counts: dict[str, int] = field(
        default_factory=lambda: {
            "datacenters": 0,
            "clusters": 0,
            "prefixes": 0,
            "devices": 0,
            "service_vips": 0,
        }
    )

    @property
    def ok(self) -> bool:
        return not self.errors


def load_yaml_file(path: Path) -> dict[str, Any]:
    yaml = require_yaml()
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise IntakeValidationError(f"{path}: top-level document must be a mapping")
    return payload


def intake_paths(inputs: list[str]) -> list[Path]:
    paths: list[Path] = []
    for raw in inputs:
        path = Path(raw)
        if path.is_dir():
            paths.extend(sorted(path.rglob("*.yml")))
            paths.extend(sorted(path.rglob("*.yaml")))
        else:
            paths.append(path)
    return sorted(dict.fromkeys(paths))


def expect_list(payload: dict[str, Any], key: str, path: Path, result: ValidationResult) -> list[dict[str, Any]]:
    value = payload.get(key, [])
    if value is None:
        return []
    if not isinstance(value, list):
        result.errors.append(f"{path}: {key} must be a list")
        return []
    rows: list[dict[str, Any]] = []
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            result.errors.append(f"{path}: {key}[{index}] must be a mapping")
            continue
        rows.append(item)
    return rows


def required_string(row: dict[str, Any], key: str, label: str, result: ValidationResult) -> str:
    value = row.get(key)
    if not isinstance(value, str) or not value.strip():
        result.errors.append(f"{label}: missing required string field {key}")
        return ""
    return value.strip()


def parse_network(value: Any, label: str, result: ValidationResult) -> ipaddress._BaseNetwork | None:
    if not isinstance(value, str) or not value.strip():
        result.errors.append(f"{label}: prefix must be a non-empty string")
        return None
    try:
        return ipaddress.ip_network(value.strip(), strict=False)
    except ValueError:
        result.errors.append(f"{label}: invalid prefix {value}")
        return None


def parse_address(value: Any, label: str, result: ValidationResult) -> ipaddress._BaseAddress | None:
    if not isinstance(value, str) or not value.strip():
        result.errors.append(f"{label}: IP address must be a non-empty string")
        return None
    address = value.split("/", 1)[0]
    try:
        return ipaddress.ip_address(address)
    except ValueError:
        result.errors.append(f"{label}: invalid IP address {value}")
        return None


def validate_version(payload: dict[str, Any], path: Path, result: ValidationResult) -> None:
    version = payload.get("inventory_intake_version")
    if version != 1:
        result.errors.append(f"{path}: inventory_intake_version must be 1")


def validate_sites(datacenters: list[dict[str, Any]], path: Path, result: ValidationResult) -> dict[str, dict[str, Any]]:
    sites: dict[str, dict[str, Any]] = {}
    for index, site in enumerate(datacenters):
        label = f"{path}: datacenters[{index}]"
        name = required_string(site, "name", label, result)
        slug = required_string(site, "slug", label, result)
        if slug:
            if slug in sites:
                result.errors.append(f"{label}: duplicate site slug {slug}")
            sites[slug] = site
        if not isinstance(site.get("timezone", "UTC"), str):
            result.errors.append(f"{label}: timezone must be a string")
        for prefix_index, prefix in enumerate(site.get("management_prefixes", []) or []):
            parse_network(prefix, f"{label}: management_prefixes[{prefix_index}]", result)
        if name and slug and name.strip().lower().replace(" ", "-") != slug:
            result.warnings.append(f"{label}: site name {name} does not normalize exactly to slug {slug}")
    result.counts["datacenters"] += len(datacenters)
    return sites


def validate_prefixes(
    prefixes: list[dict[str, Any]], path: Path, sites: dict[str, dict[str, Any]], result: ValidationResult
) -> dict[str, ipaddress._BaseNetwork]:
    networks: dict[str, ipaddress._BaseNetwork] = {}
    seen_vlans: set[tuple[str, int]] = set()
    for index, prefix in enumerate(prefixes):
        label = f"{path}: prefixes[{index}]"
        site_slug = required_string(prefix, "site", label, result)
        if site_slug and site_slug not in sites:
            result.errors.append(f"{label}: unknown site {site_slug}")
        network = parse_network(prefix.get("prefix"), label, result)
        if network is not None:
            key = str(network)
            if key in networks:
                result.errors.append(f"{label}: duplicate prefix {key}")
            networks[key] = network
        vlan = prefix.get("vlan")
        if vlan is not None:
            if not isinstance(vlan, dict):
                result.errors.append(f"{label}: vlan must be a mapping")
            else:
                vlan_id = vlan.get("id")
                if not isinstance(vlan_id, int) or vlan_id < 1 or vlan_id > 4094:
                    result.errors.append(f"{label}: vlan.id must be an integer from 1 to 4094")
                elif site_slug:
                    vlan_key = (site_slug, vlan_id)
                    if vlan_key in seen_vlans:
                        result.errors.append(f"{label}: duplicate VLAN {vlan_id} for site {site_slug}")
                    seen_vlans.add(vlan_key)
    result.counts["prefixes"] += len(prefixes)
    return networks


def address_in_any_prefix(address: ipaddress._BaseAddress, networks: dict[str, ipaddress._BaseNetwork]) -> bool:
    return any(address.version == network.version and address in network for network in networks.values())


def validate_devices(
    devices: list[dict[str, Any]],
    path: Path,
    sites: dict[str, dict[str, Any]],
    networks: dict[str, ipaddress._BaseNetwork],
    result: ValidationResult,
) -> set[str]:
    names: set[str] = set()
    for index, device in enumerate(devices):
        label = f"{path}: devices[{index}]"
        name = required_string(device, "name", label, result)
        if name:
            if name in names:
                result.errors.append(f"{label}: duplicate device name {name}")
            names.add(name)
        site_slug = required_string(device, "site", label, result)
        if site_slug and site_slug not in sites:
            result.errors.append(f"{label}: unknown site {site_slug}")
        required_string(device, "role", label, result)
        management_ip = device.get("management_ip")
        if management_ip:
            address = parse_address(management_ip, f"{label}: management_ip", result)
            if address and networks and not address_in_any_prefix(address, networks):
                result.warnings.append(f"{label}: management_ip {management_ip} is outside declared prefixes")
        interfaces = device.get("interfaces", []) or []
        if not isinstance(interfaces, list):
            result.errors.append(f"{label}: interfaces must be a list")
        else:
            seen_interfaces: set[str] = set()
            for interface_index, interface in enumerate(interfaces):
                iface_label = f"{label}: interfaces[{interface_index}]"
                if not isinstance(interface, dict):
                    result.errors.append(f"{iface_label}: interface must be a mapping")
                    continue
                iface_name = required_string(interface, "name", iface_label, result)
                if iface_name in seen_interfaces:
                    result.errors.append(f"{iface_label}: duplicate interface {iface_name}")
                seen_interfaces.add(iface_name)
    result.counts["devices"] += len(devices)
    return names


def validate_clusters(
    clusters: list[dict[str, Any]],
    path: Path,
    sites: dict[str, dict[str, Any]],
    devices: set[str],
    result: ValidationResult,
) -> None:
    seen: set[str] = set()
    for index, cluster in enumerate(clusters):
        label = f"{path}: clusters[{index}]"
        name = required_string(cluster, "name", label, result)
        if name:
            if name in seen:
                result.errors.append(f"{label}: duplicate cluster name {name}")
            seen.add(name)
        site_slug = required_string(cluster, "site", label, result)
        if site_slug and site_slug not in sites:
            result.errors.append(f"{label}: unknown site {site_slug}")
        required_string(cluster, "role", label, result)
        for member_index, member in enumerate(cluster.get("members", []) or []):
            if not isinstance(member, str) or not member.strip():
                result.errors.append(f"{label}: members[{member_index}] must be a device name string")
            elif devices and member not in devices:
                result.errors.append(f"{label}: members[{member_index}] references unknown device {member}")
    result.counts["clusters"] += len(clusters)


def validate_listener(listener: dict[str, Any], label: str, result: ValidationResult) -> None:
    protocol = listener.get("protocol")
    if protocol not in {"tcp", "udp", "http", "https"}:
        result.errors.append(f"{label}: protocol must be tcp, udp, http, or https")
    port = listener.get("port")
    if not isinstance(port, int) or port < 1 or port > 65535:
        result.errors.append(f"{label}: port must be an integer from 1 to 65535")


def validate_service_vips(
    service_vips: list[dict[str, Any]],
    path: Path,
    sites: dict[str, dict[str, Any]],
    networks: dict[str, ipaddress._BaseNetwork],
    result: ValidationResult,
) -> None:
    seen: set[str] = set()
    for index, vip in enumerate(service_vips):
        label = f"{path}: service_vips[{index}]"
        name = required_string(vip, "name", label, result)
        if name:
            if name in seen:
                result.errors.append(f"{label}: duplicate service VIP name {name}")
            seen.add(name)
        site_slug = required_string(vip, "site", label, result)
        if site_slug and site_slug not in sites:
            result.errors.append(f"{label}: unknown site {site_slug}")
        address = parse_address(vip.get("address"), f"{label}: address", result)
        if address and networks and not address_in_any_prefix(address, networks):
            result.warnings.append(f"{label}: address {vip.get('address')} is outside declared prefixes")
        listeners = vip.get("listeners")
        if listeners is None and "protocol" in vip and "port" in vip:
            listeners = [{"protocol": vip["protocol"], "port": vip["port"]}]
        if not isinstance(listeners, list) or not listeners:
            result.errors.append(f"{label}: listeners must be a non-empty list")
            continue
        for listener_index, listener in enumerate(listeners):
            listener_label = f"{label}: listeners[{listener_index}]"
            if not isinstance(listener, dict):
                result.errors.append(f"{listener_label}: listener must be a mapping")
                continue
            validate_listener(listener, listener_label, result)
    result.counts["service_vips"] += len(service_vips)


def validate_payload(path: Path, payload: dict[str, Any], result: ValidationResult) -> None:
    validate_version(payload, path, result)
    datacenters = expect_list(payload, "datacenters", path, result)
    clusters = expect_list(payload, "clusters", path, result)
    prefixes = expect_list(payload, "prefixes", path, result)
    devices = expect_list(payload, "devices", path, result)
    service_vips = expect_list(payload, "service_vips", path, result)

    sites = validate_sites(datacenters, path, result)
    networks = validate_prefixes(prefixes, path, sites, result)
    device_names = validate_devices(devices, path, sites, networks, result)
    validate_clusters(clusters, path, sites, device_names, result)
    validate_service_vips(service_vips, path, sites, networks, result)


def validate_files(paths: list[Path]) -> ValidationResult:
    result = ValidationResult()
    if not paths:
        result.errors.append("no intake files found")
        return result
    for path in paths:
        result.files.append(str(path))
        if not path.exists():
            result.errors.append(f"{path}: file does not exist")
            continue
        try:
            payload = load_yaml_file(path)
            validate_payload(path, payload, result)
        except IntakeValidationError as exc:
            result.errors.append(str(exc))
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", help="YAML intake file or directory paths")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = validate_files(intake_paths(args.paths))
    payload = {
        "ok": result.ok,
        "files": result.files,
        "counts": result.counts,
        "errors": result.errors,
        "warnings": result.warnings,
    }
    if args.format == "json":
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(f"validated_files={len(result.files)}")
        for key in sorted(result.counts):
            print(f"{key}={result.counts[key]}")
        for warning in result.warnings:
            print(f"WARNING: {warning}", file=sys.stderr)
        for validation_error in result.errors:
            print(f"ERROR: {validation_error}", file=sys.stderr)
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
