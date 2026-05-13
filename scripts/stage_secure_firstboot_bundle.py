#!/usr/bin/env python3
"""Validate and age-encrypt a secure first-boot enrollment bundle."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from validate_secure_firstboot_bundle import load_bundle, validate_bundle

REPO_ROOT = Path(__file__).resolve().parents[1]


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--expected-fqdn", required=True)
    parser.add_argument("--recipient", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--age-bin", default="age")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--allow-repo-output", action="store_true")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    return parser.parse_args()


def emit(args: argparse.Namespace, payload: dict[str, object]) -> None:
    if args.format == "json":
        print(json.dumps(payload, indent=2, sort_keys=True))
        return
    for key, value in payload.items():
        print(f"{key}={value}")


def main() -> int:
    args = parse_args()
    apply = bool(args.apply and not args.dry_run)
    output = args.output

    if is_within(output, REPO_ROOT) and not args.allow_repo_output:
        print("refusing to write encrypted bundle inside repository", file=sys.stderr)
        return 2

    try:
        bundle = load_bundle(args.bundle)
        validation = validate_bundle(bundle, expected_fqdn=args.expected_fqdn)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"invalid bundle: {exc}", file=sys.stderr)
        return 1

    if not validation.ok:
        for error in validation.errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    result: dict[str, object] = {
        "bundle": str(args.bundle),
        "dry_run": not apply,
        "expected_fqdn": args.expected_fqdn,
        "output": str(output),
        "would_write": str(output),
    }

    if not apply:
        emit(args, result)
        return 0

    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        args.age_bin,
        "--encrypt",
        "--recipient",
        args.recipient,
        "--output",
        str(output),
        str(args.bundle),
    ]
    subprocess.run(command, check=True)  # noqa: S603
    output.chmod(0o600)
    result["written"] = str(output)
    emit(args, result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
