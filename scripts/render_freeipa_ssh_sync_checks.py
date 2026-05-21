#!/usr/bin/env python3
"""Render non-secret FreeIPA SSH sync validation checks from identity source data."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from render_identity_sync_plan import render_identity_sync_plan  # noqa: E402
from validate_identity_source import (  # noqa: E402
    load_identity_source,
    validate_identity_source,
)


def user_controller_checks(
    user: dict[str, Any], hosts: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = [
        {
            "name": f"ipa user-show {user['name']}",
            "kind": "freeipa-user",
            "argv": ["ipa", "user-show", user["name"], "--all"],
        },
        {
            "name": f"ipa group-show {user['primary_group']}",
            "kind": "freeipa-primary-group",
            "argv": ["ipa", "group-show", user["primary_group"], "--all"],
        },
    ]
    for group in user.get("groups", []) or []:
        checks.append(
            {
                "name": f"ipa group-show {group}",
                "kind": "freeipa-supplemental-group",
                "argv": ["ipa", "group-show", group, "--all"],
            }
        )
    for host in hosts:
        checks.append(
            {
                "name": f"ipa hbactest {user['name']} sshd on {host['fqdn']}",
                "kind": "freeipa-hbac-ssh",
                "argv": [
                    "ipa",
                    "hbactest",
                    "--user",
                    user["name"],
                    "--host",
                    host["fqdn"],
                    "--service",
                    "sshd",
                ],
            }
        )
    return checks


def host_controller_checks(host: dict[str, Any]) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = [
        {
            "name": f"ipa host-show {host['fqdn']}",
            "kind": "freeipa-host",
            "argv": ["ipa", "host-show", host["fqdn"], "--all"],
        }
    ]
    for hostgroup in host.get("hostgroups", []) or []:
        checks.append(
            {
                "name": f"ipa hostgroup-show {hostgroup}",
                "kind": "freeipa-hostgroup",
                "argv": ["ipa", "hostgroup-show", hostgroup, "--all"],
            }
        )
    return checks


def client_checks(user: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "name": f"getent passwd {user['name']}",
            "kind": "client-nss-user",
            "argv": ["getent", "passwd", user["name"]],
        },
        {
            "name": f"sss_ssh_authorizedkeys {user['name']}",
            "kind": "client-ssh-authorizedkeys",
            "argv": ["sss_ssh_authorizedkeys", user["name"]],
        },
        {
            "name": f"sudo -l -U {user['name']}",
            "kind": "client-sudo-policy",
            "argv": ["sudo", "-l", "-U", user["name"]],
        },
    ]


def render_freeipa_ssh_sync_checks(source: dict[str, Any]) -> dict[str, Any]:
    plan = render_identity_sync_plan(source)
    users = plan["freeipa_users"]
    hosts = plan["freeipa_host_enrollments"]

    freeipa_controller_checks: list[dict[str, Any]] = []
    for user in users:
        freeipa_controller_checks.extend(user_controller_checks(user, hosts))
    for host in hosts:
        freeipa_controller_checks.extend(host_controller_checks(host))

    linux_client_checks = [
        {
            "user": user["name"],
            "commands": client_checks(user),
        }
        for user in users
    ]

    return {
        "realm": plan["realm"],
        "domain": plan["domain"],
        "requires_vars": sorted(
            {var_name for user in users for var_name in user.get("ssh_public_key_vars", []) or []}
        ),
        "users": [
            {
                "name": user["name"],
                "primary_group": user["primary_group"],
                "groups": user.get("groups", []) or [],
                "ssh_public_key_vars": user.get("ssh_public_key_vars", []) or [],
            }
            for user in users
        ],
        "hosts": [
            {
                "name": host["name"],
                "fqdn": host["fqdn"],
                "hostgroups": host.get("hostgroups", []) or [],
                "status": host.get("status", ""),
            }
            for host in hosts
        ],
        "freeipa_controller_checks": freeipa_controller_checks,
        "linux_client_checks": linux_client_checks,
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
    print(json.dumps(render_freeipa_ssh_sync_checks(source), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
