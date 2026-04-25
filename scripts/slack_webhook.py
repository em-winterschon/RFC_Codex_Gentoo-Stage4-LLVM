#!/usr/bin/env python3
"""Send messages to Slack incoming webhooks."""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any
from urllib import error, request


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("message", help="Message text to send")
    parser.add_argument("--webhook-url", default=os.getenv("SLACK_WEBHOOK_URL", ""))
    parser.add_argument("--title", help="Optional title rendered above the message")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def build_payload(message: str, *, title: str | None = None) -> dict[str, Any]:
    text = message.strip()
    if title:
        text = f"*{title.strip()}*\n{text}"
    return {"text": text}


def send_payload(webhook_url: str, payload: dict[str, Any]) -> dict[str, Any]:
    req = request.Request(
        webhook_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "codex-slack-webhook"},
        method="POST",
    )
    with request.urlopen(req, timeout=15) as response:  # noqa: S310
        raw = response.read().decode("utf-8", errors="replace")
        return {"status": response.status, "body": raw}


def main() -> int:
    args = parse_args()
    payload = build_payload(args.message, title=args.title)
    if not args.webhook_url:
        print("ERROR: Slack webhook URL is not configured", file=sys.stderr)
        return 2
    if args.dry_run:
        print(
            json.dumps(
                {"webhook_url": args.webhook_url, "payload": payload}, indent=2, sort_keys=True
            )
        )
        return 0
    try:
        result = send_payload(args.webhook_url, payload)
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        print(f"ERROR: slack HTTP {exc.code}: {detail}", file=sys.stderr)
        return 1
    except error.URLError as exc:
        print(f"ERROR: slack transport failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"ok": True, "result": result}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
