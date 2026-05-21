#!/usr/bin/env python3
"""Local write-ahead spool for Forge continuity events."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import re
import socket
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

EVENT_SCHEMA = "rfc-codex.forge-memory-event.v1"
MANIFEST_SCHEMA = "rfc-codex.forge-memory-manifest.v1"
BOOTSTRAP_SCHEMA = "rfc-codex.forge-bootstrap-summary.v1"
PUBLISH_SCHEMA = "rfc-codex.forge-object-store-publish.v1"
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


def file_metadata(
    source_file: Path, object_store_root: Path, object_key: str, kind: str
) -> dict[str, Any]:
    object_file = object_store_root / object_key
    return {
        "kind": kind,
        "source_file": str(source_file),
        "object_key": object_key,
        "object_file": str(object_file),
        "sha256": sha256_file(source_file),
        "size_bytes": source_file.stat().st_size,
    }


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


def canonical_json(value: dict[str, Any]) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sign_manifest(manifest: dict[str, Any], signing_key_file: str, signing_key_id: str) -> None:
    key_id = require_safe_id(signing_key_id, "signing-key-id")
    key_path = Path(signing_key_file)
    if not key_path.exists():
        raise SpoolError(f"signing key file does not exist: {key_path}")
    signing_key = key_path.read_bytes().strip()
    if not signing_key:
        raise SpoolError(f"signing key file is empty: {key_path}")

    signed_payload = dict(manifest)
    signed_payload["signature_state"] = "signed"
    signed_payload["signature"] = {
        "algorithm": "hmac-sha256",
        "key_id": key_id,
    }
    payload = canonical_json(signed_payload)
    signature = hmac.new(signing_key, payload.encode("utf-8"), hashlib.sha256).hexdigest()

    manifest["signature_state"] = "signed"
    manifest["signature_payload"] = payload
    manifest["signature_payload_sha256"] = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    manifest["signature"] = {
        "algorithm": "hmac-sha256",
        "key_id": key_id,
        "value": signature,
    }


def load_json_file(
    path_text: str | None, label: str, base_path: Path | None = None
) -> dict[str, Any]:
    if not path_text:
        return {"path": "", "items": []}
    path = Path(path_text)
    if not path.is_absolute() and base_path is not None:
        path = base_path / path
    if not path.exists():
        raise SpoolError(f"{label} JSON does not exist: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SpoolError(f"{label} JSON is invalid: {exc.msg}") from exc
    if isinstance(value, list):
        items = value
    elif isinstance(value, dict):
        items = value.get("items", value.get("issues", value.get("blockers", [])))
        if not isinstance(items, list):
            raise SpoolError(f"{label} JSON items must be a list")
    else:
        raise SpoolError(f"{label} JSON must be an object or list")
    reject_secret_keys(items)
    return {"path": str(path), "items": items}


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


def run_git(repo_path: Path, *args: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_path), *args],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise SpoolError(f"git {' '.join(args)} failed for {repo_path}: {exc}") from exc
    return result.stdout.strip()


def summarize_repo(repo_path: Path) -> dict[str, Any]:
    if not repo_path.exists():
        raise SpoolError(f"repo path does not exist: {repo_path}")
    branch = run_git(repo_path, "branch", "--show-current")
    commit = run_git(repo_path, "rev-parse", "HEAD")
    status_lines = run_git(repo_path, "status", "--short").splitlines()
    summary = {
        "path": str(repo_path),
        "branch": branch,
        "commit": commit,
        "dirty": bool(status_lines),
        "status_short": status_lines[:50],
    }
    reject_secret_keys(summary)
    return summary


def latest_documents(repo_path: Path, limit: int) -> list[dict[str, str]]:
    patterns = [
        "docs/EOD-STATUS-*.md",
        "docs/SITREP-*.md",
        "docs/MORNING-SITREP*.md",
        "docs/OVERNIGHT-*.md",
        "docs/closeouts/*.yml",
        "docs/closeouts/*.yaml",
    ]
    candidates: list[Path] = []
    for pattern in patterns:
        candidates.extend(path for path in repo_path.glob(pattern) if path.is_file())
    candidates = sorted(
        candidates, key=lambda path: (path.stat().st_mtime, str(path)), reverse=True
    )
    documents: list[dict[str, str]] = []
    for path in candidates[:limit]:
        text = path.read_text(encoding="utf-8", errors="replace")
        title = ""
        for line in text.splitlines():
            if line.startswith("#"):
                title = line.lstrip("#").strip()
                break
        documents.append(
            {
                "path": str(path.relative_to(repo_path)),
                "title": title,
                "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            }
        )
    reject_secret_keys(documents)
    return documents


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


def bootstrap_session(args: argparse.Namespace) -> dict[str, Any]:
    spool_root = Path(args.spool_root)
    agent_id = require_safe_id(args.agent_id, "agent-id")
    session_id = require_safe_id(args.session_id, "session-id")
    repo_path = Path(args.repo_path).resolve()
    repo = summarize_repo(repo_path)
    recent_sessions = list_sessions(
        argparse.Namespace(spool_root=str(spool_root), agent_id=agent_id, limit=args.session_limit)
    )
    issue_state = load_json_file(args.issue_state_file, "issue-state", repo_path)
    blocker_state = load_json_file(args.blocker_state_file, "blocker-state", repo_path)

    bootstrap_summary = {
        "bootstrap_schema": BOOTSTRAP_SCHEMA,
        "repo": repo,
        "latest_documents": latest_documents(repo_path, args.document_limit),
        "recent_sessions": recent_sessions,
        "issue_state": issue_state,
        "blocker_state": blocker_state,
        "latest_memory_notes": args.memory_note,
        "object_store_state": args.object_store_state,
        "mcp_state": args.mcp_state,
    }
    reject_secret_keys(bootstrap_summary)

    event_args = argparse.Namespace(
        spool_root=str(spool_root),
        agent_id=agent_id,
        session_id=session_id,
        repo=repo_path.name,
        branch=repo["branch"],
        commit=repo["commit"],
        event_type="session-start",
        intent=args.intent,
        action=["continuity-bootstrap"],
        artifact=["repo-state", "memory-state", "issue-state", "blocker-state"],
        note=args.note,
        extra_json=json.dumps(bootstrap_summary, sort_keys=True),
    )
    result = append_event(event_args)
    result["bootstrap_summary"] = bootstrap_summary
    return result


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
    if args.signing_key_file:
        sign_manifest(manifest, args.signing_key_file, args.signing_key_id)
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


def normalized_prefix(raw_prefix: str) -> str:
    prefix = raw_prefix.strip("/")
    if not prefix:
        raise SpoolError("prefix must not be empty")
    parts = prefix.split("/")
    for part in parts:
        if part in {"", ".", ".."}:
            raise SpoolError("prefix contains an unsafe path component")
    return prefix


def copy_object(source_file: Path, object_file: Path, overwrite: bool) -> None:
    if object_file.exists() and not overwrite:
        raise SpoolError(f"object already exists: {object_file}")
    object_file.parent.mkdir(parents=True, exist_ok=True)
    object_file.write_bytes(source_file.read_bytes())


def publish_session(args: argparse.Namespace) -> dict[str, Any]:
    spool_root = Path(args.spool_root)
    object_store_root = Path(args.object_store_root)
    agent_id = require_safe_id(args.agent_id, "agent-id")
    session_id = require_safe_id(args.session_id, "session-id")
    prefix = normalized_prefix(args.prefix)

    event_path = event_file_for(spool_root, agent_id, session_id)
    if not event_path.exists():
        raise SpoolError(f"event log does not exist: {event_path}")
    manifest_files = manifest_files_for(spool_root, session_id)
    if not manifest_files:
        raise SpoolError(f"closeout manifest does not exist for session: {session_id}")
    closeout_manifest = Path(manifest_files[-1])

    event_key = f"{prefix}/agents/{agent_id}/sessions/{session_id}/events.jsonl"
    manifest_key = f"{prefix}/manifests/{closeout_manifest.relative_to(spool_root / 'manifests')}"
    publish_manifest_key = f"{prefix}/publish-manifests/{agent_id}/{session_id}.json"

    objects = [
        file_metadata(event_path, object_store_root, event_key, "event-log"),
        file_metadata(closeout_manifest, object_store_root, manifest_key, "closeout-manifest"),
    ]

    for item in objects:
        copy_object(Path(item["source_file"]), Path(item["object_file"]), args.overwrite)

    publish_manifest_file = object_store_root / publish_manifest_key
    if publish_manifest_file.exists() and not args.overwrite:
        raise SpoolError(f"object already exists: {publish_manifest_file}")

    published_at = utc_now()
    publish_manifest = {
        "schema": PUBLISH_SCHEMA,
        "published_at_utc": published_at,
        "backend": "filesystem",
        "object_store_root": str(object_store_root),
        "prefix": prefix,
        "session_id": session_id,
        "agent_id": agent_id,
        "host": socket.gethostname(),
        "object_count": len(objects),
        "objects": objects,
        "publish_manifest_key": publish_manifest_key,
        "publish_manifest_file": str(publish_manifest_file),
    }
    reject_secret_keys(publish_manifest)
    publish_manifest_file.parent.mkdir(parents=True, exist_ok=True)
    publish_manifest_file.write_text(
        json.dumps(publish_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return publish_manifest


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
    close.add_argument("--signing-key-file")
    close.add_argument("--signing-key-id", default="forge-local-hmac")
    close.set_defaults(func=closeout)

    publish = subparsers.add_parser(
        "publish-session",
        help="publish a closed session to a filesystem-backed object-store layout",
    )
    publish.add_argument("--spool-root", required=True)
    publish.add_argument("--object-store-root", required=True)
    publish.add_argument("--session-id", required=True)
    publish.add_argument("--agent-id", default="forge")
    publish.add_argument("--prefix", default="forge-memory/v1")
    publish.add_argument("--overwrite", action="store_true")
    publish.set_defaults(func=publish_session)

    list_parser = subparsers.add_parser("list-sessions", help="summarize local continuity sessions")
    list_parser.add_argument("--spool-root", required=True)
    list_parser.add_argument("--agent-id", default="forge")
    list_parser.add_argument("--limit", type=int, default=10)
    list_parser.set_defaults(func=list_sessions)

    bootstrap = subparsers.add_parser(
        "bootstrap-session",
        help="append a session-start event with repo, memory, issue, and blocker summaries",
    )
    bootstrap.add_argument("--spool-root", required=True)
    bootstrap.add_argument("--session-id", required=True)
    bootstrap.add_argument("--agent-id", default="forge")
    bootstrap.add_argument("--repo-path", required=True)
    bootstrap.add_argument("--intent", default="resume continuity")
    bootstrap.add_argument("--issue-state-file")
    bootstrap.add_argument("--blocker-state-file")
    bootstrap.add_argument("--memory-note", action="append", default=[])
    bootstrap.add_argument("--note", action="append", default=[])
    bootstrap.add_argument("--document-limit", type=int, default=5)
    bootstrap.add_argument("--session-limit", type=int, default=5)
    bootstrap.add_argument("--object-store-state", default="unavailable")
    bootstrap.add_argument("--mcp-state", default="unavailable")
    bootstrap.set_defaults(func=bootstrap_session)

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
