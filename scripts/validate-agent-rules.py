#!/usr/bin/env python3
"""Validate or synchronize repository AGENTS.md from a canonical source."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import tempfile
from pathlib import Path


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def read_hash_file(path: Path) -> str:
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        raise ValueError(f"{path}: expected a SHA256 hash, found an empty file")
    digest = text.split()[0].strip().lower()
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise ValueError(f"{path}: invalid SHA256 hash {digest!r}")
    return digest


def fsync_directory(path: Path) -> None:
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_write_bytes(path: Path, payload: bytes, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp_path, mode)
        os.replace(tmp_path, path)
        fsync_directory(path.parent)
    except Exception:
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass
        raise


def require_regular_file(path: Path, label: str) -> bytes:
    if not path.is_file():
        raise FileNotFoundError(f"{label} does not exist or is not a regular file: {path}")
    return path.read_bytes()


def validate(args: argparse.Namespace) -> int:
    target = Path(args.target)
    target_payload = require_regular_file(target, "target")
    target_hash = sha256_bytes(target_payload)
    failures: list[str] = []

    source_hash = ""
    if args.source:
        source = Path(args.source)
        source_payload = require_regular_file(source, "source")
        source_hash = sha256_bytes(source_payload)
        if target_payload != source_payload:
            failures.append(
                f"{target} differs from canonical source {source} "
                f"(target={target_hash}, source={source_hash})"
            )

    if args.expected_sha256:
        expected_hash = args.expected_sha256.lower()
        if target_hash != expected_hash:
            failures.append(f"{target} hash {target_hash} != expected {expected_hash}")
        if source_hash and source_hash != expected_hash:
            failures.append(f"source hash {source_hash} != expected {expected_hash}")

    if args.expected_sha256_file:
        expected_path = Path(args.expected_sha256_file)
        expected_hash = read_hash_file(expected_path)
        if target_hash != expected_hash:
            failures.append(f"{target} hash {target_hash} != {expected_path} hash {expected_hash}")
        if source_hash and source_hash != expected_hash:
            failures.append(f"source hash {source_hash} != {expected_path} hash {expected_hash}")

    if not args.source and not args.expected_sha256 and not args.expected_sha256_file:
        failures.append("validate requires --source, --expected-sha256, or --expected-sha256-file")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1

    print(f"PASS: {target} sha256={target_hash}")
    return 0


def sync(args: argparse.Namespace) -> int:
    source = Path(args.source)
    target = Path(args.target)
    source_payload = require_regular_file(source, "source")
    source_hash = sha256_bytes(source_payload)

    if args.expected_sha256_file:
        expected_path = Path(args.expected_sha256_file)
        if expected_path.exists() and not args.update_expected_sha256:
            expected_hash = read_hash_file(expected_path)
            if source_hash != expected_hash:
                print(
                    f"FAIL: source hash {source_hash} != {expected_path} hash {expected_hash}; "
                    "rerun with --update-expected-sha256 only after approving the "
                    "new canonical source",
                    file=sys.stderr,
                )
                return 1

    current_payload = target.read_bytes() if target.exists() else b""
    changed = current_payload != source_payload
    if changed or args.force:
        atomic_write_bytes(target, source_payload)

    if args.expected_sha256_file and args.update_expected_sha256:
        expected_payload = f"{source_hash}  {target.name}\n".encode("ascii")
        atomic_write_bytes(Path(args.expected_sha256_file), expected_payload)

    status = "updated" if changed else "already-current"
    print(f"PASS: {target} {status} sha256={source_hash}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate or synchronize repository AGENTS.md from canonical Yukon standards.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="validate target AGENTS.md")
    validate_parser.add_argument("--target", default="AGENTS.md")
    validate_parser.add_argument("--source", default=os.environ.get("AGENTS_STANDARD_PATH", ""))
    validate_parser.add_argument(
        "--expected-sha256", default=os.environ.get("AGENTS_STANDARD_SHA256", "")
    )
    validate_parser.add_argument(
        "--expected-sha256-file", default="policy/agentsys/AGENTS.md.sha256"
    )
    validate_parser.set_defaults(func=validate)

    sync_parser = subparsers.add_parser("sync", help="synchronize target AGENTS.md from source")
    sync_parser.add_argument("--target", default="AGENTS.md")
    sync_parser.add_argument(
        "--source", default=os.environ.get("AGENTS_STANDARD_PATH", ""), required=False
    )
    sync_parser.add_argument("--expected-sha256-file", default="policy/agentsys/AGENTS.md.sha256")
    sync_parser.add_argument(
        "--update-expected-sha256",
        action="store_true",
        help="atomically update the pinned hash after approving a new canonical source",
    )
    sync_parser.add_argument(
        "--force", action="store_true", help="rewrite target even if content is identical"
    )
    sync_parser.set_defaults(func=sync)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "sync" and not args.source:
        parser.error("sync requires --source or AGENTS_STANDARD_PATH")
    try:
        return int(args.func(args))
    except (OSError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
