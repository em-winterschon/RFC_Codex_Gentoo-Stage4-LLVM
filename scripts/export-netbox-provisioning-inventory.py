#!/usr/bin/env python3
"""Export NetBox objects into provisioning inventory, IPAM, and service targets."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import sys
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


def fetch_paginated(api_url: str, endpoint: str, token: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    base_url = api_url.rstrip("/")
    url = f"{base_url}/api/{endpoint.strip('/')}/?" + parse.urlencode({"limit": "1000"})
    while url:
        payload = request_json(url, token)
        results = payload.get("results", [])
        if not isinstance(results, list):
            raise RuntimeError(f"NetBox {endpoint} response did not contain a results list")
        rows.extend(item for item in results if isinstance(item, dict))
        url = str(payload.get("next") or "")
    return rows


def rows_from_file(path: str) -> list[dict[str, Any]]:
    payload = load_json_file(path)
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict) and isinstance(payload.get("results"), list):
        return [item for item in payload["results"] if isinstance(item, dict)]
    raise RuntimeError(f"{path}: expected a NetBox results object or a list")


def object_tags(row: dict[str, Any]) -> set[str]:
    tags = row.get("tags", [])
    names: set[str] = set()
    if not isinstance(tags, list):
        return names
    for tag in tags:
        if isinstance(tag, dict):
            name = str(tag.get("name") or tag.get("slug") or "").strip()
        else:
            name = str(tag).strip()
        if name:
            names.add(name)
    return names


def has_tag(row: dict[str, Any], tag: str) -> bool:
    if not tag:
        return True
    return tag in object_tags(row)


def nested_name(row: dict[str, Any], key: str) -> str:
    value = row.get(key)
    if isinstance(value, dict):
        return str(value.get("name") or value.get("display") or value.get("slug") or "").strip()
    return str(value or "").strip()


def primary_ip(row: dict[str, Any]) -> dict[str, Any]:
    primary = row.get("primary_ip4") or row.get("primary_ip") or {}
    return primary if isinstance(primary, dict) else {}


def ip_without_prefix(address: str) -> str:
    if not address:
        return ""
    try:
        return str(ipaddress.ip_interface(address).ip)
    except ValueError:
        return address.split("/", 1)[0]


def host_key(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_]+", "_", name.strip().lower()).strip("_")
    return cleaned or "unnamed_host"


def scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return '""'
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if text == "":
        return '""'
    if re.fullmatch(r"[A-Za-z0-9_./:@+-]+", text):
        return text
    return json.dumps(text)


def yaml_dump_inventory(hosts: list[dict[str, Any]]) -> str:
    lines = [
        "---",
        "all:",
        "  children:",
        "    install_targets:",
        "      hosts:",
    ]
    for host in sorted(hosts, key=lambda item: item["inventory_name"]):
        lines.append(f"        {host['inventory_name']}:")
        for key in (
            "ansible_host",
            "ansible_user",
            "ansible_python_interpreter",
            "install_hostname",
            "dns_name",
            "source_type",
            "cluster",
            "site",
            "role",
            "stage5_role",
            "profile",
            "proxmox_vmid",
        ):
            value = host.get(key)
            if value in ("", None):
                continue
            lines.append(f"          {key}: {scalar(value)}")
    return "\n".join(lines) + "\n"


def normalize_host_record(row: dict[str, Any], source_type: str) -> dict[str, Any] | None:
    name = str(row.get("name") or row.get("display") or "").strip()
    primary = primary_ip(row)
    address = str(primary.get("address") or "").strip()
    ip_address = ip_without_prefix(address)
    if not name or not ip_address:
        return None
    dns_name = str(primary.get("dns_name") or row.get("dns_name") or "").strip().rstrip(".")
    custom_fields = row.get("custom_fields", {})
    if not isinstance(custom_fields, dict):
        custom_fields = {}
    stage5_role = str(custom_fields.get("stage5_role") or nested_name(row, "role") or "").strip()
    profile = str(custom_fields.get("profile") or "").strip()
    proxmox_vmid = custom_fields.get("proxmox_vmid", "")
    return {
        "name": name,
        "inventory_name": host_key(name),
        "ansible_host": ip_address,
        "ansible_user": "root",
        "ansible_python_interpreter": "/usr/bin/python3",
        "install_hostname": name,
        "dns_name": dns_name,
        "source_type": source_type,
        "cluster": nested_name(row, "cluster"),
        "site": nested_name(row, "site"),
        "role": nested_name(row, "role"),
        "stage5_role": stage5_role,
        "profile": profile,
        "proxmox_vmid": proxmox_vmid,
        "status": nested_name(row, "status"),
        "ip_address": ip_address,
        "address": address,
        "tags": sorted(object_tags(row)),
    }


def standalone_ip_host_record(row: dict[str, Any], used_ips: set[str]) -> dict[str, Any] | None:
    address = str(row.get("address") or "").strip()
    ip_address = ip_without_prefix(address)
    dns_name = str(row.get("dns_name") or "").strip().rstrip(".")
    if not ip_address or not dns_name or ip_address in used_ips:
        return None
    custom_fields = row.get("custom_fields", {})
    if not isinstance(custom_fields, dict):
        custom_fields = {}
    name = dns_name.split(".", 1)[0]
    return {
        "name": name,
        "inventory_name": host_key(name),
        "ansible_host": ip_address,
        "ansible_user": "root",
        "ansible_python_interpreter": "/usr/bin/python3",
        "install_hostname": name,
        "dns_name": dns_name,
        "source_type": "standalone_ip",
        "cluster": "",
        "site": "",
        "role": "",
        "stage5_role": str(custom_fields.get("stage5_role") or "").strip(),
        "profile": str(custom_fields.get("profile") or "").strip(),
        "proxmox_vmid": custom_fields.get("proxmox_vmid", ""),
        "status": nested_name(row, "status"),
        "ip_address": ip_address,
        "address": address,
        "tags": sorted(object_tags(row)),
    }


def service_ports_from_ip(row: dict[str, Any]) -> list[dict[str, Any]]:
    custom_fields = row.get("custom_fields", {})
    if not isinstance(custom_fields, dict):
        return []
    service_ports = custom_fields.get("service_ports", [])
    if not isinstance(service_ports, list):
        return []
    clean_ports: list[dict[str, Any]] = []
    for item in service_ports:
        if not isinstance(item, dict):
            continue
        try:
            port = int(item.get("port", 0))
        except (TypeError, ValueError):
            continue
        if port <= 0:
            continue
        protocol = str(item.get("protocol", "tcp")).strip().lower()
        if protocol not in {"tcp", "udp"}:
            protocol = "tcp"
        name = str(item.get("name") or f"service-{port}-{protocol}").strip()
        clean_ports.append({"name": name, "port": port, "protocol": protocol})
    return clean_ports


def generate_service_targets(ip_addresses: list[dict[str, Any]], tag: str) -> list[dict[str, Any]]:
    targets: list[dict[str, Any]] = []
    for row in ip_addresses:
        if not has_tag(row, tag):
            continue
        address = str(row.get("address") or "").strip()
        ip_address = ip_without_prefix(address)
        dns_name = str(row.get("dns_name") or "").strip().rstrip(".")
        target = dns_name or ip_address
        if not target:
            continue
        for service in service_ports_from_ip(row):
            targets.append(
                {
                    "service_name": service["name"],
                    "target": target,
                    "ip_address": ip_address,
                    "dns_name": dns_name,
                    "port": service["port"],
                    "protocol": service["protocol"],
                }
            )
    return sorted(targets, key=lambda item: (item["service_name"], item["target"], item["port"]))


def export_provisioning_inventory(
    *,
    virtual_machines: list[dict[str, Any]],
    devices: list[dict[str, Any]],
    ip_addresses: list[dict[str, Any]],
    tag: str,
) -> dict[str, Any]:
    source_order = {"virtual_machine": 0, "device": 1, "standalone_ip": 2}
    vm_hosts = [
        host
        for row in virtual_machines
        if has_tag(row, tag)
        for host in [normalize_host_record(row, "virtual_machine")]
        if host is not None
    ]
    device_hosts = [
        host
        for row in devices
        if has_tag(row, tag)
        for host in [normalize_host_record(row, "device")]
        if host is not None
    ]
    used_ips = {host["ip_address"] for host in vm_hosts + device_hosts if host.get("ip_address")}
    standalone_ip_hosts = [
        host
        for row in ip_addresses
        if has_tag(row, tag)
        for host in [standalone_ip_host_record(row, used_ips)]
        if host is not None
    ]
    hosts = sorted(vm_hosts + device_hosts + standalone_ip_hosts, key=lambda item: (source_order.get(item["source_type"], 99), item["name"]))
    ipam_records = sorted(
        [
            {
                "name": host["name"],
                "source_type": host["source_type"],
                "ip_address": host["ip_address"],
                "address": host["address"],
                "dns_name": host["dns_name"],
                "cluster": host["cluster"],
                "site": host["site"],
                "role": host["role"],
                "stage5_role": host["stage5_role"],
                "profile": host["profile"],
                "tags": host["tags"],
            }
            for host in hosts
        ],
        key=lambda item: (source_order.get(item["source_type"], 99), item["name"]),
    )
    service_targets = generate_service_targets(ip_addresses, tag)
    return {
        "inventory": yaml_dump_inventory(hosts),
        "ipam": {
            "summary": {
                "devices": len(device_hosts),
                "ip_addresses": len([row for row in ip_addresses if has_tag(row, tag)]),
                "standalone_ip_hosts": len(standalone_ip_hosts),
                "virtual_machines": len(vm_hosts),
            },
            "records": ipam_records,
        },
        "service_targets": {
            "summary": {"targets": len(service_targets)},
            "targets": service_targets,
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--netbox-api-url", default=os.getenv("NETBOX_API_URL", "http://172.16.99.62"))
    parser.add_argument("--netbox-token", default=os.getenv("NETBOX_TOKEN", ""))
    parser.add_argument("--netbox-token-file", default=os.getenv("NETBOX_TOKEN_FILE", ""))
    parser.add_argument("--virtual-machines-file", default="")
    parser.add_argument("--devices-file", default="")
    parser.add_argument("--ip-addresses-file", default="")
    parser.add_argument("--tag", default="codex-managed")
    parser.add_argument("--inventory-output", required=True)
    parser.add_argument("--ipam-output", required=True)
    parser.add_argument("--service-targets-output", required=True)
    return parser.parse_args()


def write_json(path: str, payload: dict[str, Any]) -> None:
    Path(path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    token = args.netbox_token
    if not token and args.netbox_token_file:
        token = load_token(args.netbox_token_file)

    virtual_machines = (
        rows_from_file(args.virtual_machines_file)
        if args.virtual_machines_file
        else fetch_paginated(args.netbox_api_url, "virtualization/virtual-machines", token)
    )
    devices = rows_from_file(args.devices_file) if args.devices_file else fetch_paginated(args.netbox_api_url, "dcim/devices", token)
    ip_addresses = (
        rows_from_file(args.ip_addresses_file)
        if args.ip_addresses_file
        else fetch_paginated(args.netbox_api_url, "ipam/ip-addresses", token)
    )

    exports = export_provisioning_inventory(
        virtual_machines=virtual_machines,
        devices=devices,
        ip_addresses=ip_addresses,
        tag=args.tag,
    )
    Path(args.inventory_output).write_text(exports["inventory"], encoding="utf-8")
    write_json(args.ipam_output, exports["ipam"])
    write_json(args.service_targets_output, exports["service_targets"])
    sys.stdout.write(
        json.dumps(
            {
                "inventory_output": args.inventory_output,
                "ipam_output": args.ipam_output,
                "service_targets_output": args.service_targets_output,
                "summary": {
                    **exports["ipam"]["summary"],
                    "service_targets": exports["service_targets"]["summary"]["targets"],
                },
            },
            sort_keys=True,
        )
        + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
