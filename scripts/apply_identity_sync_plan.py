#!/usr/bin/env python3
"""Apply identity sync-plan operations through explicit mutation gates.

The command is dry-run by default. Live mutation requires --apply plus
IDENTITY_SYNC_APPLY=1 and the provider-specific gate for every selected
provider. Secret values are resolved only at apply time and are never printed
to stdout or the audit log.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from render_identity_sync_plan import render_identity_sync_plan  # noqa: E402
from validate_identity_source import (  # noqa: E402
    load_identity_source,
    validate_identity_source,
)


class IdentityApplyError(Exception):
    """Raised when gated identity apply cannot proceed safely."""


SENSITIVE_ARG_PREFIXES = (
    "--sshpubkey=",
    "--setattr=userPassword=",
    "--password=",
    "--secret=",
)


def selected_providers(provider: str) -> list[str]:
    return ["freeipa", "freeradius"] if provider == "all" else [provider]


def gate_enabled(name: str) -> bool:
    return os.environ.get(name) == "1"


def require_apply_gates(provider: str) -> None:
    if not gate_enabled("IDENTITY_SYNC_APPLY"):
        raise IdentityApplyError("IDENTITY_SYNC_APPLY=1 is required for live --apply mode")
    if "freeipa" in selected_providers(provider) and not gate_enabled(
        "IDENTITY_SYNC_APPLY_FREEIPA"
    ):
        raise IdentityApplyError("IDENTITY_SYNC_APPLY_FREEIPA=1 is required for FreeIPA apply")
    if "freeradius" in selected_providers(provider) and not gate_enabled(
        "IDENTITY_SYNC_APPLY_FREERADIUS"
    ):
        raise IdentityApplyError(
            "IDENTITY_SYNC_APPLY_FREERADIUS=1 is required for FreeRADIUS apply"
        )


def resolve_env_var(name: str, *, required: bool) -> str:
    candidates = [name, name.upper()]
    for candidate in candidates:
        value = os.environ.get(candidate)
        if value is not None:
            return value
    if required:
        raise IdentityApplyError(f"required vault/environment variable is not set: {name}")
    return ""


def resolve_list_var(name: str, *, required: bool) -> list[str]:
    value = resolve_env_var(name, required=required)
    if not value:
        return []
    stripped = value.strip()
    if stripped.startswith("["):
        try:
            parsed = json.loads(stripped)
        except json.JSONDecodeError as exc:
            raise IdentityApplyError(
                f"{name}: expected JSON list or newline-separated values"
            ) from exc
        if not isinstance(parsed, list) or not all(isinstance(item, str) for item in parsed):
            raise IdentityApplyError(f"{name}: expected JSON list of strings")
        return [item.strip() for item in parsed if item.strip()]
    return [line.strip() for line in value.splitlines() if line.strip()]


def redacted_argv(argv: list[str]) -> list[str]:
    redacted: list[str] = []
    for arg in argv:
        if any(arg.startswith(prefix) for prefix in SENSITIVE_ARG_PREFIXES):
            key = arg.split("=", 1)[0]
            redacted.append(f"{key}=<redacted>")
        else:
            redacted.append(arg)
    return redacted


def audit_event(audit_log: Path | None, event: dict[str, Any]) -> None:
    if audit_log is None:
        return
    audit_log.parent.mkdir(parents=True, exist_ok=True)
    with audit_log.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, sort_keys=True) + "\n")


def run_command(
    argv: list[str],
    *,
    audit_log: Path | None,
    check: bool = True,
    allow_already_member: bool = False,
    allow_no_modifications: bool = False,
) -> subprocess.CompletedProcess[str]:
    audit_event(audit_log, {"event": "run_command", "argv": redacted_argv(argv)})
    result = subprocess.run(argv, check=False, capture_output=True, text=True)
    if check and result.returncode != 0:
        combined = f"{result.stdout}\n{result.stderr}"
        if allow_already_member and "already a member" in combined:
            return result
        if allow_no_modifications and "no modifications to be performed" in combined:
            return result
        raise IdentityApplyError(
            "command failed: " + " ".join(redacted_argv(argv)) + f" (rc={result.returncode})"
        )
    return result


def ipa_exists(ipa_command: str, kind: str, name: str, audit_log: Path | None) -> bool:
    result = run_command(
        [ipa_command, f"{kind}-show", name],
        audit_log=audit_log,
        check=False,
    )
    return result.returncode == 0


def build_required_vars(plan: dict[str, Any], providers: list[str]) -> list[str]:
    required: set[str] = set()
    if "freeipa" in providers:
        for user in plan["freeipa_users"]:
            required.update(user.get("ssh_public_key_vars", []) or [])
        for host in plan["freeipa_host_enrollments"]:
            var_name = host.get("enrollment_secret_var")
            if var_name:
                required.add(var_name)
    if "freeradius" in providers:
        for client in plan["freeradius_clients"]:
            required.add(client["shared_secret_var"])
    return sorted(required)


def build_summary(
    plan: dict[str, Any],
    *,
    apply: bool,
    provider: str,
    freeradius_output: Path,
    audit_log: Path | None,
) -> dict[str, Any]:
    providers = selected_providers(provider)
    return {
        "applied": False,
        "dry_run": not apply,
        "provider": provider,
        "selected_providers": providers,
        "realm": plan["realm"],
        "domain": plan["domain"],
        "requires_vars": build_required_vars(plan, providers),
        "freeipa": {
            "local_idrange": plan.get("freeipa_local_idrange", {}) or {},
            "groups": len(plan["freeipa_groups"]),
            "users": len(plan["freeipa_users"]),
            "service_accounts": len(plan["freeipa_service_accounts"]),
            "host_enrollments": len(plan["freeipa_host_enrollments"]),
            "manual_actions": [
                {
                    "kind": "ldap_sysaccount",
                    "name": account["name"],
                    "reason": (
                        "sysaccount bind DN creation remains LDAP-specific "
                        "and is not mutated by the IPA CLI path"
                    ),
                }
                for account in plan["freeipa_service_accounts"]
            ],
        },
        "freeradius": {
            "clients": len(plan["freeradius_clients"]),
            "output": str(freeradius_output),
            "rendered": False,
        },
        "audit_log": str(audit_log) if audit_log else "",
    }


def parse_ipa_raw_attrs(output: str) -> dict[str, str]:
    attrs: dict[str, str] = {}
    for line in output.splitlines():
        stripped = line.strip()
        if ": " not in stripped:
            continue
        key, value = stripped.split(": ", 1)
        attrs[key.lower()] = value.strip()
    return attrs


def require_ids_within_local_idrange(plan: dict[str, Any]) -> None:
    idrange = plan.get("freeipa_local_idrange", {}) or {}
    if not idrange:
        raise IdentityApplyError("freeipa_local_idrange is required before FreeIPA UID/GID apply")

    base_id = int(idrange["base_id"])
    limit = base_id + int(idrange["range_size"])
    targets: list[tuple[str, str, int]] = []
    targets.extend(("group", group["name"], int(group["gid"])) for group in plan["freeipa_groups"])
    targets.extend(("user", user["name"], int(user["uid"])) for user in plan["freeipa_users"])
    targets.extend(
        ("service_account", account["name"], int(account["uid"]))
        for account in plan["freeipa_service_accounts"]
    )
    for kind, name, value in targets:
        if not base_id <= value < limit:
            raise IdentityApplyError(
                f"{kind} {name} ID {value} is outside FreeIPA local ID range "
                f"{base_id}-{limit - 1}"
            )


def ensure_freeipa_local_idrange(
    plan: dict[str, Any], *, ipa_command: str, audit_log: Path | None
) -> int:
    idrange = plan.get("freeipa_local_idrange", {}) or {}
    if not idrange:
        return 0

    name = idrange["name"]
    expected = {
        "ipabaseid": str(idrange["base_id"]),
        "ipaidrangesize": str(idrange["range_size"]),
        "ipabaserid": str(idrange["rid_base"]),
        "ipasecondarybaserid": str(idrange["secondary_rid_base"]),
        "iparangetype": idrange.get("type", "ipa-local"),
    }

    result = run_command(
        [ipa_command, "idrange-show", name, "--all", "--raw"],
        audit_log=audit_log,
        check=False,
    )
    if result.returncode != 0:
        run_command(
            [
                ipa_command,
                "idrange-add",
                name,
                f"--base-id={idrange['base_id']}",
                f"--range-size={idrange['range_size']}",
                f"--rid-base={idrange['rid_base']}",
                f"--secondary-rid-base={idrange['secondary_rid_base']}",
                f"--type={idrange.get('type', 'ipa-local')}",
            ],
            audit_log=audit_log,
        )
        return 1

    attrs = parse_ipa_raw_attrs(result.stdout)
    mismatches = [
        f"{key}: expected {value}, found {attrs.get(key, '<missing>')}"
        for key, value in expected.items()
        if attrs.get(key) != value
    ]
    if mismatches:
        raise IdentityApplyError(
            f"FreeIPA local ID range {name} exists with incompatible settings: "
            + "; ".join(mismatches)
        )
    return 0


def apply_freeipa(plan: dict[str, Any], *, ipa_command: str, audit_log: Path | None) -> int:
    require_ids_within_local_idrange(plan)
    commands = ensure_freeipa_local_idrange(plan, ipa_command=ipa_command, audit_log=audit_log)
    group_gids = {group["name"]: str(group["gid"]) for group in plan["freeipa_groups"]}

    for group in plan["freeipa_groups"]:
        if ipa_exists(ipa_command, "group", group["name"], audit_log):
            run_command(
                [
                    ipa_command,
                    "group-mod",
                    group["name"],
                    f"--gid={group['gid']}",
                    f"--desc={group.get('description', '')}",
                ],
                audit_log=audit_log,
                allow_no_modifications=True,
            )
        else:
            run_command(
                [
                    ipa_command,
                    "group-add",
                    group["name"],
                    f"--gid={group['gid']}",
                    f"--desc={group.get('description', '')}",
                ],
                audit_log=audit_log,
            )
        commands += 1

    for user in plan["freeipa_users"]:
        gid = group_gids[user["primary_group"]]
        if ipa_exists(ipa_command, "user", user["name"], audit_log):
            run_command(
                [
                    ipa_command,
                    "user-mod",
                    user["name"],
                    f"--uid={user['uid']}",
                    f"--gidnumber={gid}",
                    f"--shell={user['shell']}",
                ],
                audit_log=audit_log,
                allow_no_modifications=True,
            )
        else:
            run_command(
                [
                    ipa_command,
                    "user-add",
                    user["name"],
                    f"--first={user['name']}",
                    "--last=RFC1918",
                    f"--uid={user['uid']}",
                    f"--gidnumber={gid}",
                    f"--shell={user['shell']}",
                ],
                audit_log=audit_log,
            )
        commands += 1

        ssh_keys: list[str] = []
        for var_name in user.get("ssh_public_key_vars", []) or []:
            ssh_keys.extend(resolve_list_var(var_name, required=True))
        if ssh_keys:
            run_command(
                [ipa_command, "user-mod", user["name"]]
                + [f"--sshpubkey={ssh_key}" for ssh_key in ssh_keys],
                audit_log=audit_log,
                allow_no_modifications=True,
            )
            commands += 1

        for group_name in user.get("groups", []) or []:
            run_command(
                [ipa_command, "group-add-member", group_name, f"--users={user['name']}"],
                audit_log=audit_log,
                allow_already_member=True,
            )
            commands += 1

    for host in plan["freeipa_host_enrollments"]:
        fqdn = host["fqdn"]
        if ipa_exists(ipa_command, "host", fqdn, audit_log):
            run_command(
                [ipa_command, "host-mod", fqdn, f"--desc={host['name']}"],
                audit_log=audit_log,
                allow_no_modifications=True,
            )
        else:
            run_command(
                [ipa_command, "host-add", fqdn, "--force", f"--desc={host['name']}"],
                audit_log=audit_log,
            )
        commands += 1

        for hostgroup in host.get("hostgroups", []) or []:
            if not ipa_exists(ipa_command, "hostgroup", hostgroup, audit_log):
                run_command([ipa_command, "hostgroup-add", hostgroup], audit_log=audit_log)
                commands += 1
            run_command(
                [ipa_command, "hostgroup-add-member", hostgroup, f"--hosts={fqdn}"],
                audit_log=audit_log,
                allow_already_member=True,
            )
            commands += 1

    return commands


def render_freeradius_clients(plan: dict[str, Any]) -> str:
    lines = [
        "# Generated by scripts/apply_identity_sync_plan.py",
        "# Do not edit by hand; update identity-source-definitions instead.",
        "",
    ]
    for client in plan["freeradius_clients"]:
        secret = resolve_env_var(client["shared_secret_var"], required=True)
        lines.extend(
            [
                f"client {client['shortname']} {{",
                f"    ipaddr = {client['ipaddr']}",
                f"    secret = {secret}",
                f"    shortname = {client['shortname']}",
                f"    nastype = {client['nastype']}",
                "}",
                "",
            ]
        )
    return "\n".join(lines)


def apply_freeradius(plan: dict[str, Any], *, output: Path, audit_log: Path | None) -> None:
    content = render_freeradius_clients(plan)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=output.parent, delete=False
    ) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    temp_path.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP)
    temp_path.replace(output)
    audit_event(
        audit_log,
        {
            "event": "write_file",
            "path": str(output),
            "mode": "0640",
            "contains_secret_values": True,
            "secret_values_redacted": True,
        },
    )


def emit_summary(summary: dict[str, Any], output_format: str) -> None:
    if output_format == "json":
        print(json.dumps(summary, indent=2, sort_keys=True))
        return
    print(f"identity sync provider: {summary['provider']}")
    print(f"dry_run: {str(summary['dry_run']).lower()}")
    print(f"applied: {str(summary['applied']).lower()}")
    print(f"requires_vars: {', '.join(summary['requires_vars'])}")


def apply_identity_sync_plan(args: argparse.Namespace) -> dict[str, Any]:
    source = load_identity_source(args.path)
    validation = validate_identity_source(source, args.path)
    if not validation.ok:
        raise IdentityApplyError("; ".join(validation.errors))

    plan = render_identity_sync_plan(source)
    audit_log = args.audit_log
    summary = build_summary(
        plan,
        apply=args.apply,
        provider=args.provider,
        freeradius_output=args.freeradius_output,
        audit_log=audit_log,
    )

    audit_event(audit_log, {"event": "plan", "provider": args.provider, "apply": args.apply})
    if not args.apply:
        return summary

    require_apply_gates(args.provider)
    audit_event(audit_log, {"event": "apply_start", "provider": args.provider})

    if "freeipa" in selected_providers(args.provider):
        summary["freeipa"]["commands_run"] = apply_freeipa(
            plan,
            ipa_command=args.freeipa_command,
            audit_log=audit_log,
        )
    if "freeradius" in selected_providers(args.provider):
        apply_freeradius(plan, output=args.freeradius_output, audit_log=audit_log)
        summary["freeradius"]["rendered"] = True

    summary["applied"] = True
    summary["dry_run"] = False
    audit_event(audit_log, {"event": "apply_complete", "provider": args.provider})
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--apply", action="store_true", help="Perform gated live mutations.")
    parser.add_argument(
        "--provider",
        choices=("all", "freeipa", "freeradius"),
        default="all",
        help="Provider scope to plan or apply.",
    )
    parser.add_argument("--format", choices=("json", "text"), default="json")
    parser.add_argument("--freeipa-command", default="ipa", help="FreeIPA CLI command path.")
    parser.add_argument(
        "--freeradius-output",
        type=Path,
        default=Path("/etc/raddb/clients.d/rfc1918-generated.conf"),
        help="FreeRADIUS generated clients.d output path.",
    )
    parser.add_argument("--audit-log", type=Path, help="Optional redacted JSONL audit log path.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        summary = apply_identity_sync_plan(args)
    except IdentityApplyError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    emit_summary(summary, args.format)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
