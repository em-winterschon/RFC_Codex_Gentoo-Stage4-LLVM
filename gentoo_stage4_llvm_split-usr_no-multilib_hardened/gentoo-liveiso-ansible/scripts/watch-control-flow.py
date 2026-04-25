#!/usr/bin/env python3
"""Render structured Ansible control-flow JSONL events for remote observation."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", help="Explicit JSONL control-flow log path.")
    parser.add_argument(
        "--dir",
        default="/tmp/ansible-control-flow",
        help="Directory to search when --path is omitted.",
    )
    parser.add_argument(
        "--follow",
        action="store_true",
        help="Follow the control-flow log like tail -f.",
    )
    return parser.parse_args()


def resolve_path(path_arg: str | None, directory: str) -> Path:
    if path_arg:
        return Path(path_arg)

    directory_path = Path(directory)
    files = sorted(directory_path.glob("*.jsonl"), key=lambda item: item.stat().st_mtime)
    if not files:
        raise SystemExit(f"no control-flow logs found in {directory_path}")
    return files[-1]


def format_event(payload: dict) -> str:
    ts = payload.get("ts", "-")
    event = payload.get("event", "-")
    play = payload.get("play") or "-"
    task = payload.get("task") or "-"
    host = payload.get("host") or "-"
    checkpoint = payload.get("checkpoint")
    if isinstance(checkpoint, dict):
        stage = checkpoint.get("stage_id", "-")
        phase = checkpoint.get("checkpoint", event)
        return f"{ts} [{event}] play={play} stage={stage} phase={phase} task={task} host={host}"
    return f"{ts} [{event}] play={play} task={task} host={host}"


def emit_existing(path: Path):
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            payload = json.loads(line)
            print(format_event(payload))


def follow(path: Path):
    with path.open(encoding="utf-8") as handle:
        handle.seek(0, 2)
        while True:
            line = handle.readline()
            if not line:
                time.sleep(0.5)
                continue
            payload = json.loads(line)
            print(format_event(payload))
            sys.stdout.flush()


def main() -> int:
    args = parse_args()
    path = resolve_path(args.path, args.dir)
    emit_existing(path)
    if args.follow:
        follow(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
