#!/usr/bin/env python3
"""Codex notify handler that forwards turn-complete events to ntfy."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO_ROOT))

import ntfy_notify  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("payload", nargs="?")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def topic_for_state(state: str) -> str:
    state_key = state.upper().replace("-", "_")
    return (
        os.getenv(f"CODEX_NTFY_TOPIC_{state_key}")
        or os.getenv("CODEX_NTFY_ALERT_TOPIC")
        or os.getenv("CODEX_NTFY_TOPIC")
        or os.getenv("NTFY_ALERT_TOPIC")
        or os.getenv("NTFY_TOPIC", "")
    )


def main() -> int:
    args = parse_args()
    if not args.payload:
        return 0
    try:
        payload = json.loads(args.payload)
    except json.JSONDecodeError:
        return 0
    if payload.get("type") != "agent-turn-complete":
        return 0

    last_message = payload.get("last-assistant-message") or "Turn complete"
    prompt_messages = payload.get("input-messages") or []
    state = "info"
    title = "Codex turn complete"
    body_lines = [
        f"thread={payload.get('thread-id', '')}",
        f"turn={payload.get('turn-id', '')}",
        f"cwd={payload.get('cwd', '')}",
        "prompt=" + " ".join(str(item) for item in prompt_messages),
        "assistant=" + str(last_message),
    ]
    notify_args = argparse.Namespace(
        url=os.getenv("CODEX_NTFY_URL", os.getenv("NTFY_URL", "")),
        topic=topic_for_state(state),
        title=title,
        message="\n".join(body_lines),
        state=state,
        severity=None,
        app_name="codex",
        host=os.getenv("CODEX_NTFY_HOST"),
        facility=16,
        tag=["codex", "turn-complete"],
        actions_json=None,
        click=None,
        token=os.getenv("CODEX_NTFY_TOKEN", os.getenv("NTFY_TOKEN", "")),
        username=None,
        password=None,
        priority=None,
        allow_missing_config=True,
        dry_run=args.dry_run,
        output="json",
    )
    payload_data = ntfy_notify.build_payload(notify_args)
    if not payload_data["topic"] or not payload_data["url"]:
        if args.dry_run:
            missing = "topic" if not payload_data["topic"] else "URL"
            print(
                json.dumps(
                    {"skipped": True, "reason": f"missing {missing} configuration"}, indent=2
                )
            )
        return 0
    if args.dry_run:
        print(json.dumps(payload_data, indent=2, sort_keys=True))
        return 0
    try:
        result = ntfy_notify.send_payload(payload_data)
    except Exception:  # noqa: BLE001
        return 0
    print(json.dumps({"ok": True, "result": result}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
