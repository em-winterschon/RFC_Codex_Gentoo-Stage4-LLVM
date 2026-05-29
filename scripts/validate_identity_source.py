#!/usr/bin/env python3
"""Validate repo-safe identity and AAA source-of-truth definitions."""

from __future__ import annotations

import argparse
import ipaddress
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


class IdentitySourceValidationError(Exception):
    """Raised when identity source files contain schema or reference errors."""


@dataclass
class ValidationResult:
    files: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    counts: dict[str, int] = field(
        default_factory=lambda: {
            "groups": 0,
            "users": 0,
            "service_accounts": 0,
            "host_enrollments": 0,
            "radius_clients": 0,
            "rollout_gates": 0,
        }
    )

    @property
    def ok(self) -> bool:
        return not self.errors


def require_yaml() -> Any:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - depends on local environment
        raise SystemExit("PyYAML is required. Install python yaml support first.") from exc
    return yaml


def load_identity_source(path: Path) -> dict[str, Any]:
    yaml = require_yaml()
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise IdentitySourceValidationError(f"{path}: top-level document must be a mapping")
    source = payload.get("identity_source_definition")
    if not isinstance(source, dict):
        raise IdentitySourceValidationError(f"{path}: missing identity_source_definition mapping")
    return source


def required_string(row: dict[str, Any], key: str, label: str, result: ValidationResult) -> str:
    value = row.get(key)
    if not isinstance(value, str) or not value.strip():
        result.errors.append(f"{label}: missing required string field {key}")
        return ""
    return value.strip()


def validate_uid_gid(value: Any, key: str, label: str, result: ValidationResult) -> int | None:
    if not isinstance(value, int) or value < 1:
        result.errors.append(f"{label}: {key} must be a positive integer")
        return None
    return value


def validate_freeipa_local_idrange(
    idrange: Any, label: str, result: ValidationResult
) -> tuple[str, int, int] | None:
    if not isinstance(idrange, dict):
        result.errors.append(f"{label} must be a mapping")
        return None

    name = required_string(idrange, "name", label, result)
    parsed: dict[str, int] = {}
    for key in ("base_id", "range_size", "rid_base", "secondary_rid_base"):
        value = validate_uid_gid(idrange.get(key), key, label, result)
        if value is not None:
            parsed[key] = value
    idrange_type = idrange.get("type", "ipa-local")
    if idrange_type != "ipa-local":
        result.errors.append(f"{label}.type must be ipa-local")
    if name and "base_id" in parsed and "range_size" in parsed:
        return (name, parsed["base_id"], parsed["base_id"] + parsed["range_size"])
    return None


def collect_freeipa_local_idranges(
    uid_gid_policy: dict[str, Any], result: ValidationResult
) -> list[tuple[str, int, int]]:
    ranges: list[tuple[str, int, int]] = []
    freeipa_local_idrange = uid_gid_policy.get("freeipa_local_idrange", {}) or {}
    if freeipa_local_idrange:
        parsed = validate_freeipa_local_idrange(
            freeipa_local_idrange,
            "uid_gid_policy.freeipa_local_idrange",
            result,
        )
        if parsed is not None:
            ranges.append(parsed)

    additional = uid_gid_policy.get("additional_freeipa_local_idranges", []) or []
    if not isinstance(additional, list):
        result.errors.append("uid_gid_policy.additional_freeipa_local_idranges must be a list")
        return ranges

    seen_names = {name for name, _, _ in ranges}
    for index, idrange in enumerate(additional):
        label = f"uid_gid_policy.additional_freeipa_local_idranges[{index}]"
        parsed = validate_freeipa_local_idrange(idrange, label, result)
        if parsed is None:
            continue
        name, base_id, limit = parsed
        if name in seen_names:
            result.errors.append(f"{label}: duplicate FreeIPA local ID range {name}")
        seen_names.add(name)
        for other_name, other_base, other_limit in ranges:
            if base_id < other_limit and other_base < limit:
                result.errors.append(
                    f"{label}: overlaps FreeIPA local ID range {other_name} "
                    f"({other_base}-{other_limit - 1})"
                )
        ranges.append(parsed)
    return ranges


def validate_id_in_freeipa_ranges(
    value: int,
    key: str,
    label: str,
    idranges: list[tuple[str, int, int]],
    result: ValidationResult,
) -> None:
    if not idranges:
        return
    if any(base <= value < limit for _, base, limit in idranges):
        return
    formatted = ", ".join(f"{name}:{base}-{limit - 1}" for name, base, limit in idranges)
    result.errors.append(
        f"{label}: {key} {value} is outside configured FreeIPA local ID ranges " f"({formatted})"
    )


def reject_secret_values(row: dict[str, Any], label: str, result: ValidationResult) -> None:
    forbidden = {
        "password",
        "password_hash",
        "shared_secret",
        "secret",
        "bind_password",
        "token",
        "api_token",
    }
    for key in sorted(forbidden):
        if key in row:
            result.errors.append(f"{label}: plaintext secret field {key} is not allowed")


def validate_group_refs(
    refs: list[Any], known_groups: set[str], key: str, label: str, result: ValidationResult
) -> None:
    for index, group in enumerate(refs):
        if not isinstance(group, str) or not group.strip():
            result.errors.append(f"{label}: {key}[{index}] must be a non-empty string")
            continue
        if group not in known_groups:
            result.errors.append(f"{label}: unknown {key} group {group}")


def validate_string_list(value: Any, key: str, label: str, result: ValidationResult) -> None:
    if not isinstance(value, list):
        result.errors.append(f"{label}: {key} must be a list")
        return
    for index, item in enumerate(value):
        if not isinstance(item, str) or not item.strip():
            result.errors.append(f"{label}: {key}[{index}] must be a non-empty string")


def validate_floating_home(account: dict[str, Any], label: str, result: ValidationResult) -> None:
    home_directory = account.get("home_directory")
    if home_directory is not None:
        if not isinstance(home_directory, str) or not home_directory.startswith("/"):
            result.errors.append(f"{label}: home_directory must be an absolute path string")

    floating_home = account.get("floating_home")
    if floating_home is None:
        return
    if not isinstance(floating_home, dict):
        result.errors.append(f"{label}: floating_home must be a mapping")
        return
    reject_secret_values(floating_home, f"{label}.floating_home", result)
    for key in ("provider", "site", "server", "export_path", "mount_path", "protocol", "status"):
        required_string(floating_home, key, f"{label}.floating_home", result)
    server_ip = floating_home.get("server_ip")
    if not isinstance(server_ip, str) or not server_ip.strip():
        result.errors.append(f"{label}.floating_home: missing required string field server_ip")
    else:
        try:
            ipaddress.ip_address(server_ip)
        except ValueError:
            result.errors.append(f"{label}.floating_home: invalid server_ip {server_ip}")
    for path_key in ("export_path", "mount_path"):
        value = floating_home.get(path_key)
        if isinstance(value, str) and value and not value.startswith("/"):
            result.errors.append(f"{label}.floating_home: {path_key} must be an absolute path")
    if isinstance(home_directory, str) and isinstance(floating_home.get("mount_path"), str):
        if floating_home["mount_path"] != home_directory:
            result.errors.append(f"{label}.floating_home: mount_path must match home_directory")
    if "nfs_options" in floating_home:
        validate_string_list(
            floating_home["nfs_options"], "nfs_options", f"{label}.floating_home", result
        )


def validate_identity_source(source: dict[str, Any], path: Path | None = None) -> ValidationResult:
    result = ValidationResult()
    if path is not None:
        result.files.append(str(path))

    if source.get("version") != 1:
        result.errors.append("identity_source_definition.version must be 1")
    required_string(source, "realm", "identity_source_definition", result)
    required_string(source, "domain", "identity_source_definition", result)
    uid_gid_policy = source.get("uid_gid_policy", {}) or {}
    if not isinstance(uid_gid_policy, dict):
        result.errors.append("identity_source_definition.uid_gid_policy must be a mapping")
        uid_gid_policy = {}
    idranges = collect_freeipa_local_idranges(uid_gid_policy, result)

    groups = source.get("groups", []) or []
    users = source.get("users", []) or []
    service_accounts = source.get("service_accounts", []) or []
    host_enrollments = source.get("host_enrollments", []) or []
    radius_clients = source.get("radius_clients", []) or []
    rollout_gates = source.get("rollout_gates", []) or []

    known_groups: set[str] = set()
    seen_gids: dict[int, str] = {}
    for index, group in enumerate(groups):
        label = f"groups[{index}]"
        if not isinstance(group, dict):
            result.errors.append(f"{label}: group must be a mapping")
            continue
        name = required_string(group, "name", label, result)
        gid = validate_uid_gid(group.get("gid"), "gid", label, result)
        reject_secret_values(group, label, result)
        if name:
            if name in known_groups:
                result.errors.append(f"{label}: duplicate group {name}")
            known_groups.add(name)
            if gid is not None:
                if gid in seen_gids:
                    result.errors.append(
                        f"{label}: duplicate gid {gid} also used by {seen_gids[gid]}"
                    )
                seen_gids[gid] = name or label
                validate_id_in_freeipa_ranges(gid, "gid", label, idranges, result)

    seen_users: set[str] = set()
    seen_uids: dict[int, str] = {}
    for collection_name, collection in (
        ("users", users),
        ("service_accounts", service_accounts),
    ):
        for index, account in enumerate(collection):
            label = f"{collection_name}[{index}]"
            if not isinstance(account, dict):
                result.errors.append(f"{label}: account must be a mapping")
                continue
            name = required_string(account, "name", label, result)
            uid = validate_uid_gid(account.get("uid"), "uid", label, result)
            primary_group = required_string(account, "primary_group", label, result)
            reject_secret_values(account, label, result)
            if name:
                if name in seen_users:
                    result.errors.append(f"{label}: duplicate account {name}")
                seen_users.add(name)
            if uid is not None:
                if uid in seen_uids:
                    result.errors.append(
                        f"{label}: duplicate uid {uid} also used by {seen_uids[uid]}"
                    )
                seen_uids[uid] = name or label
                validate_id_in_freeipa_ranges(uid, "uid", label, idranges, result)
            if primary_group and primary_group not in known_groups:
                result.errors.append(f"{label}: unknown primary_group {primary_group}")
            validate_group_refs(
                account.get("groups", []) or [], known_groups, "groups", label, result
            )
            validate_floating_home(account, label, result)
            for var_key in ("password_var", "bind_password_var"):
                if var_key in account and (
                    not isinstance(account[var_key], str)
                    or not account[var_key].startswith("vault_")
                ):
                    result.errors.append(f"{label}: {var_key} must reference a vault_* variable")

    for index, host in enumerate(host_enrollments):
        label = f"host_enrollments[{index}]"
        if not isinstance(host, dict):
            result.errors.append(f"{label}: host enrollment must be a mapping")
            continue
        required_string(host, "name", label, result)
        required_string(host, "fqdn", label, result)
        required_string(host, "netbox_device", label, result)
        validate_group_refs(
            host.get("hostgroups", []) or [],
            known_groups
            | {
                "linux-workstations",
                "linux-servers",
                "aaa-first-linux-client",
                "automation-admin",
            },
            "hostgroups",
            label,
            result,
        )
        if "enrollment_secret_var" in host and (
            not isinstance(host["enrollment_secret_var"], str)
            or not host["enrollment_secret_var"].startswith("vault_")
        ):
            result.errors.append(
                f"{label}: enrollment_secret_var must reference a vault_* variable"
            )
        reject_secret_values(host, label, result)

    for index, client in enumerate(radius_clients):
        label = f"radius_clients[{index}]"
        if not isinstance(client, dict):
            result.errors.append(f"{label}: RADIUS client must be a mapping")
            continue
        required_string(client, "name", label, result)
        required_string(client, "netbox_device", label, result)
        ipaddr = required_string(client, "ipaddr", label, result)
        if ipaddr:
            try:
                ipaddress.ip_address(ipaddr)
            except ValueError:
                result.errors.append(f"{label}: invalid ipaddr {ipaddr}")
        if "shared_secret" in client:
            result.errors.append(
                f"{label}: RADIUS clients must use shared_secret_var, not shared_secret"
            )
        secret_var = client.get("shared_secret_var")
        if not isinstance(secret_var, str) or not secret_var.startswith("vault_"):
            result.errors.append(f"{label}: shared_secret_var must reference a vault_* variable")
        for role_key in ("access_role", "readonly_role"):
            role = client.get(role_key)
            if role is not None and role not in known_groups:
                result.errors.append(f"{label}: unknown {role_key} group {role}")
        reject_secret_values(
            {k: v for k, v in client.items() if k != "shared_secret"}, label, result
        )

    result.counts.update(
        {
            "groups": len(groups),
            "users": len(users),
            "service_accounts": len(service_accounts),
            "host_enrollments": len(host_enrollments),
            "radius_clients": len(radius_clients),
            "rollout_gates": len(rollout_gates),
        }
    )
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        source = load_identity_source(args.path)
        result = validate_identity_source(source, args.path)
    except IdentitySourceValidationError as exc:
        result = ValidationResult(files=[str(args.path)], errors=[str(exc)])

    payload = {
        "ok": result.ok,
        "files": result.files,
        "errors": result.errors,
        "warnings": result.warnings,
        "counts": result.counts,
    }
    if args.format == "json":
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for error in result.errors:
            print(f"ERROR: {error}", file=sys.stderr)
        for warning in result.warnings:
            print(f"WARNING: {warning}", file=sys.stderr)
        if result.ok:
            print("PASS: identity source validation")
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
