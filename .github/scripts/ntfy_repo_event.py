#!/usr/bin/env python3
"""Format GitHub event payloads into ntfy notifications."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import ntfy_notify  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-name", default=os.getenv("GITHUB_EVENT_NAME", ""))
    parser.add_argument("--event-path", default=os.getenv("GITHUB_EVENT_PATH", ""))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--url")
    parser.add_argument("--topic")
    parser.add_argument("--allow-missing-config", action="store_true")
    return parser.parse_args()


def load_payload(path: str) -> dict:
    if not path:
        return {}
    return json.loads(Path(path).read_text(encoding="utf-8"))


def repo_name(payload: dict) -> str:
    return payload.get("repository", {}).get(
        "full_name", os.getenv("GITHUB_REPOSITORY", "unknown/repo")
    )


def html_url(payload: dict) -> str:
    return payload.get("repository", {}).get("html_url", "")


def severity_state(severity: str) -> str:
    if severity == "err":
        return "error"
    return severity


def event_details(event_name: str, payload: dict) -> tuple[str, str, str, list[str]]:
    repo = repo_name(payload)
    if event_name == "push":
        ref = payload.get("ref", "")
        branch = ref.removeprefix("refs/heads/")
        commits = payload.get("commits", [])
        title = f"Git push: {repo}:{branch}"
        message = (
            f"pusher={payload.get('pusher', {}).get('name', 'unknown')} "
            f"commits={len(commits)} before={payload.get('before', '')} after={payload.get('after', '')} "
            f"url={html_url(payload)}/compare/{payload.get('before', '')}...{payload.get('after', '')}"
        )
        return "notice", title, message, ["git", "push"]
    if event_name == "create":
        ref_type = payload.get("ref_type", "ref")
        ref = payload.get("ref", "")
        return (
            "notice",
            f"Git create: {repo}:{ref}",
            f"type={ref_type} ref={ref}",
            ["git", "create"],
        )
    if event_name == "delete":
        ref_type = payload.get("ref_type", "ref")
        ref = payload.get("ref", "")
        return (
            "warning",
            f"Git delete: {repo}:{ref}",
            f"type={ref_type} ref={ref}",
            ["git", "delete"],
        )
    if event_name == "pull_request":
        pr = payload.get("pull_request", {})
        action = payload.get("action", "updated")
        merged = pr.get("merged", False)
        if action == "closed" and merged:
            severity = "notice"
            action_label = "merged"
        elif action in {"opened", "reopened", "ready_for_review"}:
            severity = "notice"
            action_label = action
        elif action in {"edited", "synchronize", "converted_to_draft"}:
            severity = "info"
            action_label = action
        else:
            severity = "warning"
            action_label = action
        title = f"PR {action_label}: #{pr.get('number')} {pr.get('title', '')}".strip()
        message = (
            f"repo={repo} actor={payload.get('sender', {}).get('login', 'unknown')} "
            f"base={pr.get('base', {}).get('ref', '')} head={pr.get('head', {}).get('ref', '')} "
            f"url={pr.get('html_url', html_url(payload))}"
        )
        return severity, title, message, ["github", "pull_request", action_label]
    if event_name == "release":
        release = payload.get("release", {})
        action = payload.get("action", "released")
        severity = "notice" if action in {"published", "released", "prereleased"} else "info"
        title = f"Release {action}: {release.get('tag_name', '')}".strip()
        message = (
            f"repo={repo} name={release.get('name', '')} author={release.get('author', {}).get('login', 'unknown')} "
            f"url={release.get('html_url', html_url(payload))}"
        )
        return severity, title, message, ["github", "release", action]
    if event_name == "workflow_run":
        run = payload.get("workflow_run", {})
        conclusion = run.get("conclusion", "unknown")
        severity = "notice" if conclusion == "success" else "err"
        title = f"Workflow {conclusion}: {run.get('name', '')}".strip()
        message = (
            f"repo={repo} event={run.get('event', '')} branch={run.get('head_branch', '')} "
            f"url={run.get('html_url', html_url(payload))}"
        )
        return severity, title, message, ["github", "workflow", conclusion]
    return "info", f"GitHub event: {event_name}", f"repo={repo}", ["github", event_name]


def main() -> int:
    args = parse_args()
    payload = load_payload(args.event_path)
    severity, title, message, tags = event_details(args.event_name, payload)
    notify_args = argparse.Namespace(
        url=args.url,
        topic=args.topic,
        title=title,
        message=message,
        state=severity_state(severity),
        severity=severity,
        app_name="github",
        host="github-actions",
        facility=16,
        tag=tags,
        actions_json=None,
        click=payload.get("pull_request", {}).get("html_url")
        or payload.get("release", {}).get("html_url")
        or payload.get("workflow_run", {}).get("html_url")
        or html_url(payload),
        token=None,
        username=None,
        password=None,
        priority=None,
        allow_missing_config=args.allow_missing_config,
        dry_run=args.dry_run,
        output="json",
    )
    payload_data = ntfy_notify.build_payload(notify_args)
    if not payload_data["topic"] and args.allow_missing_config:
        print(json.dumps({"skipped": True, "reason": "missing topic configuration"}, indent=2))
        return 0
    if args.dry_run:
        print(json.dumps(payload_data, indent=2, sort_keys=True))
        return 0
    try:
        result = ntfy_notify.send_payload(payload_data)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"ok": True, "result": result}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
