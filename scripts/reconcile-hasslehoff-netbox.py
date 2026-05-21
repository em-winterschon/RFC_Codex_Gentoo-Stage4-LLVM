#!/usr/bin/env python3
"""Reconcile live Hasslehoff Proxmox inventory into NetBox.

Default mode is a dry-run. Passing --apply is required for NetBox writes.

Scope is intentionally narrow and additive:

- Proxmox cluster prx-rfc99-prime
- Hasslehoff and nanoprime cluster membership
- live Hasslehoff QEMU VMs
- VM interfaces, MAC addresses, configured IP addresses, and selected services

The script does not delete, retire, or reclassify stale DCIM placeholders.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import requests


DEFAULT_API_URL = "http://172.16.99.62/api"
DEFAULT_TOKEN_FILE = "/root/operator-private/netbox/svc-netbox-stage4-admin-token"
DEFAULT_PROXMOX_SSH_HOST = "hasslehoff"
DEFAULT_PROXMOX_NODE = "hasslehoff"
DEFAULT_SITE = "local-rfc1918-lab"
DEFAULT_CLUSTER = "prx-rfc99-prime"
DEFAULT_CLUSTER_TYPE = "proxmox"
DEFAULT_HYPERVISOR_TYPE = "Proxmox-8.4-host"
DEFAULT_HYPERVISOR_ROLE = "proxmox-hypervisor"


ROLE_BY_VM_NAME = {
    "gw-rfc99-vyos-routeprime": "vyos-router",
    "ctbsd-rfc99-jailerprime-099099": "retired-freebsd-jail-host",
    "eph-sun99-sourcebot-099229": "sourcebot",
    "svc-netbox-stage4": "ipam-dcim",
    "svc-identity-ipa01": "identity-controller",
    "obs-sun99-prometheus-099064": "observability-prometheus",
    "obs-sun99-vmetrics-099065": "observability-victoriametrics",
    "obs-sun99-grafana-099066": "observability-grafana",
    "obs-sun99-kibana-099067": "observability-kibana",
    "sched-sun99-slurmctl-099071": "slurm-controller",
    "sched-sun99-slurmwkr-099072": "slurm-worker",
    "boot-sun99-netboot-099088": "netboot-publisher",
    "svc-container-services-safe-move-01": "container-services-staging",
    "obs-sun99-esstage-099091": "observability-elasticsearch",
    "vm-workstation-nscde-gpu01": "workstation-vm",
}


ROLE_TITLES = {
    "vyos-router": "vyos-router",
    "sourcebot": "sourcebot",
    "observability-kibana": "observability-kibana",
    "netboot-publisher": "netboot-publisher",
    "observability-elasticsearch": "observability-elasticsearch",
    "workstation-vm": "workstation-vm",
}


SERVICE_PLAN = {
    "svc-netbox-stage4": [("netbox-http", "tcp", [80])],
    "svc-identity-ipa01": [
        ("ldap", "tcp", [389, 636]),
        ("radius", "udp", [1812, 1813]),
    ],
    "obs-sun99-prometheus-099064": [("prometheus", "tcp", [9090])],
    "obs-sun99-vmetrics-099065": [
        ("victoriametrics-http", "tcp", [8428]),
        ("graphite-tcp", "tcp", [2003]),
        ("collectd-udp", "udp", [25826]),
        ("vmagent", "tcp", [9103]),
    ],
    "obs-sun99-grafana-099066": [("grafana", "tcp", [3000])],
    "obs-sun99-kibana-099067": [("kibana", "tcp", [5601])],
    "sched-sun99-slurmctl-099071": [("slurm-controller", "tcp", [6817, 6819])],
    "sched-sun99-slurmwkr-099072": [("slurm-worker", "tcp", [6818])],
    "boot-sun99-netboot-099088": [
        ("http-netboot", "tcp", [80]),
        ("tftp-netboot", "udp", [69]),
    ],
    "obs-sun99-esstage-099091": [("elasticsearch", "tcp", [9200, 9300])],
}


@dataclass
class VmEvidence:
    vmid: int
    name: str
    status: str
    cpus: int | None
    memory_mb: int | None
    disk_gb: int | None
    config: dict[str, str]
    nets: list[dict[str, Any]] = field(default_factory=list)
    addresses: list[tuple[str, str]] = field(default_factory=list)


class NetBox:
    def __init__(self, api_url: str, token_file: str, apply: bool) -> None:
        self.api_url = api_url.rstrip("/")
        self.apply = apply
        self.created: list[str] = []
        self.updated: list[str] = []
        self.existing: list[str] = []
        self.conflicts: list[str] = []
        self._dry_id = -1
        token = Path(token_file).read_text(encoding="utf-8").strip()
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Token {token}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            }
        )

    def all(self, endpoint: str, **params: Any) -> list[dict[str, Any]]:
        params.setdefault("limit", 1000)
        url = f"{self.api_url}/{endpoint.strip('/')}/"
        out: list[dict[str, Any]] = []
        while url:
            response = self.session.get(url, params=params if "?" not in url else None, timeout=20)
            response.raise_for_status()
            data = response.json()
            out.extend(data.get("results", []))
            url = data.get("next")
            params = {}
        return out

    def first(self, endpoint: str, **params: Any) -> dict[str, Any] | None:
        rows = self.all(endpoint, **params)
        return rows[0] if rows else None

    def dry_object(self, payload: dict[str, Any]) -> dict[str, Any]:
        obj = {"id": self._dry_id, "url": f"dry-run://{abs(self._dry_id)}", **payload}
        self._dry_id -= 1
        return obj

    def post(self, endpoint: str, payload: dict[str, Any], label: str) -> dict[str, Any] | None:
        if not self.apply:
            self.created.append(f"DRY create {label}")
            return self.dry_object(payload)
        response = self.session.post(f"{self.api_url}/{endpoint.strip('/')}/", json=payload, timeout=20)
        if response.status_code >= 400:
            self.conflicts.append(f"create failed {label}: {response.status_code} {response.text[:500]}")
            return None
        self.created.append(f"created {label}")
        return response.json()

    def patch(self, obj: dict[str, Any], payload: dict[str, Any], label: str) -> dict[str, Any] | None:
        if not payload:
            return obj
        if not self.apply:
            self.updated.append(f"DRY update {label}")
            return {**obj, **payload}
        response = self.session.patch(obj["url"], json=payload, timeout=20)
        if response.status_code >= 400:
            self.conflicts.append(f"update failed {label}: {response.status_code} {response.text[:500]}")
            return None
        self.updated.append(f"updated {label}")
        return response.json()

    def ensure(
        self,
        endpoint: str,
        label: str,
        lookup: dict[str, Any],
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        existing = self.first(endpoint, **lookup)
        if existing:
            self.existing.append(label)
            return existing
        return self.post(endpoint, payload, label)


def ssh_text(host: str, command: str) -> str:
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host, command],
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout


def ssh_json(host: str, command: str) -> Any:
    return json.loads(ssh_text(host, command))


def parse_config(text: str) -> dict[str, str]:
    config: dict[str, str] = {}
    for line in text.splitlines():
        if line and not line.startswith("#") and ": " in line:
            key, value = line.split(": ", 1)
            config[key] = value
    return config


def parse_net_line(name: str, value: str) -> dict[str, Any]:
    item: dict[str, Any] = {"name": name, "raw": value}
    first, *rest = value.split(",")
    if "=" in first:
        model, mac = first.split("=", 1)
        item["model"] = model
        item["mac"] = mac.lower()
    for part in rest:
        if "=" in part:
            key, val = part.split("=", 1)
            item[key] = val
    return item


def configured_addresses(config: dict[str, str], vm_name: str) -> list[tuple[str, str]]:
    addresses: list[tuple[str, str]] = []
    for key, value in config.items():
        if not key.startswith("ipconfig"):
            continue
        index = key.removeprefix("ipconfig")
        match = re.search(r"\bip=([^,\s]+)", value)
        if match and match.group(1) != "dhcp":
            addresses.append((f"net{index}", match.group(1)))
    # Static exceptions observed in live service state but not represented in
    # cloud-init ipconfig on these legacy VMs.
    if vm_name == "svc-netbox-stage4":
        addresses.append(("net0", "172.16.99.62/24"))
    if vm_name == "obs-sun99-esstage-099091":
        addresses.append(("net0", "10.9.8.91/24"))
    return sorted(set(addresses))


def collect_vms(proxmox_host: str, proxmox_node: str) -> list[VmEvidence]:
    rows = ssh_json(proxmox_host, f"pvesh get /nodes/{proxmox_node}/qemu --output-format json")
    vms: list[VmEvidence] = []
    for row in sorted(rows, key=lambda item: int(item["vmid"])):
        vmid = int(row["vmid"])
        config = parse_config(ssh_text(proxmox_host, f"qm config {vmid}"))
        nets = [
            parse_net_line(key, value)
            for key, value in sorted(config.items())
            if re.fullmatch(r"net\d+", key)
        ]
        maxdisk = int(row.get("maxdisk") or 0)
        vms.append(
            VmEvidence(
                vmid=vmid,
                name=str(row["name"]),
                status=str(row["status"]),
                cpus=int(config.get("cores", row.get("cpus") or 0)) or None,
                memory_mb=int(config["memory"]) if config.get("memory", "").isdigit() else None,
                disk_gb=round(maxdisk / 1024 / 1024 / 1024) if maxdisk else None,
                config=config,
                nets=nets,
                addresses=configured_addresses(config, str(row["name"])),
            )
        )
    return vms


def normalize_ip(address: str) -> str:
    return str(ipaddress.ip_interface(address))


def ensure_vm_role(nb: NetBox, role_slug: str) -> dict[str, Any] | None:
    role = nb.first("dcim/device-roles", slug=role_slug)
    if role:
        if not role.get("vm_role"):
            return nb.patch(role, {"vm_role": True}, f"role {role_slug} vm_role=true") or role
        return role
    return nb.post(
        "dcim/device-roles",
        {
            "name": ROLE_TITLES.get(role_slug, role_slug),
            "slug": role_slug,
            "color": "9e9e9e",
            "vm_role": True,
            "description": "Created from Hasslehoff Proxmox reconciliation",
        },
        f"role {role_slug}",
    )


def ensure_mac(nb: NetBox, mac: str, assigned_type: str, assigned_id: int, label: str) -> dict[str, Any] | None:
    existing = nb.first("dcim/mac-addresses", mac_address=mac)
    if existing:
        assigned = existing.get("assigned_object")
        if not assigned:
            return nb.patch(
                existing,
                {"assigned_object_type": assigned_type, "assigned_object_id": assigned_id},
                f"MAC {mac} assign {label}",
            ) or existing
        return existing
    return nb.post(
        "dcim/mac-addresses",
        {
            "mac_address": mac,
            "assigned_object_type": assigned_type,
            "assigned_object_id": assigned_id,
            "description": f"Observed on {label}",
        },
        f"MAC {mac} for {label}",
    )


def ensure_ip(
    nb: NetBox,
    address: str,
    dns_name: str,
    description: str,
    assigned_type: str,
    assigned_id: int,
    label: str,
) -> dict[str, Any] | None:
    normalized = normalize_ip(address)
    existing = nb.first("ipam/ip-addresses", address=normalized)
    payload = {
        "address": normalized,
        "status": "active",
        "dns_name": dns_name,
        "description": description[:200],
        "assigned_object_type": assigned_type,
        "assigned_object_id": assigned_id,
    }
    if not existing:
        return nb.post("ipam/ip-addresses", payload, f"IP {normalized} for {label}")

    current_type = existing.get("assigned_object_type")
    current_id = existing.get("assigned_object_id")
    if current_type in (None, ""):
        return nb.patch(existing, payload, f"IP {normalized} assign {label}") or existing
    if current_type == assigned_type and current_id == assigned_id:
        return existing
    nb.conflicts.append(
        f"IP {normalized} already assigned to {current_type}:{current_id}; left unchanged for {label}"
    )
    return existing


def ensure_service(nb: NetBox, vm: dict[str, Any], ip_ids: list[int], name: str, protocol: str, ports: list[int]) -> None:
    services = nb.all(
        "ipam/services",
        parent_object_type="virtualization.virtualmachine",
        parent_object_id=vm["id"],
        name=name,
    )
    for service in services:
        if service.get("protocol", {}).get("value") == protocol:
            current_ids = sorted(ip["id"] for ip in service.get("ipaddresses", []))
            desired_ids = sorted(set(current_ids + ip_ids))
            payload: dict[str, Any] = {}
            if sorted(service.get("ports", [])) != sorted(ports):
                payload["ports"] = ports
            if desired_ids != current_ids:
                payload["ipaddresses"] = desired_ids
            nb.patch(service, payload, f"service {vm['name']} {name}/{protocol}")
            return
    nb.post(
        "ipam/services",
        {
            "parent_object_type": "virtualization.virtualmachine",
            "parent_object_id": vm["id"],
            "name": name,
            "protocol": protocol,
            "ports": ports,
            "ipaddresses": ip_ids,
            "description": "Created from Hasslehoff/NetBox reconciliation",
        },
        f"service {vm['name']} {name}/{protocol}:{ports}",
    )


def reconcile(args: argparse.Namespace) -> dict[str, Any]:
    nb = NetBox(args.api_url, args.token_file, args.apply)
    site = nb.first("dcim/sites", name=args.site)
    cluster_type = nb.first("virtualization/cluster-types", slug=args.cluster_type)
    hypervisor_role = nb.first("dcim/device-roles", slug=args.hypervisor_role)
    hypervisor_type = nb.first("dcim/device-types", model=args.hypervisor_type)
    if not all([site, cluster_type, hypervisor_role, hypervisor_type]):
        raise RuntimeError("missing baseline NetBox site/cluster-type/device-role/device-type")

    cluster = nb.ensure(
        "virtualization/clusters",
        f"cluster {args.cluster_name}",
        {"name": args.cluster_name},
        {
            "name": args.cluster_name,
            "type": cluster_type["id"],
            "status": "active",
            "description": f"Live Proxmox cluster observed from {args.proxmox_ssh_host} pvesh",
        },
    )

    hasslehoff = nb.first("dcim/devices", name=args.proxmox_node)
    if hasslehoff and cluster and not hasslehoff.get("cluster"):
        nb.patch(hasslehoff, {"cluster": cluster["id"]}, f"device {args.proxmox_node} cluster membership")

    nanoprime = nb.ensure(
        "dcim/devices",
        "device nanoprime",
        {"name": "nanoprime"},
        {
            "name": "nanoprime",
            "site": site["id"],
            "device_type": hypervisor_type["id"],
            "role": hypervisor_role["id"],
            "status": "active",
            "cluster": cluster["id"] if cluster else None,
            "comments": "Observed online in Proxmox cluster prx-rfc99-prime and verified by SSH from M70 on 2026-05-21.",
        },
    )
    if nanoprime and cluster and not nanoprime.get("cluster"):
        nb.patch(nanoprime, {"cluster": cluster["id"]}, "device nanoprime cluster membership")

    if nanoprime:
        for iface_name, iface_type, description, address, dns_name in [
            ("eth0", "1000base-t", "Observed physical interface; bridge member of mgmt-net0", None, None),
            ("eth1", "1000base-t", "Observed physical interface; bridge member of ceph-net0", None, None),
            ("eth2", "1000base-t", "Observed physical interface; bridge member of ceph-net0", None, None),
            ("mgmt-net0", "bridge", "Management bridge 172.16.99.13/24 via eth0", "172.16.99.13/24", "nanoprime.rfc1918.host"),
            ("ceph-net0", "bridge", "Ceph/private bridge 10.232.232.13/24 via eth1 eth2", "10.232.232.13/24", "nanoprime-ceph.rfc1918.host"),
        ]:
            iface = nb.ensure(
                "dcim/interfaces",
                f"nanoprime interface {iface_name}",
                {"device_id": nanoprime["id"], "name": iface_name},
                {
                    "device": nanoprime["id"],
                    "name": iface_name,
                    "type": iface_type,
                    "enabled": True,
                    "description": description,
                },
            )
            if iface and address and dns_name:
                ip = ensure_ip(
                    nb,
                    address,
                    dns_name,
                    f"{iface_name} IP for nanoprime",
                    "dcim.interface",
                    iface["id"],
                    f"nanoprime {iface_name}",
                )
                if iface_name == "mgmt-net0" and ip and nanoprime.get("primary_ip4") is None:
                    nb.patch(nanoprime, {"primary_ip4": ip["id"]}, "nanoprime primary_ip4")

    roles = {slug: ensure_vm_role(nb, slug) for slug in sorted(set(ROLE_BY_VM_NAME.values()))}
    vms = collect_vms(args.proxmox_ssh_host, args.proxmox_node)

    for evidence in vms:
        role_slug = ROLE_BY_VM_NAME.get(evidence.name, "service-vm")
        role = roles.get(role_slug) or ensure_vm_role(nb, role_slug)
        vm = nb.ensure(
            "virtualization/virtual-machines",
            f"VM {evidence.vmid} {evidence.name}",
            {"name": evidence.name},
            {
                "name": evidence.name,
                "status": "active" if evidence.status == "running" else "offline",
                "cluster": cluster["id"] if cluster else None,
                "device": hasslehoff["id"] if hasslehoff else None,
                "site": site["id"],
                "role": role["id"] if role else None,
                "vcpus": evidence.cpus,
                "memory": evidence.memory_mb,
                "disk": evidence.disk_gb,
                "description": f"Proxmox VMID {evidence.vmid} on {args.proxmox_node}",
                "comments": f"Observed from Hasslehoff pvesh/qm config on 2026-05-21. VMID={evidence.vmid}.",
            },
        )
        if not vm:
            continue

        vm_ip_ids: list[int] = []
        iface_by_name: dict[str, dict[str, Any]] = {}
        for net in evidence.nets:
            iface = nb.ensure(
                "virtualization/interfaces",
                f"VM {evidence.name} interface {net['name']}",
                {"virtual_machine_id": vm["id"], "name": net["name"]},
                {
                    "virtual_machine": vm["id"],
                    "name": net["name"],
                    "enabled": True,
                    "description": f"Proxmox {net['raw']}"[:200],
                },
            )
            if not iface:
                continue
            iface_by_name[net["name"]] = iface
            mac = net.get("mac")
            if mac:
                mac_obj = ensure_mac(nb, mac, "virtualization.vminterface", iface["id"], f"{evidence.name} {net['name']}")
                if mac_obj and iface.get("primary_mac_address") is None:
                    nb.patch(iface, {"primary_mac_address": mac_obj["id"]}, f"VM {evidence.name} {net['name']} primary MAC")

        for iface_name, address in evidence.addresses:
            iface = iface_by_name.get(iface_name)
            if not iface:
                continue
            ip = ensure_ip(
                nb,
                address,
                f"{evidence.name}.rfc1918.host",
                f"Configured IP for Proxmox VM {evidence.vmid} {evidence.name}",
                "virtualization.vminterface",
                iface["id"],
                f"{evidence.name} {iface_name}",
            )
            if ip and ip.get("assigned_object_type") == "virtualization.vminterface":
                vm_ip_ids.append(ip["id"])
                if vm.get("primary_ip4") is None and ipaddress.ip_interface(ip["address"]).version == 4:
                    nb.patch(vm, {"primary_ip4": ip["id"]}, f"VM {evidence.name} primary_ip4")

        if evidence.name in SERVICE_PLAN:
            all_ip_ids = sorted(
                set(
                    vm_ip_ids
                    + [
                        item["id"]
                        for item in nb.all(
                            "ipam/ip-addresses",
                            dns_name=f"{evidence.name}.rfc1918.host",
                        )
                    ]
                )
            )
            for service_name, protocol, ports in SERVICE_PLAN[evidence.name]:
                ensure_service(nb, vm, all_ip_ids, service_name, protocol, ports)

    return {
        "apply": args.apply,
        "proxmox_ssh_host": args.proxmox_ssh_host,
        "proxmox_node": args.proxmox_node,
        "cluster_name": args.cluster_name,
        "live_vm_count": len(vms),
        "created": nb.created,
        "updated": nb.updated,
        "existing_count": len(nb.existing),
        "conflicts": nb.conflicts,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", default=DEFAULT_API_URL)
    parser.add_argument("--token-file", default=DEFAULT_TOKEN_FILE)
    parser.add_argument("--proxmox-ssh-host", default=DEFAULT_PROXMOX_SSH_HOST)
    parser.add_argument("--proxmox-node", default=DEFAULT_PROXMOX_NODE)
    parser.add_argument("--site", default=DEFAULT_SITE)
    parser.add_argument("--cluster-name", default=DEFAULT_CLUSTER)
    parser.add_argument("--cluster-type", default=DEFAULT_CLUSTER_TYPE)
    parser.add_argument("--hypervisor-type", default=DEFAULT_HYPERVISOR_TYPE)
    parser.add_argument("--hypervisor-role", default=DEFAULT_HYPERVISOR_ROLE)
    parser.add_argument("--apply", action="store_true", help="perform NetBox writes")
    return parser.parse_args()


def main() -> int:
    result = reconcile(parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if result["conflicts"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
