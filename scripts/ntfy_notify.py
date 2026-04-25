#!/usr/bin/env python3
"""Send structured notifications to ntfy-compatible HTTP endpoints."""

from __future__ import annotations

import argparse
import base64
import json
import os
import platform
import socket
import sys
from datetime import UTC, datetime
from typing import Any
from urllib import error, request

SYSLOG_SEVERITIES = {
    "emerg": 0,
    "alert": 1,
    "crit": 2,
    "err": 3,
    "error": 3,
    "warning": 4,
    "warn": 4,
    "notice": 5,
    "info": 6,
    "debug": 7,
}
SEVERITY_NAMES = {
    0: "emerg",
    1: "alert",
    2: "crit",
    3: "err",
    4: "warning",
    5: "notice",
    6: "info",
    7: "debug",
}
NTFY_PRIORITY_MAP = {
    0: "5",
    1: "5",
    2: "4",
    3: "4",
    4: "3",
    5: "3",
    6: "2",
    7: "1",
}
STATE_TAGS = {
    "success": ["white_check_mark"],
    "fail": ["x"],
    "error": ["rotating_light"],
    "warning": ["warning"],
    "notice": ["information_source"],
    "info": ["information_source"],
    "debug": ["lady_beetle"],
    "action-required": ["warning", "triangular_flag_on_post"],
    "start": ["rocket"],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url")
    parser.add_argument("--topic")
    parser.add_argument("--title")
    parser.add_argument("--message", required=True)
    parser.add_argument("--state", default="info")
    parser.add_argument("--severity")
    parser.add_argument("--app-name", default="codex")
    parser.add_argument("--host")
    parser.add_argument("--facility", type=int, default=16, help="Syslog facility number")
    parser.add_argument("--tag", action="append", default=[])
    parser.add_argument("--actions-json")
    parser.add_argument("--click")
    parser.add_argument("--token")
    parser.add_argument("--username")
    parser.add_argument("--password")
    parser.add_argument("--priority")
    parser.add_argument("--allow-missing-config", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--output", choices=("json", "body"), default="json")
    return parser.parse_args()


def normalize_state_key(value: str) -> str:
    return value.strip().replace("-", "_").replace(" ", "_").upper()


def resolve_topic(cli_topic: str | None, state: str) -> str:
    if cli_topic:
        return cli_topic
    state_key = normalize_state_key(state)
    return os.getenv(f"NTFY_TOPIC_{state_key}") or os.getenv("NTFY_TOPIC", "")


def resolve_url(cli_url: str | None) -> str:
    return cli_url or os.getenv("NTFY_URL", "https://ntfy.sh")


def resolve_token(cli_token: str | None) -> str:
    return cli_token or os.getenv("NTFY_TOKEN", "")


def resolve_basic_auth(username: str | None, password: str | None) -> str:
    resolved_user = username or os.getenv("NTFY_USERNAME", "")
    resolved_password = password or os.getenv("NTFY_PASSWORD", "")
    if not resolved_user:
        return ""
    return base64.b64encode(f"{resolved_user}:{resolved_password}".encode()).decode("ascii")


def severity_for_state(state: str, explicit: str | None) -> int:
    if explicit:
        key = explicit.lower()
        if key not in SYSLOG_SEVERITIES:
            raise ValueError(f"Unsupported severity: {explicit}")
        return SYSLOG_SEVERITIES[key]
    if state in {"success"}:
        return SYSLOG_SEVERITIES["notice"]
    if state in {"fail", "error", "action-required"}:
        return SYSLOG_SEVERITIES["err"]
    if state in {"warning"}:
        return SYSLOG_SEVERITIES["warning"]
    if state in {"debug"}:
        return SYSLOG_SEVERITIES["debug"]
    return SYSLOG_SEVERITIES["info"]


def render_syslog_body(
    *,
    facility: int,
    severity: int,
    host: str,
    app_name: str,
    state: str,
    message: str,
) -> str:
    pri = facility * 8 + severity
    timestamp = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    sanitized_message = " ".join(message.splitlines()).replace('"', "'")
    return (
        f"<{pri}>1 {timestamp} {host} {app_name} {os.getpid()} - - "
        f'state="{state}" severity="{SEVERITY_NAMES[severity]}" '
        f'severity_code="{severity}" message="{sanitized_message}"'
    )


def parse_actions(actions_json: str | None) -> list[dict[str, Any]] | None:
    if not actions_json:
        return None
    parsed = json.loads(actions_json)
    if not isinstance(parsed, list):
        raise ValueError("--actions-json must decode to a JSON array")
    return parsed


def build_payload(args: argparse.Namespace) -> dict[str, Any]:
    state = args.state.strip().lower()
    host = args.host or os.getenv("NTFY_HOST", socket.gethostname())
    topic = resolve_topic(args.topic, state)
    url = resolve_url(args.url)
    token = resolve_token(args.token)
    basic_auth = resolve_basic_auth(args.username, args.password)
    severity = severity_for_state(state, args.severity)
    priority = args.priority or NTFY_PRIORITY_MAP[severity]
    tags = [tag for tag in args.tag if tag]
    for default_tag in STATE_TAGS.get(state, []):
        if default_tag not in tags:
            tags.append(default_tag)
    app_slug = args.app_name.replace(" ", "-").lower()
    if app_slug not in tags:
        tags.append(app_slug)
    body = render_syslog_body(
        facility=args.facility,
        severity=severity,
        host=host,
        app_name=args.app_name,
        state=state,
        message=args.message,
    )
    title = args.title or f"{args.app_name}: {state}"
    headers = {
        "Title": title,
        "Priority": str(priority),
        "Tags": ",".join(tags),
        "X-Markdown": "no",
        "User-Agent": f"{args.app_name}/{platform.node() or 'unknown'}",
    }
    if args.click:
        headers["Click"] = args.click
    if token:
        headers["Authorization"] = f"Bearer {token}"
    elif basic_auth:
        headers["Authorization"] = f"Basic {basic_auth}"
    actions = parse_actions(args.actions_json)
    if actions is not None:
        headers["Actions"] = json.dumps(actions, separators=(",", ":"))
    return {
        "state": state,
        "topic": topic,
        "url": url.rstrip("/"),
        "headers": headers,
        "body": body,
        "severity": severity,
        "severity_name": SEVERITY_NAMES[severity],
    }


def send_payload(payload: dict[str, Any]) -> dict[str, Any]:
    endpoint = f"{payload['url']}/{payload['topic']}"
    req = request.Request(
        endpoint,
        data=payload["body"].encode("utf-8"),
        headers=payload["headers"],
        method="POST",
    )
    with request.urlopen(req, timeout=15) as response:  # noqa: S310
        raw = response.read().decode("utf-8")
        return json.loads(raw) if raw else {"status": response.status}


def main() -> int:
    args = parse_args()
    try:
        payload = build_payload(args)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if not payload["topic"]:
        if args.allow_missing_config:
            print(
                json.dumps(
                    {
                        "skipped": True,
                        "reason": "missing topic configuration",
                        "state": payload["state"],
                    },
                    indent=2,
                    sort_keys=True,
                )
            )
            return 0
        print("ERROR: ntfy topic is not configured", file=sys.stderr)
        return 2

    if args.dry_run:
        if args.output == "body":
            print(payload["body"])
        else:
            print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    try:
        result = send_payload(payload)
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        print(f"ERROR: ntfy HTTP {exc.code}: {detail}", file=sys.stderr)
        return 1
    except error.URLError as exc:
        print(f"ERROR: ntfy transport failed: {exc}", file=sys.stderr)
        return 1

    if args.output == "body":
        print(payload["body"])
    else:
        print(
            json.dumps(
                {"ok": True, "result": result, "topic": payload["topic"]}, indent=2, sort_keys=True
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
