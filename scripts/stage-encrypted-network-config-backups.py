#!/usr/bin/env python3
"""Stage encrypted network-device config backups for git tracking.

The collector playbooks write plaintext device exports under operator-private
paths. This script copies only encrypted Ansible Vault outputs into the repo so
large RouterOS/SwOS config artifacts can be versioned without expanding the
main group_vars/all/vault.yml file.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[1]

ROUTEROS_ARTIFACTS = (
    "export-show-sensitive.txt",
    "export-hide-sensitive.txt",
    "manifest.json",
)

SWOS_ARTIFACTS = (
    "backup.swb",
    "summary.json",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Encrypt latest RouterOS/SwOS config backup artifacts into a repo-safe "
            "directory using ansible-vault encrypt."
        ),
    )
    parser.add_argument(
        "--routeros-root",
        type=Path,
        default=Path("/root/operator-private/routeros/state-snapshots"),
        help="Root containing RouterOS snapshots as <host>/<timestamp>/ files.",
    )
    parser.add_argument(
        "--swos-root",
        type=Path,
        default=Path("/root/operator-private/swos"),
        help="Root containing SwOS snapshots as <host>/<timestamp>/ files.",
    )
    parser.add_argument(
        "--routeros-manual-root",
        type=Path,
        default=Path("/root/operator-private/routeros"),
        help="Root containing manual RouterOS export directories with post-*.rsc files.",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=REPO_ROOT / "encrypted-backups" / "network-devices",
        help="Repository directory for encrypted backup files.",
    )
    parser.add_argument(
        "--vault-wrapper",
        type=Path,
        default=REPO_ROOT / "scripts" / "with-ansible-vault-env.sh",
        help="Wrapper that sources vault env before invoking ansible-vault.",
    )
    parser.add_argument(
        "--include-all",
        action="store_true",
        help="Stage all timestamped snapshots instead of only the latest per host.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print selected artifacts without writing encrypted output.",
    )
    parser.add_argument(
        "--fail-when-empty",
        action="store_true",
        help="Exit non-zero if no backup artifacts were found.",
    )
    return parser.parse_args()


def safe_name(value: str) -> str:
    safe = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in value)
    return safe.strip("._-") or "unnamed"


def timestamp_dirs(root: Path) -> Iterable[tuple[str, Path]]:
    if not root.exists():
        return
    for host_dir in sorted(path for path in root.iterdir() if path.is_dir()):
        for stamp_dir in sorted(path for path in host_dir.iterdir() if path.is_dir()):
            yield host_dir.name, stamp_dir


def snapshot_dirs_by_host(root: Path) -> dict[str, list[Path]]:
    by_host: dict[str, list[Path]] = {}
    for host, stamp_dir in timestamp_dirs(root):
        by_host.setdefault(host, []).append(stamp_dir)
    return by_host


def selected_snapshot_dirs(root: Path, include_all: bool) -> list[tuple[str, Path]]:
    by_host = snapshot_dirs_by_host(root)
    selected: list[tuple[str, Path]] = []
    for host, stamp_dirs in sorted(by_host.items()):
        chosen = stamp_dirs if include_all else [sorted(stamp_dirs)[-1]]
        selected.extend((host, stamp_dir) for stamp_dir in chosen)
    return selected


def routeros_command_returncodes(snapshot_dir: Path) -> dict[str, int]:
    manifest_path = snapshot_dir / "manifest.json"
    if not manifest_path.is_file():
        return {}
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return {
        str(command.get("file")): int(command.get("returncode", 1))
        for command in manifest.get("commands", [])
        if isinstance(command, dict) and command.get("file")
    }


def candidate_artifacts(kind: str, snapshot_dir: Path) -> list[Path]:
    filenames = ROUTEROS_ARTIFACTS if kind == "routeros" else SWOS_ARTIFACTS
    artifacts = [snapshot_dir / filename for filename in filenames if (snapshot_dir / filename).is_file()]

    # RouterOS should prefer full exports when present, but retain hide-sensitive
    # exports as a fallback for devices that do not support show-sensitive.
    if kind == "routeros":
        returncodes = routeros_command_returncodes(snapshot_dir)
        artifacts = [
            path
            for path in artifacts
            if path.name == "manifest.json" or returncodes.get(path.name, 0) == 0
        ]
        has_sensitive = any(path.name == "export-show-sensitive.txt" for path in artifacts)
        if has_sensitive:
            artifacts = [
                path for path in artifacts if path.name != "export-hide-sensitive.txt"
            ]
        has_config = any(path.name != "manifest.json" for path in artifacts)
        if not has_config:
            return []
    return artifacts


def encrypted_dest(output_root: Path, kind: str, host: str, snapshot_dir: Path, source: Path) -> Path:
    return (
        output_root
        / kind
        / safe_name(host)
        / safe_name(snapshot_dir.name)
        / f"{safe_name(source.name)}.vault"
    )


def encrypt_file(vault_wrapper: Path, source: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp_dest = dest.with_suffix(dest.suffix + ".tmp")
    if tmp_dest.exists():
        tmp_dest.unlink()
    subprocess.run(
        [
            str(vault_wrapper),
            "ansible-vault",
            "encrypt",
            str(source),
            "--output",
            str(tmp_dest),
        ],
        check=True,
    )
    tmp_dest.replace(dest)


def stage_kind(
    *,
    kind: str,
    root: Path,
    output_root: Path,
    vault_wrapper: Path,
    include_all: bool,
    dry_run: bool,
) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for host, stamp_dirs in sorted(snapshot_dirs_by_host(root).items()):
        ordered_dirs = sorted(stamp_dirs)
        if not include_all:
            ordered_dirs = list(reversed(ordered_dirs))
        for snapshot_dir in ordered_dirs:
            artifacts = candidate_artifacts(kind, snapshot_dir)
            if not artifacts:
                continue
            for source in artifacts:
                dest = encrypted_dest(output_root, kind, host, snapshot_dir, source)
                record: dict[str, object] = {
                    "device_type": kind,
                    "inventory_host": host,
                    "snapshot_timestamp": snapshot_dir.name,
                    "source_file": str(source),
                    "encrypted_file": str(dest.relative_to(REPO_ROOT) if dest.is_relative_to(REPO_ROOT) else dest),
                    "source_size_bytes": source.stat().st_size,
                }
                if dry_run:
                    record["dry_run"] = True
                else:
                    encrypt_file(vault_wrapper, source, dest)
                    record["encrypted_size_bytes"] = dest.stat().st_size
                records.append(record)
            if not include_all:
                break
    return records


def stage_manual_routeros_exports(
    *,
    root: Path,
    output_root: Path,
    vault_wrapper: Path,
    include_all: bool,
    dry_run: bool,
) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    if not root.exists():
        return records

    for host_dir in sorted(path for path in root.iterdir() if path.is_dir()):
        exports = sorted(host_dir.glob("post-*.rsc"))
        if not exports:
            continue
        selected_exports = exports if include_all else [exports[-1]]
        for source in selected_exports:
            dest = (
                output_root
                / "routeros-manual"
                / safe_name(host_dir.name)
                / f"{safe_name(source.name)}.vault"
            )
            record: dict[str, object] = {
                "device_type": "routeros-manual",
                "inventory_host": host_dir.name,
                "snapshot_timestamp": source.stem.removeprefix("post-"),
                "source_file": str(source),
                "encrypted_file": str(dest.relative_to(REPO_ROOT) if dest.is_relative_to(REPO_ROOT) else dest),
                "source_size_bytes": source.stat().st_size,
            }
            if dry_run:
                record["dry_run"] = True
            else:
                encrypt_file(vault_wrapper, source, dest)
                record["encrypted_size_bytes"] = dest.stat().st_size
            records.append(record)
    return records


def write_manifest(output_root: Path, records: list[dict[str, object]], dry_run: bool) -> None:
    if dry_run:
        return
    output_root.mkdir(parents=True, exist_ok=True)
    manifest = {
        "generated_at_epoch": int(time.time()),
        "records": records,
        "schema": "rfc1918.network-device-config-backups.v1",
    }
    (output_root / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    if not args.dry_run and not args.vault_wrapper.exists():
        print(f"vault wrapper not found: {args.vault_wrapper}", file=sys.stderr)
        return 2

    records = []
    records += stage_kind(
        kind="routeros",
        root=args.routeros_root,
        output_root=args.output_root,
        vault_wrapper=args.vault_wrapper,
        include_all=args.include_all,
        dry_run=args.dry_run,
    )
    records += stage_kind(
        kind="swos",
        root=args.swos_root,
        output_root=args.output_root,
        vault_wrapper=args.vault_wrapper,
        include_all=args.include_all,
        dry_run=args.dry_run,
    )
    records += stage_manual_routeros_exports(
        root=args.routeros_manual_root,
        output_root=args.output_root,
        vault_wrapper=args.vault_wrapper,
        include_all=args.include_all,
        dry_run=args.dry_run,
    )

    if args.fail_when_empty and not records:
        print("no network-device backup artifacts found", file=sys.stderr)
        return 1

    write_manifest(args.output_root, records, args.dry_run)
    print(json.dumps({"records": records}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
