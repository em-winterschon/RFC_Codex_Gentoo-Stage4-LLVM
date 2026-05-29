#!/usr/bin/env python3
"""validate-hasslehoff-backup-policy.py validates Hasslehoff backup policy."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

required_service_classes = {
    "netbox",
    "freeipa",
    "observability",
    "syslog-search",
    "netboot-publisher",
    "container-services",
    "workstation-validation",
}


@dataclass
class ValidationResult:
    policy_id: str = ""
    external_target_id: str = ""
    vm_lxc_services: int = 0
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors

    def as_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "policy_id": self.policy_id,
            "external_target_id": self.external_target_id,
            "vm_lxc_services": self.vm_lxc_services,
            "required_service_classes": sorted(required_service_classes),
            "errors": self.errors,
        }


def load_yaml(path: Path) -> dict[str, Any]:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - environment dependency
        raise SystemExit("PyYAML is required to validate Hasslehoff backup policy.") from exc

    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise SystemExit(f"{path}: top-level policy document must be a mapping")
    return payload


def require_bool_false(value: Any, field_name: str, result: ValidationResult) -> None:
    if value is not False:
        result.errors.append(f"{field_name} must be false")


def validate_restore_validation(
    values: Any,
    required_values: set[str],
    field_name: str,
    result: ValidationResult,
) -> None:
    if not isinstance(values, list):
        result.errors.append(f"{field_name} must be a list")
        return
    observed = {value for value in values if isinstance(value, str)}
    missing = sorted(required_values - observed)
    if missing:
        result.errors.append(f"{field_name} missing required values: {', '.join(missing)}")


def validate_policy(policy: dict[str, Any]) -> ValidationResult:
    result = ValidationResult()
    result.policy_id = str(policy.get("policy_id", ""))
    result.external_target_id = str(policy.get("external_target_id", ""))

    if result.policy_id != "rfc1918.hasslehoff.backup-policy.v1":
        result.errors.append("policy_id must be rfc1918.hasslehoff.backup-policy.v1")
    if result.external_target_id != "nasa-m70-nfs-relay":
        result.errors.append("external_target_id must be nasa-m70-nfs-relay")

    external_target = policy.get("external_target")
    if not isinstance(external_target, dict):
        result.errors.append("external_target must be a mapping")
        external_target = {}
    require_bool_false(external_target.get("x12again_allowed"), "x12again_allowed", result)

    notification = policy.get("notification")
    if not isinstance(notification, dict):
        result.errors.append("notification must be a mapping")
    elif notification.get("ntfy_topic") != "forge-ops":
        result.errors.append("notification.ntfy_topic must be forge-ops")

    schedule_policy = policy.get("schedule_policy")
    if not isinstance(schedule_policy, dict):
        result.errors.append("schedule_policy must be a mapping")
    else:
        config_state = schedule_policy.get("config_state")
        if not isinstance(config_state, dict):
            result.errors.append("schedule_policy.config_state must be a mapping")
        elif config_state.get("class_id") != "hasslehoff-config-state":
            result.errors.append("schedule_policy.config_state.class_id is wrong")

    restore_validation = policy.get("restore_validation")
    if not isinstance(restore_validation, dict):
        result.errors.append("restore_validation must be a mapping")
    else:
        validate_restore_validation(
            restore_validation.get("vm_lxc_required"),
            {"disposable_restore", "offline_image_inspection"},
            "restore_validation.vm_lxc_required",
            result,
        )

    vm_lxc_coverage = policy.get("vm_lxc_coverage")
    if not isinstance(vm_lxc_coverage, list):
        result.errors.append("vm_lxc_coverage must be a list")
        return result

    observed_services: set[str] = set()
    for index, entry in enumerate(vm_lxc_coverage):
        label = f"vm_lxc_coverage[{index}]"
        if not isinstance(entry, dict):
            result.errors.append(f"{label} must be a mapping")
            continue
        service_class = entry.get("service_class")
        if not isinstance(service_class, str) or not service_class:
            result.errors.append(f"{label}.service_class must be a non-empty string")
            continue
        if service_class in observed_services:
            result.errors.append(f"duplicate service_class {service_class}")
        observed_services.add(service_class)
        for key in ("backup_method", "cadence"):
            if not isinstance(entry.get(key), str) or not entry[key]:
                result.errors.append(f"{label}.{key} must be a non-empty string")
        validate_restore_validation(
            entry.get("restore_validation"),
            {"disposable_restore", "offline_image_inspection"},
            f"{label}.restore_validation",
            result,
        )

    missing_services = sorted(required_service_classes - observed_services)
    extra_services = sorted(observed_services - required_service_classes)
    if missing_services:
        result.errors.append(f"vm_lxc_coverage missing services: {', '.join(missing_services)}")
    if extra_services:
        result.errors.append(
            f"vm_lxc_coverage has unexpected services: {', '.join(extra_services)}"
        )
    result.vm_lxc_services = len(observed_services & required_service_classes)
    return result


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", type=Path, help="Hasslehoff backup policy YAML path")
    parser.add_argument("--format", choices=("json", "text"), default="text")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    result = validate_policy(load_yaml(args.policy))
    if args.format == "json":
        print(json.dumps(result.as_dict(), indent=2, sort_keys=True))
    elif result.ok:
        print(
            "PASS: "
            f"{result.policy_id} covers {result.vm_lxc_services} VM/LXC service classes "
            f"to {result.external_target_id}"
        )
    else:
        for error in result.errors:
            print(f"FAIL: {error}", file=sys.stderr)
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
