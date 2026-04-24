#!/usr/bin/env python3
"""Watch Codex TUI logs and publish ntfy alerts for sandbox approval prompts."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from collections import deque
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO_ROOT))

import ntfy_notify  # noqa: E402

TOOLCALL_EXEC_RE = re.compile(r"ToolCall: exec_command (\{.*\}) thread_id=(\S+)")
TOOLCALL_PATCH_RE = re.compile(r"ToolCall: apply_patch\b")
EXEC_APPROVAL_RE = re.compile(r'op.dispatch\.exec_approval".*submission.id="([^"]+)"')
PATCH_APPROVAL_RE = re.compile(r'op.dispatch\.patch_approval".*submission.id="([^"]+)"')
TS_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}T[^\s]+)")
MAX_QUEUE = 32


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log-file", default=str(Path.home() / ".codex/log/codex-tui.log"))
    parser.add_argument("--state-file", default=str(Path.home() / ".codex/approval-watcher-state.json"))
    parser.add_argument("--poll-interval", type=float, default=1.0)
    parser.add_argument("--from-start", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def base_url() -> str:
    return os.getenv("CODEX_NTFY_URL", os.getenv("NTFY_URL", "https://ntfy.sh"))


def alert_topic() -> str:
    return (
        os.getenv("CODEX_NTFY_ALERT_TOPIC")
        or os.getenv("CODEX_NTFY_TOPIC_ACTION_REQUIRED")
        or os.getenv("CODEX_NTFY_TOPIC")
        or os.getenv("NTFY_ALERT_TOPIC")
        or os.getenv("NTFY_TOPIC", "")
    )


def token() -> str:
    return os.getenv("CODEX_NTFY_TOKEN", os.getenv("NTFY_TOKEN", ""))


def load_state(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def line_timestamp(line: str) -> str:
    match = TS_RE.match(line)
    return match.group(1) if match else ""


def trim_command(command: str, limit: int = 1200) -> str:
    command = command.strip()
    return command if len(command) <= limit else command[: limit - 3] + "..."


def notify(title: str, message: str, tags: list[str], *, dry_run: bool) -> int:
    notify_args = argparse.Namespace(
        url=base_url(),
        topic=alert_topic(),
        title=title,
        message=message,
        state="action-required",
        severity=None,
        app_name="codex-approval",
        host=os.getenv("CODEX_NTFY_HOST"),
        facility=16,
        tag=tags,
        actions_json=None,
        click=None,
        token=token(),
        username=None,
        password=None,
        priority="5",
        allow_missing_config=True,
        dry_run=dry_run,
        output="json",
    )
    payload = ntfy_notify.build_payload(notify_args)
    if not payload["topic"]:
        return 0
    if dry_run:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0
    try:
        ntfy_notify.send_payload(payload)
    except Exception:  # noqa: BLE001
        return 1
    return 0


def render_exec_message(event: dict, submission_id: str) -> str:
    lines = [
        f"submission={submission_id}",
        f"thread={event.get('thread_id', '')}",
        f"time={event.get('timestamp', '')}",
    ]
    justification = event.get("justification", "").strip()
    if justification:
        lines.append(f"justification={justification}")
    lines.extend(
        [
            "",
            "command:",
            trim_command(event.get("cmd", "")),
            "",
            "Approve this request in the Codex UI.",
            "Remote ntfy replies are not wired into sandbox approval dialogs in this runtime.",
        ]
    )
    return "\n".join(lines)


def render_patch_message(timestamp: str, submission_id: str) -> str:
    return "\n".join(
        [
            f"submission={submission_id}",
            f"time={timestamp}",
            "",
            "A patch approval dialog is waiting in the Codex UI.",
            "Approve or deny it locally in the active session.",
        ]
    )


def file_identity(path: Path) -> dict:
    stat = path.stat()
    return {"inode": stat.st_ino, "dev": stat.st_dev, "offset": stat.st_size}


def open_at_saved_offset(path: Path, state: dict, from_start: bool) -> tuple[object, dict]:
    stat = path.stat()
    saved = load_state(Path(state["state_file"]))
    use_saved = (
        saved.get("inode") == stat.st_ino
        and saved.get("dev") == stat.st_dev
        and isinstance(saved.get("offset"), int)
        and saved["offset"] <= stat.st_size
    )
    fh = path.open("r", encoding="utf-8", errors="replace")
    if from_start:
        fh.seek(0)
    elif use_saved:
        fh.seek(saved["offset"])
    else:
        fh.seek(0, os.SEEK_END)
    runtime_state = {
        "inode": stat.st_ino,
        "dev": stat.st_dev,
        "offset": fh.tell(),
        "state_file": state["state_file"],
    }
    return fh, runtime_state


def process_line(
    line: str,
    *,
    pending_exec: deque[dict],
    pending_patch: deque[dict],
    dry_run: bool,
) -> None:
    ts = line_timestamp(line)
    exec_match = TOOLCALL_EXEC_RE.search(line)
    if exec_match:
        payload = json.loads(exec_match.group(1))
        if payload.get("sandbox_permissions") == "require_escalated":
            pending_exec.append(
                {
                    "timestamp": ts,
                    "thread_id": exec_match.group(2),
                    "cmd": str(payload.get("cmd", "")),
                    "justification": str(payload.get("justification", "")),
                }
            )
            while len(pending_exec) > MAX_QUEUE:
                pending_exec.popleft()
        return

    if TOOLCALL_PATCH_RE.search(line):
        pending_patch.append({"timestamp": ts})
        while len(pending_patch) > MAX_QUEUE:
            pending_patch.popleft()
        return

    approval_match = EXEC_APPROVAL_RE.search(line)
    if approval_match:
        if pending_exec:
            event = pending_exec.popleft()
            notify(
                "Codex exec approval needed",
                render_exec_message(event, approval_match.group(1)),
                ["codex", "approval", "exec-command"],
                dry_run=dry_run,
            )
        else:
            notify(
                "Codex exec approval needed",
                render_patch_message(ts, approval_match.group(1)),
                ["codex", "approval", "exec-command"],
                dry_run=dry_run,
            )
        return

    patch_match = PATCH_APPROVAL_RE.search(line)
    if patch_match:
        event = pending_patch.popleft() if pending_patch else {"timestamp": ts}
        notify(
            "Codex patch approval needed",
            render_patch_message(event.get("timestamp", ts), patch_match.group(1)),
            ["codex", "approval", "apply-patch"],
            dry_run=dry_run,
        )


def main() -> int:
    args = parse_args()
    log_path = Path(args.log_file)
    state_file = Path(args.state_file)
    if not log_path.exists():
        print(f"ERROR: log file not found: {log_path}", file=sys.stderr)
        return 2

    pending_exec: deque[dict] = deque()
    pending_patch: deque[dict] = deque()
    state_seed = {"state_file": str(state_file)}
    fh, runtime_state = open_at_saved_offset(log_path, state_seed, args.from_start)

    try:
        while True:
            line = fh.readline()
            if line:
                runtime_state["offset"] = fh.tell()
                process_line(
                    line,
                    pending_exec=pending_exec,
                    pending_patch=pending_patch,
                    dry_run=args.dry_run,
                )
                continue
            save_state(state_file, runtime_state)
            if args.once:
                break
            time.sleep(args.poll_interval)
    finally:
        save_state(state_file, runtime_state)
        fh.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
