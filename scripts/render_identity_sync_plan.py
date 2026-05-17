#!/usr/bin/env python3
"""Render a deterministic FreeIPA/FreeRADIUS sync plan from identity source data."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from validate_identity_source import (  # noqa: E402
    load_identity_source,
    validate_identity_source,
)


def render_identity_sync_plan(source: dict[str, Any]) -> dict[str, Any]:
    users = source.get("users", []) or []
    service_accounts = source.get("service_accounts", []) or []
    groups = source.get("groups", []) or []
    host_enrollments = source.get("host_enrollments", []) or []
    radius_clients = source.get("radius_clients", []) or []
    uid_gid_policy = source.get("uid_gid_policy", {}) or {}

    return {
        "realm": source["realm"],
        "domain": source["domain"],
        "freeipa_local_idrange": uid_gid_policy.get("freeipa_local_idrange", {}) or {},
        "freeipa_groups": [
            {
                "name": group["name"],
                "gid": group["gid"],
                "description": group.get("description", ""),
            }
            for group in groups
        ],
        "freeipa_users": [
            {
                "name": user["name"],
                "uid": user["uid"],
                "primary_group": user["primary_group"],
                "groups": user.get("groups", []) or [],
                "shell": user.get("shell", "/bin/bash"),
                "ssh_public_key_vars": user.get("ssh_public_key_vars", []) or [],
                "password_var": user.get("password_var", ""),
                "description": user.get("description", ""),
            }
            for user in users
        ],
        "freeipa_service_accounts": [
            {
                "name": account["name"],
                "uid": account["uid"],
                "primary_group": account["primary_group"],
                "shell": account.get("shell", "/sbin/nologin"),
                "bind_dn": account.get("bind_dn", ""),
                "bind_password_var": account.get("bind_password_var", ""),
                "description": account.get("description", ""),
            }
            for account in service_accounts
        ],
        "freeipa_host_enrollments": [
            {
                "name": host["name"],
                "fqdn": host["fqdn"],
                "netbox_device": host["netbox_device"],
                "hostgroups": host.get("hostgroups", []) or [],
                "enrollment_secret_var": host.get("enrollment_secret_var", ""),
                "status": host.get("status", "planned"),
            }
            for host in host_enrollments
        ],
        "freeradius_clients": [
            {
                "name": client["name"],
                "shortname": client.get("shortname", client["name"]),
                "ipaddr": client["ipaddr"],
                "netbox_device": client["netbox_device"],
                "device_group": client.get("device_group", ""),
                "access_role": client.get("access_role", ""),
                "readonly_role": client.get("readonly_role", ""),
                "nastype": client.get("nastype", "other"),
                "shared_secret_var": client["shared_secret_var"],
                "break_glass_secret_ref": client.get("break_glass_secret_ref", ""),
                "status": client.get("status", "planned"),
            }
            for client in radius_clients
        ],
        "rollout_gates": source.get("rollout_gates", []) or [],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--format", choices=("json",), default="json")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = load_identity_source(args.path)
    validation = validate_identity_source(source, args.path)
    if not validation.ok:
        for error in validation.errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(json.dumps(render_identity_sync_plan(source), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
