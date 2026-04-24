#!/usr/bin/env python3
"""Minimal curses pub/sub client for ntfy topics."""

from __future__ import annotations

import argparse
import curses
import json
import os
import threading
import time
from collections.abc import Iterator
from dataclasses import dataclass
from typing import Any
from urllib import error, parse, request


@dataclass
class Config:
    server: str
    alert_topic: str
    reply_topic: str
    token: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--print-config", action="store_true", help="Print resolved configuration as JSON and exit"
    )
    return parser.parse_args()


def load_config() -> Config:
    return Config(
        server=os.getenv("NTFY_URL", os.getenv("NTFY_SERVER", "https://ntfy.sh")).rstrip("/"),
        alert_topic=os.getenv("NTFY_ALERT_TOPIC", os.getenv("NTFY_TOPIC", "")),
        reply_topic=os.getenv("NTFY_REPLY_TOPIC", ""),
        token=os.getenv("NTFY_TOKEN", ""),
    )


def auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"} if token else {}


def poll_topic(
    server: str, topic: str, token: str, since_ts: int
) -> tuple[int, list[dict[str, Any]]]:
    query = parse.urlencode({"poll": "1", "since": str(since_ts)})
    url = f"{server}/{topic}/json?{query}"
    req = request.Request(url, headers=auth_headers(token), method="GET")
    with request.urlopen(req, timeout=60) as response:  # noqa: S310
        raw = response.read().decode("utf-8", errors="replace")
    newest_ts = since_ts
    messages: list[dict[str, Any]] = []
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


def publish_message(
    server: str, topic: str, token: str, title: str, priority: str, body: str
) -> None:
    headers = {"User-Agent": "codex-ntfy-pubsub"}
    if title:
        headers["Title"] = title
    if priority:
        headers["Priority"] = priority
    headers.update(auth_headers(token))
    req = request.Request(
        f"{server}/{topic}",
        data=body.encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with request.urlopen(req, timeout=20):  # noqa: S310
        return


class Subscriber(threading.Thread):
    def __init__(
        self, config: Config, topic: str, logs: list[tuple[str, str]], lock: threading.Lock
    ) -> None:
        super().__init__(daemon=True)
        self.config = config
        self.topic = topic
        self.logs = logs
        self.lock = lock
        self.running = True
        self.since_ts = int(time.time())

    def run(self) -> None:
        while self.running:
            try:
                newest_ts, messages = poll_topic(
                    self.config.server, self.topic, self.config.token, self.since_ts
                )
                self.since_ts = newest_ts
                if messages:
                    with self.lock:
                        for event in messages:
                            body = str(event.get("message", "")).strip()
                            if body:
                                self.logs.append((self.topic, body))
            except error.URLError as exc:
                with self.lock:
                    self.logs.append(("error", f"{self.topic}: {exc}"))
                time.sleep(3)
            time.sleep(0.2)


def input_dialog(stdscr: curses.window, prompt: str, default: str = "") -> str:
    curses.echo()
    stdscr.clear()
    stdscr.addstr(0, 0, f"{prompt} [{default}]: ")
    stdscr.refresh()
    value = stdscr.getstr().decode("utf-8", errors="replace").strip()
    curses.noecho()
    return value or default


def configure_settings(stdscr: curses.window, config: Config) -> None:
    config.server = input_dialog(stdscr, "ntfy server", config.server)
    config.alert_topic = input_dialog(stdscr, "alert topic", config.alert_topic)
    config.reply_topic = input_dialog(stdscr, "reply topic", config.reply_topic)
    config.token = input_dialog(stdscr, "token (optional)", config.token)


def subscribe_topic(
    stdscr: curses.window,
    config: Config,
    subscriptions: dict[str, Subscriber],
    logs: list[tuple[str, str]],
    lock: threading.Lock,
) -> None:
    topic = input_dialog(stdscr, "Subscribe to topic", config.reply_topic or config.alert_topic)
    if not topic:
        return
    if topic in subscriptions and subscriptions[topic].running:
        stdscr.addstr(2, 0, f"Already subscribed to {topic}. Press any key to continue.")
        stdscr.getch()
        return
    sub = Subscriber(config, topic, logs, lock)
    subscriptions[topic] = sub
    sub.start()
    stdscr.addstr(2, 0, f"Subscribed to {topic}. Press any key to continue.")
    stdscr.getch()


def publish_dialog(stdscr: curses.window, config: Config) -> None:
    topic = input_dialog(stdscr, "Publish to topic", config.alert_topic)
    if not topic:
        return
    title = input_dialog(stdscr, "Title", "")
    priority = input_dialog(stdscr, "Priority (1-5)", "3")
    body = input_dialog(stdscr, "Message body", "")
    try:
        publish_message(config.server, topic, config.token, title, priority, body)
        stdscr.addstr(2, 0, f"Published to {topic}. Press any key to continue.")
    except error.URLError as exc:
        stdscr.addstr(2, 0, f"Publish failed: {exc}. Press any key to continue.")
    stdscr.getch()


def iter_recent_logs(logs: list[tuple[str, str]], limit: int = 50) -> Iterator[tuple[str, str]]:
    yield from logs[-limit:]


def view_logs(stdscr: curses.window, logs: list[tuple[str, str]], lock: threading.Lock) -> None:
    stdscr.clear()
    stdscr.addstr(0, 0, "Recent ntfy messages")
    with lock:
        snapshot = list(iter_recent_logs(logs))
    max_x = max(20, curses.COLS - 2)
    row = 2
    for topic, message in snapshot:
        line = f"[{topic}] {message}"
        if len(line) > max_x:
            line = line[: max_x - 1] + "..."
        if row >= curses.LINES - 2:
            break
        stdscr.addstr(row, 0, line)
        row += 1
    stdscr.addstr(min(row + 1, curses.LINES - 1), 0, "Press any key to return.")
    stdscr.getch()


def curses_main(stdscr: curses.window) -> None:
    curses.curs_set(0)
    config = load_config()
    logs: list[tuple[str, str]] = []
    lock = threading.Lock()
    subscriptions: dict[str, Subscriber] = {}
    menu = [
        "Configure server and topics",
        "Subscribe to a topic",
        "Publish a message",
        "View logs",
        "Quit",
    ]
    while True:
        stdscr.clear()
        stdscr.addstr(0, 0, "ntfy pub/sub")
        stdscr.addstr(1, 0, f"Server: {config.server}")
        stdscr.addstr(2, 0, f"Alert topic: {config.alert_topic}")
        stdscr.addstr(3, 0, f"Reply topic: {config.reply_topic}")
        for idx, item in enumerate(menu, start=1):
            stdscr.addstr(5 + idx, 2, f"{idx}. {item}")
        stdscr.addstr(12, 0, "Press 1-5 or q.")
        stdscr.refresh()
        key = stdscr.getch()
        if key == ord("1"):
            configure_settings(stdscr, config)
        elif key == ord("2"):
            subscribe_topic(stdscr, config, subscriptions, logs, lock)
        elif key == ord("3"):
            publish_dialog(stdscr, config)
        elif key == ord("4"):
            view_logs(stdscr, logs, lock)
        elif key in {ord("5"), ord("q"), ord("Q")}:
            break
        time.sleep(0.1)
    for sub in subscriptions.values():
        sub.running = False
    time.sleep(0.3)


def main() -> int:
    args = parse_args()
    if args.print_config:
        config = load_config()
        print(
            json.dumps(
                {
                    "server": config.server,
                    "alert_topic": config.alert_topic,
                    "reply_topic": config.reply_topic,
                    "token_configured": bool(config.token),
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0
    curses.wrapper(curses_main)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
