#!/usr/bin/env python3
"""Persist ntfy reply-topic messages into a local normalized queue."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections import deque
from pathlib import Path
from urllib import error, parse, request

REPO_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO_ROOT))

import codex_ntfy_reply_queue as reply_queue  # noqa: E402

MAX_SEEN_IDS = 512


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--state-file",
        default=str(Path.home() / ".codex/ntfy-reply-listener-state.json"),
    )
    parser.add_argument("--poll-interval", type=float, default=1.0)
    parser.add_argument("--from-start", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def ntfy_base_url() -> str:
    return os.getenv(
        "CODEX_NTFY_URL",
        os.getenv("NTFY_URL", os.getenv("NTFY_SERVER", "")),
    ).rstrip("/")


def ntfy_reply_topic() -> str:
    return os.getenv("CODEX_NTFY_REPLY_TOPIC", os.getenv("NTFY_REPLY_TOPIC", ""))


def ntfy_token() -> str:
    return os.getenv("CODEX_NTFY_TOKEN", os.getenv("NTFY_TOKEN", ""))


def auth_headers() -> dict[str, str]:
    token = ntfy_token()
    return {"Authorization": f"Bearer {token}"} if token else {}


def load_state(path: Path) -> dict:
    if not path.exists():
        return {"since": 0, "seen_ids": []}
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"since": 0, "seen_ids": []}
    state.setdefault("since", 0)
    state.setdefault("seen_ids", [])
    return state


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def iter_test_messages() -> list[dict]:
    raw = os.getenv("CODEX_NTFY_REPLY_LISTENER_TEST_MESSAGES", "")
    base_ts = int(time.time())
    messages: list[dict] = []
    for offset, line in enumerate(raw.splitlines()):
        stripped = line.strip()
        if not stripped:
            continue
        messages.append(
            {
                "id": reply_queue.synthetic_message_id(),
                "time": base_ts + offset,
                "topic": ntfy_reply_topic(),
                "message": stripped,
            }
        )
    return messages


def poll_topic(since_ts: int) -> tuple[int, list[dict]]:
    topic = ntfy_reply_topic()
    query = parse.urlencode({"poll": "1", "since": str(since_ts)})
    url = f"{ntfy_base_url()}/{topic}/json?{query}"
    req = request.Request(url, headers=auth_headers(), method="GET")
    with request.urlopen(req, timeout=60) as response:  # noqa: S310
        raw = response.read().decode("utf-8", errors="replace")
    newest_ts = since_ts
    messages: list[dict] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        newest_ts = max(newest_ts, int(event.get("time", since_ts)))
        if event.get("event") == "message":
            messages.append(event)
    return newest_ts, messages


def process_messages(messages: list[dict], state: dict, *, dry_run: bool) -> int:
    seen_ids = deque(state.get("seen_ids", []), maxlen=MAX_SEEN_IDS)
    seen_lookup = set(seen_ids)
    processed = 0
    for event in messages:
        message_id = str(event.get("id") or reply_queue.synthetic_message_id())
        if message_id in seen_lookup:
            continue
        payload = reply_queue.normalize_reply_message(
            str(event.get("message", "")),
            message_id=message_id,
            timestamp=int(event.get("time", int(time.time()))),
            topic=str(event.get("topic", ntfy_reply_topic())),
        )
        seen_ids.append(message_id)
        seen_lookup.add(message_id)
        if not payload:
            continue
        if dry_run:
            print(json.dumps(payload, indent=2, sort_keys=True))
        else:
            reply_queue.enqueue_reply(payload)
        processed += 1
    state["seen_ids"] = list(seen_ids)
    return processed


def main() -> int:
    args = parse_args()
    if not ntfy_reply_topic():
        print("ERROR: CODEX_NTFY_REPLY_TOPIC/NTFY_REPLY_TOPIC is not configured", file=sys.stderr)
        return 2
    if not ntfy_base_url() and not os.getenv("CODEX_NTFY_REPLY_LISTENER_TEST_MESSAGES"):
        print("ERROR: CODEX_NTFY_URL/NTFY_URL/NTFY_SERVER is not configured", file=sys.stderr)
        return 2

    state_path = Path(args.state_file)
    state = load_state(state_path)
    if not args.from_start and not state.get("since"):
        state["since"] = int(time.time())
    reply_queue.ensure_queue_dirs()

    while True:
        try:
            if os.getenv("CODEX_NTFY_REPLY_LISTENER_TEST_MESSAGES"):
                newest_ts = int(time.time())
                messages = iter_test_messages()
            else:
                newest_ts, messages = poll_topic(int(state.get("since", 0)))
        except error.URLError as exc:
            print(f"WARNING: ntfy reply poll failed: {exc}", file=sys.stderr)
            if args.once:
                return 1
            time.sleep(args.poll_interval)
            continue

        state["since"] = max(int(state.get("since", 0)), newest_ts)
        process_messages(messages, state, dry_run=args.dry_run)
        if not args.dry_run:
            save_state(state_path, state)

        if args.once:
            return 0
        time.sleep(args.poll_interval)


if __name__ == "__main__":
    raise SystemExit(main())
