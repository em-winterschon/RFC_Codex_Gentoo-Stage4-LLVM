#!/usr/bin/env python3
"""Render a Stage5 secure first-boot FreeIPA OTP enrollment bundle."""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

SCHEMA = "rfc99.secure-firstboot-enrollment.v1"
METHOD = "freeipa-otp"


def ensure_iso_timestamp(value: str) -> str:
    candidate = value.strip()
    parse_candidate = candidate[:-1] + "+00:00" if candidate.endswith("Z") else candidate
    datetime.fromisoformat(parse_candidate)
    return candidate


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fqdn", required=True)
    parser.add_argument("--realm", required=True)
    parser.add_argument("--domain", required=True)
    parser.add_argument("--ipa-server", required=True)
    parser.add_argument("--expires-at", required=True)
    parser.add_argument("--otp-env", required=True)
    parser.add_argument("--generation-id", default="")
    parser.add_argument("--ca-cert-sha256", default="")
    parser.add_argument("--age-recipient", default="")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def build_payload(args: argparse.Namespace, otp: str) -> dict[str, object]:
    payload: dict[str, object] = {
        "schema": SCHEMA,
        "method": METHOD,
        "fqdn": args.fqdn,
        "realm": args.realm,
        "domain": args.domain,
        "ipa_server": args.ipa_server,
        "expires_at": ensure_iso_timestamp(args.expires_at),
        "enrollment": {
            "otp": otp,
            "otp_source": "freeipa-host-random",
        },
        "crypto": {
            "transport": "age",
        },
    }
    if args.generation_id:
        payload["generation_id"] = args.generation_id
    if args.ca_cert_sha256:
        payload["ca_cert_sha256"] = args.ca_cert_sha256
    if args.age_recipient:
        payload["crypto"] = {
            "transport": "age",
            "recipient": args.age_recipient,
        }
    return payload


def main() -> int:
    args = parse_args()
    otp = os.environ.get(args.otp_env, "")
    if not otp:
        print(f"missing OTP environment variable: {args.otp_env}", file=sys.stderr)
        return 2

    try:
        payload = build_payload(args, otp)
    except ValueError as exc:
        print(f"invalid expires-at timestamp: {exc}", file=sys.stderr)
        return 2

    rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
        args.output.chmod(0o600)
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
