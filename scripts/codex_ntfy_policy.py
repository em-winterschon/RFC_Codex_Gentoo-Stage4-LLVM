#!/usr/bin/env python3
"""Reply policy helpers for Codex ntfy integrations."""

from __future__ import annotations

import json
import os
from pathlib import Path

DEFAULT_POLICY = {
    "apiVersion": "rfc-codex/v1alpha1",
    "kind": "CodexNtfyPolicy",
    "metadata": {
        "name": "builtin-default-codex-ntfy-policy",
        "description": "Built-in fallback policy for Codex ntfy replies.",
    },
    "replyKinds": {
        "permission_reply": {"mode": "state-driven"},
        "question_reply": {"mode": "state-driven"},
        "status_request": {"mode": "advisory"},
        "unrecognized_reply": {"mode": "advisory"},
    },
}

ALLOWED_MODES = {"state-driven", "advisory"}


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def default_policy_path() -> Path:
    return repo_root() / "config/codex-ntfy-policy.json"


def policy_path() -> Path:
    explicit = os.getenv("CODEX_NTFY_POLICY_FILE", "").strip()
    if explicit:
        return Path(explicit)
    home_policy = Path.home() / ".codex/ntfy-policy.json"
    if home_policy.exists():
        return home_policy
    return default_policy_path()


def load_policy() -> dict:
    path = policy_path()
    if not path.exists():
        return DEFAULT_POLICY
    try:
        candidate = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return DEFAULT_POLICY
    if not isinstance(candidate, dict):
        return DEFAULT_POLICY
    merged = json.loads(json.dumps(DEFAULT_POLICY))
    merged_reply_kinds = merged.setdefault("replyKinds", {})
    for reply_kind, config in candidate.get("replyKinds", {}).items():
        if not isinstance(config, dict):
            continue
        merged_reply_kinds.setdefault(reply_kind, {}).update(config)
    merged["metadata"].update(candidate.get("metadata", {}))
    merged["apiVersion"] = candidate.get("apiVersion", merged["apiVersion"])
    merged["kind"] = candidate.get("kind", merged["kind"])
    return merged


def mode_for_kind(kind: str) -> str:
    policy = load_policy()
    mode = (
        policy.get("replyKinds", {})
        .get(kind, {})
        .get("mode", DEFAULT_POLICY["replyKinds"].get(kind, {}).get("mode", "advisory"))
    )
    return mode if mode in ALLOWED_MODES else "advisory"
