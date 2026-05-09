#!/usr/bin/env python3
"""Codex hook bridge for ntfy-based approvals and replies."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import uuid
from collections.abc import Iterator
from pathlib import Path
from urllib import error, parse, request

REPO_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO_ROOT))

import codex_ntfy_policy as reply_policy  # noqa: E402
import codex_ntfy_reply_queue as reply_queue  # noqa: E402
import ntfy_notify  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def ntfy_base_url() -> str:
    return os.getenv(
        "CODEX_NTFY_URL",
        os.getenv("NTFY_URL", os.getenv("NTFY_SERVER", "")),
    ).rstrip("/")


def ntfy_alert_topic() -> str:
    return (
        os.getenv("CODEX_NTFY_ALERT_TOPIC")
        or os.getenv("CODEX_NTFY_TOPIC_ACTION_REQUIRED")
        or os.getenv("CODEX_NTFY_TOPIC")
        or os.getenv("NTFY_ALERT_TOPIC")
        or os.getenv("NTFY_TOPIC", "")
    )


def ntfy_reply_topic() -> str:
    return os.getenv("CODEX_NTFY_REPLY_TOPIC", os.getenv("NTFY_REPLY_TOPIC", ""))


def ntfy_token() -> str:
    return os.getenv("CODEX_NTFY_TOKEN", os.getenv("NTFY_TOKEN", ""))


def wait_secs() -> int:
    return int(os.getenv("CODEX_NTFY_WAIT_SECS", os.getenv("NTFY_WAIT_SECS", "300")))


def auth_headers() -> dict[str, str]:
    token = ntfy_token()
    return {"Authorization": f"Bearer {token}"} if token else {}


def publish_message(
    state: str,
    title: str,
    message: str,
    tags: list[str],
    *,
    priority: str | None = None,
    dry_run: bool = False,
) -> int:
    notify_args = argparse.Namespace(
        url=ntfy_base_url(),
        topic=ntfy_alert_topic(),
        title=title,
        message=message,
        state=state,
        severity=None,
        app_name="codex-hook",
        host=os.getenv("CODEX_NTFY_HOST"),
        facility=16,
        tag=tags,
        actions_json=None,
        click=None,
        token=ntfy_token(),
        username=None,
        password=None,
        priority=priority,
        allow_missing_config=True,
        dry_run=dry_run,
        output="json",
    )
    payload_data = ntfy_notify.build_payload(notify_args)
    if not payload_data["topic"] or not payload_data["url"]:
        return 0
    if dry_run:
        print(json.dumps(payload_data, indent=2, sort_keys=True))
        return 0
    try:
        ntfy_notify.send_payload(payload_data)
    except Exception:  # noqa: BLE001
        return 0
    return 0


def poll_replies(since_ts: int, wait_timeout: int) -> Iterator[str]:
    if os.getenv("CODEX_NTFY_TEST_REPLIES"):
        for line in os.getenv("CODEX_NTFY_TEST_REPLIES", "").splitlines():
            line = line.strip()
            if line:
                yield line
        return

    topic = ntfy_reply_topic()
    if not topic or not ntfy_base_url():
        return

    end_time = time.time() + wait_timeout
    current_since = since_ts
    seen_ids: set[str] = set()
    while time.time() < end_time:
        query = parse.urlencode({"poll": "1", "since": str(current_since)})
        url = f"{ntfy_base_url()}/{topic}/json?{query}"
        req = request.Request(url, headers=auth_headers(), method="GET")
        try:
            with request.urlopen(req, timeout=min(wait_timeout, 60)) as response:  # noqa: S310
                raw = response.read().decode("utf-8", errors="replace")
        except error.URLError:
            time.sleep(2)
            continue
        newest_ts = current_since
        for line in raw.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            newest_ts = max(newest_ts, int(event.get("time", current_since)))
            if event.get("event") != "message":
                continue
            msg_id = event.get("id")
            if msg_id and msg_id in seen_ids:
                continue
            if msg_id:
                seen_ids.add(msg_id)
            message = str(event.get("message", "")).strip()
            if message:
                yield message
        current_since = newest_ts
        time.sleep(0.5)


def poll_queue_reply(request_id: str, *, expected_kind: str, wait_timeout: int) -> dict | None:
    if not reply_queue.queue_available():
        return None
    end_time = time.time() + wait_timeout
    while time.time() < end_time:
        found = reply_queue.find_reply(
            request_id,
            expected_kind=expected_kind,
        )
        if found:
            path, payload = found
            mode = reply_policy.mode_for_kind(str(payload.get("kind", expected_kind)))
            reply_queue.mark_processed(path)
            payload["policy_mode"] = mode
            return payload
        time.sleep(0.5)
    return None


def reply_queue_enabled() -> bool:
    return reply_queue.queue_available()


def advisory_message(reply_payload: dict, *, context: str) -> str:
    policy_mode = reply_payload.get(
        "policy_mode",
        reply_policy.mode_for_kind(str(reply_payload.get("kind", ""))),
    )
    return "\n".join(
        [
            f"context={context}",
            f"request_id={reply_payload.get('request_id', '')}",
            f"kind={reply_payload.get('kind', '')}",
            f"mode={policy_mode}",
            "",
            "reply:",
            str(reply_payload.get("raw_message", "")).strip(),
            "",
            "Policy marked this reply as advisory. No automatic state change was applied.",
        ]
    )


def maybe_publish_advisory(reply_payload: dict, *, context: str, dry_run: bool) -> None:
    if reply_payload.get("policy_mode") != "advisory":
        return
    publish_message(
        "notice",
        f"Codex advisory reply received: {context}",
        advisory_message(reply_payload, context=context),
        ["codex", "reply", "advisory"],
        priority="3",
        dry_run=dry_run,
    )


def permission_command(payload: dict) -> str:
    tool_input = payload.get("tool_input") or {}
    if isinstance(tool_input, dict):
        return str(tool_input.get("command") or payload.get("tool_input.command") or "")
    return str(payload.get("tool_input.command") or "")


def permission_description(payload: dict) -> str:
    tool_input = payload.get("tool_input") or {}
    if isinstance(tool_input, dict):
        return str(tool_input.get("description") or payload.get("tool_input.description") or "")
    return str(payload.get("tool_input.description") or "")


def handle_permission_request(payload: dict, *, dry_run: bool) -> int:
    request_id = os.getenv("CODEX_NTFY_TEST_REQUEST_ID", uuid.uuid4().hex[:8])
    started = int(time.time())
    body = "\n".join(
        [
            f"id: {request_id}",
            f"description: {permission_description(payload)}",
            "command:",
            permission_command(payload),
            "",
            f"reply_topic: {ntfy_reply_topic()}",
            f"allow {request_id}",
            f"deny {request_id}",
        ]
    )
    publish_message(
        "action-required",
        "Codex approval needed",
        body,
        ["codex", "approval"],
        priority="5",
        dry_run=dry_run,
    )
    if dry_run or not ntfy_reply_topic():
        return 0
    if reply_queue_enabled():
        queued_reply = poll_queue_reply(
            request_id,
            expected_kind="permission_reply",
            wait_timeout=min(wait_secs(), 5),
        )
        if queued_reply:
            if queued_reply.get("policy_mode") == "advisory":
                maybe_publish_advisory(queued_reply, context="PermissionRequest", dry_run=dry_run)
                return 0
            if queued_reply.get("decision") == "allow":
                print(
                    json.dumps(
                        {
                            "hookSpecificOutput": {
                                "hookEventName": "PermissionRequest",
                                "decision": {"behavior": "allow"},
                            }
                        }
                    )
                )
                return 0
            if queued_reply.get("decision") == "deny":
                print(
                    json.dumps(
                        {
                            "hookSpecificOutput": {
                                "hookEventName": "PermissionRequest",
                                "decision": {
                                    "behavior": "deny",
                                    "message": "Denied via ntfy reply",
                                },
                            }
                        }
                    )
                )
                return 0
    for reply in poll_replies(started, wait_secs()):
        normalized = reply_queue.normalize_reply_message(
            reply,
            message_id=reply_queue.synthetic_message_id(),
            timestamp=int(time.time()),
            topic=ntfy_reply_topic(),
        )
        if not normalized:
            continue
        normalized["policy_mode"] = reply_policy.mode_for_kind(str(normalized.get("kind", "")))
        if normalized.get("policy_mode") == "advisory":
            maybe_publish_advisory(normalized, context="PermissionRequest", dry_run=dry_run)
            return 0
        if (
            normalized.get("kind") == "permission_reply"
            and normalized.get("request_id") == request_id
            and normalized.get("decision") == "allow"
        ):
            print(
                json.dumps(
                    {
                        "hookSpecificOutput": {
                            "hookEventName": "PermissionRequest",
                            "decision": {"behavior": "allow"},
                        }
                    }
                )
            )
            return 0
        if (
            normalized.get("kind") == "permission_reply"
            and normalized.get("request_id") == request_id
            and normalized.get("decision") == "deny"
        ):
            print(
                json.dumps(
                    {
                        "hookSpecificOutput": {
                            "hookEventName": "PermissionRequest",
                            "decision": {"behavior": "deny", "message": "Denied via ntfy reply"},
                        }
                    }
                )
            )
            return 0
    return 0


def handle_stop(payload: dict, *, dry_run: bool) -> int:
    if payload.get("stop_hook_active"):
        return 0
    last_message = str(
        payload.get("last_assistant_message") or payload.get("last-assistant-message") or ""
    ).strip()
    if not last_message or "?" not in last_message:
        return 0
    request_id = os.getenv("CODEX_NTFY_TEST_REQUEST_ID", uuid.uuid4().hex[:8])
    started = int(time.time())
    body = "\n".join(
        [
            f"id: {request_id}",
            "",
            last_message,
            "",
            f"reply_topic: {ntfy_reply_topic()}",
            f"{request_id}: <your answer>",
        ]
    )
    publish_message(
        "action-required",
        "Codex is asking for input",
        body,
        ["codex", "question"],
        priority="4",
        dry_run=dry_run,
    )
    if dry_run or not ntfy_reply_topic():
        return 0
    if reply_queue_enabled():
        queued_reply = poll_queue_reply(
            request_id,
            expected_kind="question_reply",
            wait_timeout=min(wait_secs(), 5),
        )
        if queued_reply and queued_reply.get("policy_mode") == "advisory":
            maybe_publish_advisory(queued_reply, context="Stop", dry_run=dry_run)
            return 0
        if queued_reply and queued_reply.get("answer"):
            print(json.dumps({"decision": "block", "reason": queued_reply["answer"]}))
            return 0
    for reply in poll_replies(started, wait_secs()):
        normalized = reply_queue.normalize_reply_message(
            reply,
            message_id=reply_queue.synthetic_message_id(),
            timestamp=int(time.time()),
            topic=ntfy_reply_topic(),
        )
        if normalized:
            normalized["policy_mode"] = reply_policy.mode_for_kind(str(normalized.get("kind", "")))
        if normalized and normalized.get("policy_mode") == "advisory":
            maybe_publish_advisory(normalized, context="Stop", dry_run=dry_run)
            return 0
        if (
            normalized
            and normalized.get("kind") == "question_reply"
            and normalized.get("request_id") == request_id
            and normalized.get("answer")
        ):
            print(json.dumps({"decision": "block", "reason": normalized["answer"]}))
            return 0
    return 0


def main() -> int:
    args = parse_args()
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    event = payload.get("hook_event_name")
    direct_ntfy_configured = bool(ntfy_base_url() and (ntfy_alert_topic() or ntfy_reply_topic()))
    if not (direct_ntfy_configured or reply_queue_enabled()):
        return 0
    if event == "PermissionRequest":
        return handle_permission_request(payload, dry_run=args.dry_run)
    if event == "Stop":
        return handle_stop(payload, dry_run=args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
