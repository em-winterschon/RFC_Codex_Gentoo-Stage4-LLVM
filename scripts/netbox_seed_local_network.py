#!/usr/bin/env python3
"""Seed NetBox with the repo's local network fabric baseline.

The script is intentionally conservative: it creates missing objects and leaves
existing NetBox records in place unless --update-existing is passed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib import error, parse, request

DEFAULT_FABRIC = (
    "gentoo_stage4_llvm_split-usr_no-multilib_hardened/"
    "gentoo-liveiso-ansible/inventories/local-network/group_vars/all/network_fabric.yml"
)


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


def status_for_prefix(value: str) -> str:
    return "active" if value.startswith("active") else "reserved"


def status_for_device(value: str | None) -> str:
    if not value:
        return "active"
    if value in {"running", "active", "active-transition", "active-local", "active-chr-backed"}:
        return "active"
    if "retired" in value or "stopped" in value:
        return "offline"
    if value == "planned":
        return "planned"
    return "active"


def model_manufacturer(device: dict[str, Any]) -> tuple[str, str]:
    model = str(device.get("model") or device.get("runtime") or device.get("role") or "Generic")
    lower = model.lower()
    if any(token in lower for token in ("css", "crs", "ccr", "routeros", "mikrotik")):
        return model, "MikroTik"
    if "proxmox" in lower:
        return model, "Proxmox"
    if "gentoo" in lower:
        return model, "Gentoo"
    return model, "Generic"


@dataclass
class NetBoxObject:
    endpoint: str
    lookup_key: str
    lookup_value: str
    payload: dict[str, Any]


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

    def authorization_header(self) -> str:
        if self.auth_scheme == "auto":
            scheme = "Bearer" if self.token.startswith("nbt_") else "Token"
        else:
            scheme = self.auth_scheme
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

    def ensure(self, obj: NetBoxObject) -> dict[str, Any]:
        label = f"{obj.endpoint}:{obj.lookup_value}"
        existing = self.first(obj.endpoint, obj.lookup_key, obj.lookup_value)
        if existing:
            self.existing.append(label)
            if self.update_existing:
                if self.dry_run:
                    print(f"update {label}")
                    return existing
                updated = self.request_json(
                    "PATCH", f"{obj.endpoint}/{existing['id']}", obj.payload
                )
                self.updated.append(label)
                return updated
            return existing

        if self.dry_run:
            print(f"create {label}")
            return {"id": 0, **obj.payload}
        created = self.request_json("POST", obj.endpoint, obj.payload)
        self.created.append(label)
        return created


def load_fabric(path: Path) -> dict[str, Any]:
    yaml = require_yaml()
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise SystemExit(f"Invalid fabric YAML: {path}")
    return payload


def prefix_length(prefix: str) -> str:
    return prefix.split("/", 1)[1] if "/" in prefix else "24"


def with_prefix(ip_address: str, default_prefix: str) -> str:
    if "/" in ip_address:
        return ip_address
    return f"{ip_address}/{prefix_length(default_prefix)}"


def seed_netbox(client: NetBoxClient, fabric: dict[str, Any], domain: str) -> None:
    site_name = str(fabric.get("network_fabric_site", "local-rfc1918-lab"))
    site = client.ensure(
        NetBoxObject(
            "dcim/sites",
            "slug",
            slugify(site_name),
            {"name": site_name, "slug": slugify(site_name), "status": "active"},
        )
    )

    vlan_group = client.ensure(
        NetBoxObject(
            "ipam/vlan-groups",
            "slug",
            slugify(site_name),
            {
                "name": site_name,
                "slug": slugify(site_name),
                "scope_type": "dcim.site",
                "scope_id": site["id"],
            },
        )
    )

    vlan_by_prefix: dict[str, dict[str, Any]] = {}
    for vlan in fabric.get("network_fabric_vlan_plan", []):
        prefix = str(vlan.get("prefix", ""))
        if not prefix or prefix in {"TBD", "operator-assigned"}:
            continue
        created_vlan = client.ensure(
            NetBoxObject(
                "ipam/vlans",
                "vid",
                str(vlan["vlan_id"]),
                {
                    "group": vlan_group["id"],
                    "vid": int(vlan["vlan_id"]),
                    "name": str(vlan["name"]),
                    "status": status_for_prefix(str(vlan.get("status", "reserved"))),
                    "description": f"Seeded from network_fabric_vlan_plan:{vlan['name']}",
                },
            )
        )
        vlan_by_prefix[prefix] = created_vlan
        client.ensure(
            NetBoxObject(
                "ipam/prefixes",
                "prefix",
                prefix,
                {
                    "prefix": prefix,
                    "status": status_for_prefix(str(vlan.get("status", "reserved"))),
                    "site": site["id"],
                    "vlan": created_vlan["id"],
                    "description": f"{vlan['name']} ({vlan.get('status', 'unknown')})",
                },
            )
        )

    management_prefix = str(fabric.get("network_fabric_management_prefix", "172.16.99.0/24"))
    client.ensure(
        NetBoxObject(
            "ipam/prefixes",
            "prefix",
            management_prefix,
            {
                "prefix": management_prefix,
                "status": "active",
                "site": site["id"],
                "description": "Management prefix seeded from network_fabric_management_prefix",
            },
        )
    )

    role_cache: dict[str, dict[str, Any]] = {}
    dtype_cache: dict[str, dict[str, Any]] = {}
    manufacturer_cache: dict[str, dict[str, Any]] = {}

    for name, device in sorted((fabric.get("network_fabric_devices") or {}).items()):
        if not isinstance(device, dict):
            continue
        role_name = str(device.get("role", "infrastructure"))
        role_slug = slugify(role_name)
        role = role_cache.get(role_slug)
        if role is None:
            role = client.ensure(
                NetBoxObject(
                    "dcim/device-roles",
                    "slug",
                    role_slug,
                    {"name": role_name, "slug": role_slug, "color": "607d8b"},
                )
            )
            role_cache[role_slug] = role

        model, manufacturer_name = model_manufacturer(device)
        manufacturer_slug = slugify(manufacturer_name)
        manufacturer = manufacturer_cache.get(manufacturer_slug)
        if manufacturer is None:
            manufacturer = client.ensure(
                NetBoxObject(
                    "dcim/manufacturers",
                    "slug",
                    manufacturer_slug,
                    {"name": manufacturer_name, "slug": manufacturer_slug},
                )
            )
            manufacturer_cache[manufacturer_slug] = manufacturer

        dtype_slug = slugify(model)
        dtype = dtype_cache.get(dtype_slug)
        if dtype is None:
            dtype = client.ensure(
                NetBoxObject(
                    "dcim/device-types",
                    "slug",
                    dtype_slug,
                    {"manufacturer": manufacturer["id"], "model": model, "slug": dtype_slug},
                )
            )
            dtype_cache[dtype_slug] = dtype

        client.ensure(
            NetBoxObject(
                "dcim/devices",
                "name",
                name,
                {
                    "name": name,
                    "site": site["id"],
                    "role": role["id"],
                    "device_type": dtype["id"],
                    "status": status_for_device(str(device.get("status", "active"))),
                    "comments": "\n".join(str(item) for item in device.get("notes", [])),
                },
            )
        )

        management_ip = device.get("management_ip")
        if management_ip:
            address = with_prefix(str(management_ip), management_prefix)
            client.ensure(
                NetBoxObject(
                    "ipam/ip-addresses",
                    "address",
                    address,
                    {
                        "address": address,
                        "status": "active",
                        "dns_name": f"{slugify(name)}.{domain}",
                        "description": f"Management IP for {name}",
                    },
                )
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", default=os.getenv("NETBOX_API_URL", "http://172.16.99.62"))
    parser.add_argument("--token", default=os.getenv("NETBOX_TOKEN", ""))
    parser.add_argument("--token-file", default=os.getenv("NETBOX_TOKEN_FILE", ""))
    parser.add_argument("--auth-scheme", choices=("auto", "Token", "Bearer"), default="auto")
    parser.add_argument("--fabric", default=DEFAULT_FABRIC)
    parser.add_argument("--domain", default="rfc1918.host")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--update-existing", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    token = args.token
    if not token and args.token_file:
        token = Path(args.token_file).read_text(encoding="utf-8").strip()
    if not token:
        print("NETBOX_TOKEN or --token-file is required", file=sys.stderr)
        return 2

    fabric = load_fabric(Path(args.fabric))
    client = NetBoxClient(
        api_url=args.api_url,
        token=token,
        auth_scheme=args.auth_scheme,
        dry_run=args.dry_run,
        update_existing=args.update_existing,
    )
    seed_netbox(client, fabric, args.domain)
    print(
        json.dumps(
            {
                "created": len(client.created),
                "updated": len(client.updated),
                "existing": len(client.existing),
                "dry_run": args.dry_run,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
