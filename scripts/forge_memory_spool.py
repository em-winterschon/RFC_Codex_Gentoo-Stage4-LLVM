#!/usr/bin/env python3
"""Local write-ahead spool for Forge continuity events."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import socket
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

EVENT_SCHEMA = "rfc-codex.forge-memory-event.v1"
MANIFEST_SCHEMA = "rfc-codex.forge-memory-manifest.v1"
SAFE_ID = re.compile(r"^[A-Za-z0-9._:-]+$")
SECRET_KEY = re.compile(
    r"(api[_-]?key|api[_-]?token|auth[_-]?token|bearer|client[_-]?secret|"
    r"keytab|password|private[_-]?key|secret|token)",
    re.IGNORECASE,
)


class SpoolError(RuntimeError):
    """Raised for user-correctable spool errors."""


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def require_safe_id(value: str, field: str) -> str:
    if not value or not SAFE_ID.match(value):
        raise SpoolError(f"{field} must match {SAFE_ID.pattern}")
    return value


def session_dir(spool_root: Path, agent_id: str, session_id: str) -> Path:
    return spool_root / "agents" / agent_id / "sessions" / session_id


def event_file_for(spool_root: Path, agent_id: str, session_id: str) -> Path:
    return session_dir(spool_root, agent_id, session_id) / "events.jsonl"


def count_jsonl_lines(path: Path) -> int:
    if not path.exists():
        return 0
    with path.open("r", encoding="utf-8") as handle:
        return sum(1 for line in handle if line.strip())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_jsonl_events(path: Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    if not path.exists():
        return events
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SpoolError(f"{path}:{line_number}: invalid JSONL event: {exc.msg}") from exc
            if not isinstance(event, dict):
                raise SpoolError(f"{path}:{line_number}: JSONL event must be an object")
            events.append(event)
    return events


def parse_extra_json(raw: str | None) -> dict[str, Any]:
    if not raw:
        return {}
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SpoolError(f"extra JSON is invalid: {exc.msg}") from exc
    if not isinstance(value, dict):
        raise SpoolError("extra JSON must be an object")
    reject_secret_keys(value)
    return value


def reject_secret_keys(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, nested in value.items():
            key_text = str(key)
            if SECRET_KEY.search(key_text):
                raise SpoolError(f"secret-looking key rejected at {path}.{key_text}")
            reject_secret_keys(nested, f"{path}.{key_text}")
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            reject_secret_keys(nested, f"{path}[{index}]")


def append_event(args: argparse.Namespace) -> dict[str, Any]:
    spool_root = Path(args.spool_root)
    agent_id = require_safe_id(args.agent_id, "agent-id")
    session_id = require_safe_id(args.session_id, "session-id")
    extra = parse_extra_json(args.extra_json)

    event: dict[str, Any] = {
        "schema": EVENT_SCHEMA,
        "timestamp_utc": utc_now(),
        "session_id": session_id,
        "agent_id": agent_id,
        "host": socket.gethostname(),
        "repo": args.repo,
        "branch": args.branch,
        "commit": args.commit,
        "event_type": args.event_type,
        "intent": args.intent,
        "actions": args.action,
        "artifacts": args.artifact,
        "notes": args.note,
    }
    if extra:
        event["extra"] = extra

    reject_secret_keys(event)
    event_path = event_file_for(spool_root, agent_id, session_id)
    event_path.parent.mkdir(parents=True, exist_ok=True)
    with event_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, sort_keys=True, separators=(",", ":")))
        handle.write("\n")

    return {
        "event_file": str(event_path),
        "event_count": count_jsonl_lines(event_path),
        "session_id": session_id,
        "agent_id": agent_id,
    }


def closeout(args: argparse.Namespace) -> dict[str, Any]:
    spool_root = Path(args.spool_root)
    agent_id = require_safe_id(args.agent_id, "agent-id")
    session_id = require_safe_id(args.session_id, "session-id")
    closed_at = utc_now()
    event_path = event_file_for(spool_root, agent_id, session_id)
    event_count = count_jsonl_lines(event_path)
    event_hash = sha256_file(event_path) if event_path.exists() else hashlib.sha256(b"").hexdigest()
    date_path = closed_at[:10].split("-")
    manifest_path = (
        spool_root / "manifests" / date_path[0] / date_path[1] / date_path[2] / f"{session_id}.json"
    )
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    manifest = {
        "schema": MANIFEST_SCHEMA,
        "closed_at_utc": closed_at,
        "session_id": session_id,
        "agent_id": agent_id,
        "host": socket.gethostname(),
        "summary": args.summary,
        "event_file": str(event_path),
        "event_count": event_count,
        "event_sha256": event_hash,
        "signature_state": "unsigned",
        "signature": None,
    }
    reject_secret_keys(manifest)
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    return {
        "manifest_file": str(manifest_path),
        "event_count": event_count,
        "session_id": session_id,
        "agent_id": agent_id,
    }


def manifest_files_for(spool_root: Path, session_id: str) -> list[str]:
    manifest_root = spool_root / "manifests"
    if not manifest_root.exists():
        return []
    return sorted(
        str(path) for path in manifest_root.glob(f"**/{session_id}.json") if path.is_file()
    )


def list_sessions(args: argparse.Namespace) -> dict[str, Any]:
    spool_root = Path(args.spool_root)
    agent_id = require_safe_id(args.agent_id, "agent-id")
    limit = args.limit
    if limit < 1:
        raise SpoolError("limit must be at least 1")

    sessions_root = spool_root / "agents" / agent_id / "sessions"
    session_summaries: list[dict[str, Any]] = []
    if sessions_root.exists():
        for event_path in sorted(sessions_root.glob("*/events.jsonl")):
            session_id = event_path.parent.name
            events = read_jsonl_events(event_path)
            if events:
                first_event = events[0]
                last_event = events[-1]
                first_timestamp = str(first_event.get("timestamp_utc", ""))
                last_timestamp = str(last_event.get("timestamp_utc", ""))
                last_event_type = str(last_event.get("event_type", ""))
                last_intent = str(last_event.get("intent", ""))
            else:
                first_timestamp = ""
                last_timestamp = ""
                last_event_type = ""
                last_intent = ""
            manifest_files = manifest_files_for(spool_root, session_id)
            session_summaries.append(
                {
                    "session_id": session_id,
                    "event_file": str(event_path),
                    "event_count": len(events),
                    "event_sha256": sha256_file(event_path),
                    "first_timestamp_utc": first_timestamp,
                    "last_timestamp_utc": last_timestamp,
                    "last_event_type": last_event_type,
                    "last_intent": last_intent,
                    "closed": bool(manifest_files),
                    "manifest_files": manifest_files,
                }
            )

    session_summaries.sort(
        key=lambda item: (str(item["last_timestamp_utc"]), str(item["session_id"])),
        reverse=True,
    )
    limited_sessions = session_summaries[:limit]
    return {
        "agent_id": agent_id,
        "session_count": len(limited_sessions),
        "total_session_count": len(session_summaries),
        "sessions": limited_sessions,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    append = subparsers.add_parser("append-event", help="append one continuity event")
    append.add_argument("--spool-root", required=True)
    append.add_argument("--session-id", required=True)
    append.add_argument("--agent-id", default="forge")
    append.add_argument("--repo", default="")
    append.add_argument("--branch", default="")
    append.add_argument("--commit", default="")
    append.add_argument("--event-type", required=True)
    append.add_argument("--intent", default="")
    append.add_argument("--action", action="append", default=[])
    append.add_argument("--artifact", action="append", default=[])
    append.add_argument("--note", action="append", default=[])
    append.add_argument("--extra-json")
    append.set_defaults(func=append_event)

    close = subparsers.add_parser("closeout", help="write a session closeout manifest")
    close.add_argument("--spool-root", required=True)
    close.add_argument("--session-id", required=True)
    close.add_argument("--agent-id", default="forge")
    close.add_argument("--summary", required=True)
    close.set_defaults(func=closeout)

    list_parser = subparsers.add_parser("list-sessions", help="summarize local continuity sessions")
    list_parser.add_argument("--spool-root", required=True)
    list_parser.add_argument("--agent-id", default="forge")
    list_parser.add_argument("--limit", type=int, default=10)
    list_parser.set_defaults(func=list_sessions)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = args.func(args)
    except SpoolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
