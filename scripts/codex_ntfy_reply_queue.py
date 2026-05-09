#!/usr/bin/env python3
"""Shared queue helpers for Codex ntfy reply processing."""

from __future__ import annotations

import json
import os
import re
import tempfile
import uuid
from collections.abc import Iterator
from pathlib import Path
from typing import Any

ALLOW_RE = re.compile(r"^allow\s+([A-Za-z0-9._:-]+)\s*$", re.IGNORECASE)
DENY_RE = re.compile(r"^deny\s+([A-Za-z0-9._:-]+)\s*$", re.IGNORECASE)
ANSWER_RE = re.compile(r"^([A-Za-z0-9._:-]+)\s*:\s*(.+)$", re.DOTALL)
STATUS_RE = re.compile(r"^status(?:\s+([A-Za-z0-9._:-]+))?\s*$", re.IGNORECASE)
SYSLOG_MESSAGE_RE = re.compile(r'message="([^"]+)"')


def reply_queue_root() -> Path:
    return Path(
        os.getenv("CODEX_NTFY_REPLY_QUEUE_DIR", str(Path.home() / ".codex/ntfy-replies"))
    )


def pending_dir(root: Path | None = None) -> Path:
    resolved_root = root or reply_queue_root()
    return resolved_root / "pending"


def processed_dir(root: Path | None = None) -> Path:
    resolved_root = root or reply_queue_root()
    return resolved_root / "processed"


def ensure_queue_dirs(root: Path | None = None) -> tuple[Path, Path]:
    pending = pending_dir(root)
    processed = processed_dir(root)
    pending.mkdir(parents=True, exist_ok=True)
    processed.mkdir(parents=True, exist_ok=True)
    return pending, processed


def queue_available(root: Path | None = None) -> bool:
    return pending_dir(root).exists()


def normalize_reply_message(
    message: str,
    *,
    message_id: str,
    timestamp: int,
    topic: str,
) -> dict[str, Any] | None:
    stripped = message.strip()
    syslog_match = SYSLOG_MESSAGE_RE.search(stripped)
    if syslog_match:
        stripped = syslog_match.group(1).strip()
    if not stripped:
      return None

    allow_match = ALLOW_RE.match(stripped)
    if allow_match:
        return {
            "kind": "permission_reply",
            "request_id": allow_match.group(1),
            "decision": "allow",
            "message_id": message_id,
            "timestamp": timestamp,
            "topic": topic,
            "raw_message": stripped,
        }

    deny_match = DENY_RE.match(stripped)
    if deny_match:
        return {
            "kind": "permission_reply",
            "request_id": deny_match.group(1),
            "decision": "deny",
            "message_id": message_id,
            "timestamp": timestamp,
            "topic": topic,
            "raw_message": stripped,
        }

    answer_match = ANSWER_RE.match(stripped)
    if answer_match:
        return {
            "kind": "question_reply",
            "request_id": answer_match.group(1),
            "answer": answer_match.group(2).strip(),
            "message_id": message_id,
            "timestamp": timestamp,
            "topic": topic,
            "raw_message": stripped,
        }

    status_match = STATUS_RE.match(stripped)
    if status_match:
        return {
            "kind": "status_request",
            "request_id": (status_match.group(1) or "").strip(),
            "message_id": message_id,
            "timestamp": timestamp,
            "topic": topic,
            "raw_message": stripped,
        }

    return {
        "kind": "unrecognized_reply",
        "request_id": "",
        "message_id": message_id,
        "timestamp": timestamp,
        "topic": topic,
        "raw_message": stripped,
    }


def enqueue_reply(payload: dict[str, Any], root: Path | None = None) -> Path:
    pending, _ = ensure_queue_dirs(root)
    filename = f"{int(payload['timestamp']):010d}-{payload['message_id']}.json"
    destination = pending / filename
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=pending, delete=False, prefix=".tmp.", suffix=".json"
    ) as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temp_path = Path(handle.name)
    temp_path.replace(destination)
    return destination


def iter_pending_replies(root: Path | None = None) -> Iterator[Path]:
    pending = pending_dir(root)
    if not pending.exists():
        return iter(())
    return iter(sorted(pending.glob("*.json")))


def load_reply(path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def consume_reply(
    request_id: str,
    *,
    expected_kind: str,
    root: Path | None = None,
) -> dict[str, Any] | None:
    ensure_queue_dirs(root)
    found = find_reply(request_id, expected_kind=expected_kind, root=root)
    if found:
        path, payload = found
        mark_processed(path, root=root)
        return payload
    return None


def synthetic_message_id() -> str:
    return uuid.uuid4().hex[:12]


def find_reply(
    request_id: str,
    *,
    expected_kind: str,
    root: Path | None = None,
) -> tuple[Path, dict[str, Any]] | None:
    ensure_queue_dirs(root)
    for path in iter_pending_replies(root):
        payload = load_reply(path)
        if not payload:
            continue
        if payload.get("kind") != expected_kind:
            continue
        if payload.get("request_id") != request_id:
            continue
        return path, payload
    return None


def mark_processed(path: Path, *, root: Path | None = None) -> Path:
    ensure_queue_dirs(root)
    destination = processed_dir(root) / path.name
    path.replace(destination)
    return destination
