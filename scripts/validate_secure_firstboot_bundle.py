#!/usr/bin/env python3
"""Validate Stage5 secure first-boot enrollment bundles before use."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

SCHEMA = "rfc99.secure-firstboot-enrollment.v1"
METHOD = "freeipa-otp"
FORBIDDEN_SECRET_FIELDS = {
    "keytab",
    "krb5_keytab",
    "krb5.keytab",
    "keytab_b64",
    "host_keytab",
    "private_key",
    "age_identity",
}


@dataclass
class BundleValidationResult:
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


def parse_timestamp(value: str, label: str, result: BundleValidationResult) -> datetime | None:
    candidate = value.strip()
    if candidate.endswith("Z"):
        candidate = candidate[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError:
        result.errors.append(f"{label}: must be an ISO-8601 timestamp")
        return None
    if parsed.tzinfo is None:
        result.errors.append(f"{label}: must include timezone")
        return None
    return parsed.astimezone(UTC)


def required_string(payload: dict[str, Any], key: str, result: BundleValidationResult) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        result.errors.append(f"{key}: missing required non-empty string")
        return ""
    return value.strip()


def reject_forbidden_secret_fields(
    payload: Any, result: BundleValidationResult, path: str = ""
) -> None:
    if isinstance(payload, dict):
        for key, value in payload.items():
            current_path = f"{path}.{key}" if path else key
            if key in FORBIDDEN_SECRET_FIELDS:
                result.errors.append(f"{current_path}: forbidden secret field")
            reject_forbidden_secret_fields(value, result, current_path)
    elif isinstance(payload, list):
        for index, value in enumerate(payload):
            reject_forbidden_secret_fields(value, result, f"{path}[{index}]")


def validate_bundle(
    payload: dict[str, Any],
    *,
    expected_fqdn: str | None = None,
    now: datetime | None = None,
) -> BundleValidationResult:
    result = BundleValidationResult()
    now_utc = (now or datetime.now(UTC)).astimezone(UTC)
    reject_forbidden_secret_fields(payload, result)

    if payload.get("schema") != SCHEMA:
        result.errors.append(f"schema: must be {SCHEMA}")
    if payload.get("method") != METHOD:
        result.errors.append(f"method: must be {METHOD}")

    fqdn = required_string(payload, "fqdn", result)
    required_string(payload, "realm", result)
    required_string(payload, "domain", result)
    required_string(payload, "ipa_server", result)
    expires_at_raw = required_string(payload, "expires_at", result)
    if expected_fqdn and fqdn and fqdn != expected_fqdn:
        result.errors.append(f"fqdn: expected {expected_fqdn}, got {fqdn}")
    if expires_at_raw:
        expires_at = parse_timestamp(expires_at_raw, "expires_at", result)
        if expires_at is not None and expires_at <= now_utc:
            result.errors.append("expires_at: bundle expired")

    enrollment = payload.get("enrollment")
    if not isinstance(enrollment, dict):
        result.errors.append("enrollment: missing required mapping")
    else:
        otp = enrollment.get("otp")
        if not isinstance(otp, str) or not otp.strip():
            result.errors.append("enrollment.otp: missing required non-empty string")
        if enrollment.get("otp_source") != "freeipa-host-random":
            result.errors.append("enrollment.otp_source: must be freeipa-host-random")

    crypto = payload.get("crypto", {})
    if crypto and not isinstance(crypto, dict):
        result.errors.append("crypto: must be a mapping when supplied")
    elif isinstance(crypto, dict):
        transport = crypto.get("transport", "age")
        if transport != "age":
            result.errors.append("crypto.transport: first implementation must be age")

    return result


def load_bundle(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level bundle must be a JSON object")
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--expected-fqdn")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        payload = load_bundle(args.bundle)
        result = validate_bundle(payload, expected_fqdn=args.expected_fqdn)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        result = BundleValidationResult(errors=[str(exc)])

    if args.format == "json":
        print(json.dumps({"ok": result.ok, "errors": result.errors}, indent=2, sort_keys=True))
    else:
        for error in result.errors:
            print(f"ERROR: {error}", file=sys.stderr)
        if result.ok:
            print("PASS: secure first-boot bundle validation")
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
