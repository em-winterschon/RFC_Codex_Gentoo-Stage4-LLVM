#!/usr/bin/env python3
"""Apply structured inventory intake definitions to NetBox.

The default mode is an offline dry-run plan. Passing --apply is required before
the script performs NetBox API writes.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib import error, parse, request

from validate_netbox_inventory_intake import intake_paths, validate_files


def require_yaml() -> Any:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - depends on local environment
        raise SystemExit("PyYAML is required. Install python yaml support first.") from exc
    return yaml


def slugify(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "item"


def status_for_prefix(value: str | None) -> str:
    if value in {"active", "container-only", "provider-assigned"}:
        return "active"
    if value == "deprecated":
        return "deprecated"
    return "reserved"


def status_for_device(value: str | None) -> str:
    if value in {None, "", "active", "running"}:
        return "active"
    if value in {"planned", "reserved"}:
        return "planned"
    if "retired" in value or "offline" in value or "stopped" in value:
        return "offline"
    return "active"


def ip_host(value: str) -> str:
    return str(ipaddress.ip_interface(value).ip)


def ip_hosts_match(left: str, right: str) -> bool:
    return ip_host(left) == ip_host(right)


def load_intake_files(paths: list[Path]) -> list[tuple[Path, dict[str, Any]]]:
    yaml = require_yaml()
    payloads: list[tuple[Path, dict[str, Any]]] = []
    for path in paths:
        with path.open("r", encoding="utf-8") as handle:
            payload = yaml.safe_load(handle)
        if isinstance(payload, dict):
            payloads.append((path, payload))
    return payloads


@dataclass
class NetBoxObject:
    endpoint: str
    lookup_key: str
    lookup_value: str
    payload: dict[str, Any]

    @property
    def label(self) -> str:
        return f"{self.endpoint}:{self.lookup_value}"


class NetBoxClient:
    def __init__(
        self,
        *,
        api_url: str,
        token: str,
        auth_scheme: str,
        dry_run: bool,
        update_existing: bool,
    ) -> None:
        self.api_url = api_url.rstrip("/")
        self.token = token.strip()
        self.auth_scheme = auth_scheme
        self.dry_run = dry_run
        self.update_existing = update_existing
        self.created: list[str] = []
        self.updated: list[str] = []
        self.existing: list[str] = []
        self.planned: list[str] = []
        self._dry_run_objects: dict[str, dict[str, Any]] = {}
        self._next_dry_run_id = -1

    def authorization_header(self) -> str:
        scheme = self.auth_scheme
        if scheme == "auto":
            scheme = "Bearer" if self.token.startswith("nbt_") else "Token"
        return f"{scheme} {self.token}"

    def request_json(
        self,
        method: str,
        endpoint: str,
        payload: dict[str, Any] | None = None,
        *,
        query: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        endpoint = endpoint.strip("/")
        url = f"{self.api_url}/api/{endpoint}/"
        if query:
            url += "?" + parse.urlencode(query)
        data = None
        headers = {
            "Accept": "application/json",
            "Authorization": self.authorization_header(),
        }
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = request.Request(url, data=data, headers=headers, method=method)
        try:
            with request.urlopen(req, timeout=30) as response:  # noqa: S310
                raw = response.read().decode("utf-8")
        except error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"NetBox {method} {endpoint} failed: HTTP {exc.code}: {body}"
            ) from exc
        return json.loads(raw) if raw else {}

    def first(self, endpoint: str, lookup_key: str, lookup_value: str) -> dict[str, Any] | None:
        result = self.request_json("GET", endpoint, query={lookup_key: lookup_value})
        rows = result.get("results", [])
        if isinstance(rows, list) and rows:
            return rows[0]
        return None

    def first_query(self, endpoint: str, query: dict[str, str]) -> dict[str, Any] | None:
        result = self.request_json("GET", endpoint, query=query)
        rows = result.get("results", [])
        if isinstance(rows, list) and rows:
            return rows[0]
        return None

    def dry_run_object(self, obj: NetBoxObject) -> dict[str, Any]:
        if obj.label not in self._dry_run_objects:
            self._dry_run_objects[obj.label] = {"id": self._next_dry_run_id, **obj.payload}
            self._next_dry_run_id -= 1
            self.planned.append(obj.label)
        return self._dry_run_objects[obj.label]

    def ensure(self, obj: NetBoxObject) -> dict[str, Any]:
        if self.dry_run:
            return self.dry_run_object(obj)

        existing = self.first(obj.endpoint, obj.lookup_key, obj.lookup_value)
        if obj.endpoint == "ipam/ip-addresses" and existing is None:
            existing = self.first_ip_by_host(obj.lookup_value)
        if existing:
            self.existing.append(obj.label)
            if self.update_existing:
                updated = self.request_json(
                    "PATCH", f"{obj.endpoint}/{existing['id']}", obj.payload
                )
                self.updated.append(obj.label)
                return updated
            return existing

        created = self.request_json("POST", obj.endpoint, obj.payload)
        self.created.append(obj.label)
        return created

    def first_ip_by_host(self, address: str) -> dict[str, Any] | None:
        result = self.request_json("GET", "ipam/ip-addresses", query={"q": ip_host(address)})
        rows = result.get("results", [])
        if not isinstance(rows, list):
            return None
        for row in rows:
            existing_address = row.get("address")
            if isinstance(existing_address, str) and ip_hosts_match(existing_address, address):
                return row
        return None


def matching_address(value: str, networks: list[ipaddress._BaseNetwork]) -> str:
    if "/" in value:
        return value
    address = ipaddress.ip_address(value)
    for network in networks:
        if address.version == network.version and address in network:
            return f"{address}/{network.prefixlen}"
    return f"{address}/32" if address.version == 4 else f"{address}/128"


def build_networks(payloads: list[tuple[Path, dict[str, Any]]]) -> list[ipaddress._BaseNetwork]:
    networks: list[ipaddress._BaseNetwork] = []
    for _, payload in payloads:
        for prefix in payload.get("prefixes", []) or []:
            if isinstance(prefix, dict) and isinstance(prefix.get("prefix"), str):
                networks.append(ipaddress.ip_network(prefix["prefix"], strict=False))
    return networks


def ensure_site(client: NetBoxClient, site: dict[str, Any]) -> dict[str, Any]:
    slug = site["slug"]
    return client.ensure(
        NetBoxObject(
            "dcim/sites",
            "slug",
            slug,
            {
                "name": site["name"],
                "slug": slug,
                "status": "active",
                "facility": site.get("facility", ""),
                "time_zone": site.get("timezone", "UTC"),
            },
        )
    )


def ensure_manufacturer(client: NetBoxClient, name: str) -> dict[str, Any]:
    return client.ensure(
        NetBoxObject(
            "dcim/manufacturers",
            "slug",
            slugify(name),
            {"name": name, "slug": slugify(name)},
        )
    )


def ensure_device_role(client: NetBoxClient, role: str) -> dict[str, Any]:
    return client.ensure(
        NetBoxObject(
            "dcim/device-roles",
            "slug",
            slugify(role),
            {"name": role, "slug": slugify(role), "color": "607d8b"},
        )
    )


def ensure_device_type(
    client: NetBoxClient, manufacturer: dict[str, Any], model: str
) -> dict[str, Any]:
    slug = slugify(model)
    if client.dry_run:
        return client.ensure(
            NetBoxObject(
                "dcim/device-types",
                "slug",
                slug,
                {"manufacturer": manufacturer["id"], "model": model, "slug": slug},
            )
        )

    existing = client.first_query(
        "dcim/device-types",
        {"manufacturer_id": str(manufacturer["id"]), "model": model},
    )
    if existing:
        label = f"dcim/device-types:{model}"
        client.existing.append(label)
        return existing

    return client.ensure(
        NetBoxObject(
            "dcim/device-types",
            "slug",
            slug,
            {"manufacturer": manufacturer["id"], "model": model, "slug": slug},
        )
    )


def device_by_name(client: NetBoxClient, name: str) -> dict[str, Any] | None:
    if client.dry_run:
        for obj in client._dry_run_objects.values():
            if obj.get("name") == name:
                return obj
        return None
    return client.first("dcim/devices", "name", name)


def interface_by_device_and_name(
    client: NetBoxClient, device: dict[str, Any], name: str
) -> dict[str, Any] | None:
    if client.dry_run:
        label = f"dcim/interfaces:{device['name']}:{name}"
        return client._dry_run_objects.get(label)
    return client.first_query(
        "dcim/interfaces",
        {"device_id": str(device["id"]), "name": name},
    )


def power_port_by_device_and_name(
    client: NetBoxClient, device: dict[str, Any], name: str
) -> dict[str, Any] | None:
    if client.dry_run:
        label = f"dcim/power-ports:{device['name']}:{name}"
        return client._dry_run_objects.get(label)
    return client.first_query(
        "dcim/power-ports",
        {"device_id": str(device["id"]), "name": name},
    )


def cable_has_termination(cable: dict[str, Any], object_type: str, object_id: int) -> bool:
    for side in ("a_terminations", "b_terminations"):
        for termination in cable.get(side, []) or []:
            if not isinstance(termination, dict):
                continue
            termination_type = termination.get("object_type")
            termination_id = termination.get("object_id")
            if termination_id is None and isinstance(termination.get("object"), dict):
                termination_id = termination["object"].get("id")
            try:
                if termination_type == object_type and int(termination_id) == int(object_id):
                    return True
            except (TypeError, ValueError):
                continue
    return False


def cable_between_terminations(
    client: NetBoxClient,
    left_type: str,
    left_id: int,
    right_type: str,
    right_id: int,
) -> dict[str, Any] | None:
    result = client.request_json("GET", "dcim/cables", query={"limit": "0"})
    rows = result.get("results", [])
    if not isinstance(rows, list):
        return None
    for row in rows:
        if not isinstance(row, dict):
            continue
        left_matches = cable_has_termination(row, left_type, left_id)
        right_matches = cable_has_termination(row, right_type, right_id)
        if left_matches and right_matches:
            return row
    return None


def ensure_device_interface(
    client: NetBoxClient,
    device: dict[str, Any],
    interface: dict[str, Any],
) -> dict[str, Any]:
    name = str(interface["name"])
    payload: dict[str, Any] = {
        "device": device["id"],
        "name": name,
        "type": normalize_interface_type(interface),
        "enabled": interface.get("status", "active") != "disabled",
        "description": str(interface.get("purpose", "")),
        "mark_connected": bool(interface.get("connected_device")),
    }
    mac_address = interface.get("mac_address") or interface.get("mac")
    if mac_address:
        payload["mac_address"] = str(mac_address).lower()
    if interface.get("purpose") == "management":
        payload["mgmt_only"] = True

    if client.dry_run:
        return client.ensure(
            NetBoxObject(
                "dcim/interfaces",
                "name",
                f"{device['name']}:{name}",
                {"_device_name": device["name"], **payload},
            )
        )

    existing = interface_by_device_and_name(client, device, name)
    label = f"dcim/interfaces:{device['name']}:{name}"
    if existing:
        client.existing.append(label)
        if client.update_existing:
            updated = client.request_json("PATCH", f"dcim/interfaces/{existing['id']}", payload)
            client.updated.append(label)
            return updated
        return existing
    created = client.request_json("POST", "dcim/interfaces", payload)
    client.created.append(label)
    return created


def normalize_interface_type(interface: dict[str, Any]) -> str:
    raw_type = str(interface.get("type", "") or "").strip().lower()
    media = str(interface.get("media", "") or "").strip().lower()
    name = str(interface.get("name", "") or "").strip().lower()

    if raw_type == "1gbase-t":
        return "1000base-t"
    if raw_type == "10gbase-x-sfpp":
        return "10gbase-cu" if "dac" in media else "10gbase-sr"
    if raw_type == "40gbase-x-qsfpp":
        return "40gbase-sr4"
    if raw_type:
        return raw_type
    if name.startswith("ge") or name.startswith("ether"):
        return "1000base-t"
    if name.startswith("sfp") and "dac" in media:
        return "10gbase-cu"
    if name.startswith("sfp"):
        return "10gbase-sr"
    return "virtual"


def apply_device_interfaces(
    client: NetBoxClient, device: dict[str, Any], source: dict[str, Any]
) -> None:
    for interface in source.get("interfaces", []) or []:
        if isinstance(interface, dict) and interface.get("name"):
            ensure_device_interface(client, device, interface)


def assign_management_ip(
    client: NetBoxClient,
    device: dict[str, Any],
    source: dict[str, Any],
    networks: list[ipaddress._BaseNetwork],
) -> None:
    if not source.get("management_ip"):
        return
    address = matching_address(str(source["management_ip"]), networks)
    management_interface_name = source.get("management_interface") or next(
        (
            interface.get("name")
            for interface in source.get("interfaces", []) or []
            if isinstance(interface, dict)
            and (
                interface.get("purpose") == "management"
                or interface.get("purpose") == "pdu-management"
                or interface.get("name") in {"mgmt", "eth0"}
            )
        ),
        None,
    )
    interface = None
    if management_interface_name:
        interface = interface_by_device_and_name(client, device, str(management_interface_name))

    payload: dict[str, Any] = {
        "address": address,
        "status": "active",
        "dns_name": str(source.get("fqdn", "")),
        "description": f"Management IP for {source['name']}",
    }
    if interface:
        payload["assigned_object_type"] = "dcim.interface"
        payload["assigned_object_id"] = interface["id"]

    ip_object = client.ensure(NetBoxObject("ipam/ip-addresses", "address", address, payload))
    if client.dry_run:
        return
    if interface and not ip_object_is_assigned_to_interface(ip_object, interface):
        return
    primary_payload = primary_ip_update_payload(address, ip_object["id"], interface is not None)
    if primary_payload is None:
        return
    client.request_json("PATCH", f"dcim/devices/{device['id']}", primary_payload)


def primary_ip_update_payload(
    address: str, ip_id: int, interface_bound: bool
) -> dict[str, int] | None:
    if not interface_bound:
        return None
    return {"primary_ip4": ip_id} if "." in address else {"primary_ip6": ip_id}


def ip_object_is_assigned_to_interface(
    ip_object: dict[str, Any], interface: dict[str, Any]
) -> bool:
    if ip_object.get("assigned_object_type") != "dcim.interface":
        return False

    assigned_id = ip_object.get("assigned_object_id")
    if assigned_id is None and isinstance(ip_object.get("assigned_object"), dict):
        assigned_id = ip_object["assigned_object"].get("id")

    try:
        return int(assigned_id) == int(interface["id"])
    except (KeyError, TypeError, ValueError):
        return False


def ensure_power_port(
    client: NetBoxClient,
    device: dict[str, Any],
    name: str,
) -> dict[str, Any]:
    payload = {
        "device": device["id"],
        "name": name,
        "type": "nema-5-15p",
        "description": "Power input tracked from inventory intake.",
        "mark_connected": False,
    }
    if client.dry_run:
        return client.ensure(
            NetBoxObject(
                "dcim/power-ports",
                "name",
                f"{device['name']}:{name}",
                {"_device_name": device["name"], **payload},
            )
        )
    existing = power_port_by_device_and_name(client, device, name)
    label = f"dcim/power-ports:{device['name']}:{name}"
    if existing:
        client.existing.append(label)
        if client.update_existing:
            updated = client.request_json("PATCH", f"dcim/power-ports/{existing['id']}", payload)
            client.updated.append(label)
            return updated
        return existing
    created = client.request_json("POST", "dcim/power-ports", payload)
    client.created.append(label)
    return created


def ensure_power_outlet(
    client: NetBoxClient,
    device: dict[str, Any],
    outlet: dict[str, Any],
    target_power_port: dict[str, Any] | None,
) -> dict[str, Any]:
    name = str(outlet["name"])
    target_description = (
        f"Outlet index {outlet.get('outlet_index')} target "
        f"{outlet.get('target_device', 'unassigned')}"
    )
    if target_power_port:
        target_description += f" power port {target_power_port['name']}"
    payload: dict[str, Any] = {
        "device": device["id"],
        "name": name,
        "label": str(outlet.get("label", "")),
        "type": "nema-5-15r",
        "description": target_description,
        "mark_connected": False,
    }

    if client.dry_run:
        return client.ensure(
            NetBoxObject(
                "dcim/power-outlets",
                "name",
                f"{device['name']}:{name}",
                {"_device_name": device["name"], **payload},
            )
        )

    existing = client.first_query(
        "dcim/power-outlets",
        {"device_id": str(device["id"]), "name": name},
    )
    label = f"dcim/power-outlets:{device['name']}:{name}"
    if existing:
        client.existing.append(label)
        if client.update_existing:
            updated = client.request_json("PATCH", f"dcim/power-outlets/{existing['id']}", payload)
            client.updated.append(label)
            return updated
        return existing
    created = client.request_json("POST", "dcim/power-outlets", payload)
    client.created.append(label)
    return created


def ensure_power_cable(
    client: NetBoxClient,
    source_device: dict[str, Any],
    source_outlet: dict[str, Any],
    source_outlet_payload: dict[str, Any],
    target_device: dict[str, Any],
    target_power_port: dict[str, Any],
) -> dict[str, Any]:
    source_name = str(source_outlet_payload["name"])
    target_name = str(target_power_port["name"])
    lookup_value = f"{source_device['name']}:{source_name}->{target_device['name']}:{target_name}"
    payload = {
        "a_terminations": [
            {
                "object_type": "dcim.poweroutlet",
                "object_id": source_outlet["id"],
            }
        ],
        "b_terminations": [
            {
                "object_type": "dcim.powerport",
                "object_id": target_power_port["id"],
            }
        ],
        "status": "connected",
        "label": lookup_value,
        "description": "Power-chain cable tracked from inventory intake.",
    }

    if client.dry_run:
        return client.ensure(
            NetBoxObject(
                "dcim/cables",
                "label",
                lookup_value,
                payload,
            )
        )

    existing = cable_between_terminations(
        client,
        "dcim.poweroutlet",
        int(source_outlet["id"]),
        "dcim.powerport",
        int(target_power_port["id"]),
    )
    label = f"dcim/cables:{lookup_value}"
    if existing:
        client.existing.append(label)
        if client.update_existing:
            updated = client.request_json("PATCH", f"dcim/cables/{existing['id']}", payload)
            client.updated.append(label)
            return updated
        return existing

    created = client.request_json("POST", "dcim/cables", payload)
    client.created.append(label)
    return created


def apply_power_outlets(
    client: NetBoxClient,
    device: dict[str, Any],
    source: dict[str, Any],
) -> None:
    for outlet in source.get("power_outlets", []) or []:
        if not isinstance(outlet, dict) or not outlet.get("name"):
            continue
        target_power_port = None
        target_device_name = outlet.get("target_device")
        if target_device_name:
            target_device = device_by_name(client, str(target_device_name))
            if target_device:
                target_power_port = ensure_power_port(
                    client,
                    target_device,
                    str(outlet.get("target_power_port", "power0")),
                )
        netbox_outlet = ensure_power_outlet(client, device, outlet, target_power_port)
        if target_power_port and target_device:
            ensure_power_cable(client, device, netbox_outlet, outlet, target_device, target_power_port)


def apply_prefixes(
    client: NetBoxClient,
    prefixes: list[dict[str, Any]],
    sites: dict[str, dict[str, Any]],
    vlan_groups: dict[str, dict[str, Any]],
) -> None:
    for prefix in prefixes:
        site = sites[prefix["site"]]
        vlan_id = None
        vlan = prefix.get("vlan")
        if isinstance(vlan, dict):
            group = vlan_groups.setdefault(
                prefix["site"],
                client.ensure(
                    NetBoxObject(
                        "ipam/vlan-groups",
                        "slug",
                        prefix["site"],
                        {
                            "name": prefix["site"],
                            "slug": prefix["site"],
                            "scope_type": "dcim.site",
                            "scope_id": site["id"],
                        },
                    )
                ),
            )
            created_vlan = client.ensure(
                NetBoxObject(
                    "ipam/vlans",
                    "vid",
                    str(vlan["id"]),
                    {
                        "group": group["id"],
                        "vid": vlan["id"],
                        "name": vlan.get("name", f"vlan-{vlan['id']}"),
                        "status": status_for_prefix(prefix.get("status")),
                    },
                )
            )
            vlan_id = created_vlan["id"]

        payload = {
            "prefix": prefix["prefix"],
            "status": status_for_prefix(prefix.get("status")),
            "site": site["id"],
            "description": prefix.get("role", ""),
        }
        if vlan_id is not None:
            payload["vlan"] = vlan_id
        client.ensure(NetBoxObject("ipam/prefixes", "prefix", prefix["prefix"], payload))


def apply_devices(
    client: NetBoxClient,
    devices: list[dict[str, Any]],
    sites: dict[str, dict[str, Any]],
    networks: list[ipaddress._BaseNetwork],
) -> None:
    for device in devices:
        manufacturer = ensure_manufacturer(client, str(device.get("manufacturer", "Generic")))
        dtype = ensure_device_type(client, manufacturer, str(device.get("model", device["role"])))
        role = ensure_device_role(client, device["role"])
        netbox_device = client.ensure(
            NetBoxObject(
                "dcim/devices",
                "name",
                device["name"],
                {
                    "name": device["name"],
                    "site": sites[device["site"]]["id"],
                    "role": role["id"],
                    "device_type": dtype["id"],
                    "status": status_for_device(device.get("status")),
                    "comments": "\n".join(str(item) for item in device.get("notes", []) or []),
                },
            )
        )
        apply_device_interfaces(client, netbox_device, device)
        assign_management_ip(client, netbox_device, device, networks)

    for device in devices:
        netbox_device = device_by_name(client, device["name"])
        if netbox_device:
            apply_power_outlets(client, netbox_device, device)


def apply_clusters(
    client: NetBoxClient, clusters: list[dict[str, Any]], sites: dict[str, dict[str, Any]]
) -> None:
    for cluster in clusters:
        cluster_type = client.ensure(
            NetBoxObject(
                "virtualization/cluster-types",
                "slug",
                slugify(cluster["role"]),
                {"name": cluster["role"], "slug": slugify(cluster["role"])},
            )
        )
        client.ensure(
            NetBoxObject(
                "virtualization/clusters",
                "name",
                cluster["name"],
                {
                    "name": cluster["name"],
                    "type": cluster_type["id"],
                    "site": sites[cluster["site"]]["id"],
                    "description": cluster.get("endpoint", ""),
                },
            )
        )


def apply_service_vips(
    client: NetBoxClient,
    service_vips: list[dict[str, Any]],
    networks: list[ipaddress._BaseNetwork],
) -> None:
    for vip in service_vips:
        address = matching_address(str(vip["address"]), networks)
        listeners = vip.get("listeners", []) or []
        listener_text = ", ".join(
            f"{item['protocol']}/{item['port']}" for item in listeners if isinstance(item, dict)
        )
        client.ensure(
            NetBoxObject(
                "ipam/ip-addresses",
                "address",
                address,
                {
                    "address": address,
                    "status": "active",
                    "role": "vip",
                    "dns_name": f"{slugify(vip['name'])}.rfc1918.host",
                    "description": f"{vip['name']} listeners: {listener_text}",
                },
            )
        )


def apply_inventory(client: NetBoxClient, payloads: list[tuple[Path, dict[str, Any]]]) -> None:
    networks = build_networks(payloads)
    sites: dict[str, dict[str, Any]] = {}
    vlan_groups: dict[str, dict[str, Any]] = {}

    for _, payload in payloads:
        for site in payload.get("datacenters", []) or []:
            sites[site["slug"]] = ensure_site(client, site)

    for _, payload in payloads:
        apply_prefixes(client, payload.get("prefixes", []) or [], sites, vlan_groups)
    for _, payload in payloads:
        apply_devices(client, payload.get("devices", []) or [], sites, networks)
    for _, payload in payloads:
        apply_clusters(client, payload.get("clusters", []) or [], sites)
    for _, payload in payloads:
        apply_service_vips(client, payload.get("service_vips", []) or [], networks)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", help="YAML intake file or directory paths")
    parser.add_argument("--api-url", default=os.getenv("NETBOX_API_URL", "http://172.16.99.62"))
    parser.add_argument("--token", default=os.getenv("NETBOX_TOKEN", ""))
    parser.add_argument("--token-file", default=os.getenv("NETBOX_TOKEN_FILE", ""))
    parser.add_argument("--auth-scheme", choices=("auto", "Token", "Bearer"), default="auto")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Perform NetBox API writes. Default is offline dry-run.",
    )
    parser.add_argument("--update-existing", action="store_true")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    paths = intake_paths(args.paths)
    validation = validate_files(paths)
    if not validation.ok:
        for validation_error in validation.errors:
            print(f"ERROR: {validation_error}", file=sys.stderr)
        return 1

    token = args.token
    if not token and args.token_file:
        token = Path(args.token_file).read_text(encoding="utf-8").strip()
    if args.apply and not token:
        print("NETBOX_TOKEN, --token, or --token-file is required with --apply", file=sys.stderr)
        return 2

    client = NetBoxClient(
        api_url=args.api_url,
        token=token,
        auth_scheme=args.auth_scheme,
        dry_run=not args.apply,
        update_existing=args.update_existing,
    )
    apply_inventory(client, load_intake_files(paths))
    payload = {
        "dry_run": client.dry_run,
        "planned": client.planned,
        "created": client.created,
        "updated": client.updated,
        "existing": client.existing,
    }
    if args.format == "json":
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(f"dry_run={str(client.dry_run).lower()}")
        for key in ("planned", "created", "updated", "existing"):
            print(f"{key}={len(payload[key])}")
            for label in payload[key]:
                print(f"  {label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
