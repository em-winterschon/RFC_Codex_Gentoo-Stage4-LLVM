#!/usr/bin/env python3
"""Run MikroTik RouterOS serial console commands with terminal answerback support."""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
from collections.abc import Iterable

try:
    import serial
except ImportError as exc:  # pragma: no cover - exercised on hosts missing pyserial.
    raise SystemExit("missing Python module: pyserial") from exc


TERMINAL_QUERY = b"\x1bZ"
TERMINAL_ANSWERBACK = b"\x1b[?1;0c"
PROMPT_MARKER = b"] >"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Execute RouterOS commands through a local serial console.",
    )
    parser.add_argument("--port", required=True, help="Serial device, e.g. /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200, help="Serial baud rate")
    parser.add_argument("--username", default="admin", help="RouterOS username")
    parser.add_argument(
        "--password-env",
        default="ROUTEROS_PASSWORD",
        help="Environment variable containing the RouterOS password",
    )
    parser.add_argument(
        "--command",
        action="append",
        required=True,
        help="RouterOS command to execute; repeat for multiple commands",
    )
    parser.add_argument("--login-timeout", type=float, default=8.0)
    parser.add_argument("--command-timeout", type=float, default=8.0)
    return parser.parse_args()


def needs_terminal_answerback(buffer: bytes) -> bool:
    return TERMINAL_QUERY in buffer


def sanitize_transcript(text: str, secret: str) -> str:
    text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
    if secret:
        text = text.replace(secret, "<redacted>")
    return text


class RouterOSSerialSession:
    def __init__(self, port: str, baud: int, password: str):
        self.password = password
        self.serial = serial.Serial(port, baud, timeout=0.1, write_timeout=1)

    def close(self) -> None:
        self.serial.close()

    def send(self, value: str | bytes) -> None:
        data = value.encode() if isinstance(value, str) else value
        self.serial.write(data)
        self.serial.flush()

    def send_line(self, line: str) -> None:
        self.send(line + "\r")

    def read_for(self, seconds: float) -> bytes:
        end = time.time() + seconds
        data = b""
        answered_terminal_query = False
        while time.time() < end:
            chunk = self.serial.read(4096)
            if chunk:
                data += chunk
                if needs_terminal_answerback(data) and not answered_terminal_query:
                    self.send(TERMINAL_ANSWERBACK)
                    answered_terminal_query = True
            else:
                time.sleep(0.03)
        return data

    def read_until_any(self, needles: Iterable[bytes], timeout: float) -> bytes:
        end = time.time() + timeout
        data = b""
        answered_terminal_query = False
        needles = tuple(needles)
        while time.time() < end:
            chunk = self.serial.read(4096)
            if chunk:
                data += chunk
                if needs_terminal_answerback(data) and not answered_terminal_query:
                    self.send(TERMINAL_ANSWERBACK)
                    answered_terminal_query = True
                if any(needle in data for needle in needles):
                    return data
            else:
                time.sleep(0.03)
        return data

    def login(self, username: str, login_timeout: float) -> bytes:
        transcript = b""
        self.send("\x03\r")
        transcript += self.read_until_any((b"Login:", b"Password:", PROMPT_MARKER), login_timeout)
        if (
            b"Login:" not in transcript
            and b"Password:" not in transcript
            and PROMPT_MARKER not in transcript
        ):
            self.send_line("")
            transcript += self.read_until_any(
                (b"Login:", b"Password:", PROMPT_MARKER), login_timeout
            )

        if b"Login:" in transcript:
            self.send_line(username)
            transcript += self.read_until_any((b"Password:",), login_timeout)
        if b"Password:" in transcript and PROMPT_MARKER not in transcript:
            self.send_line(self.password)
            transcript += self.read_until_any(
                (PROMPT_MARKER, b"Login failed", b"Login:"), login_timeout
            )

        if b"Login failed" in transcript or PROMPT_MARKER not in transcript:
            raise RuntimeError("RouterOS serial login failed or prompt was not reached")
        return transcript

    def run_command(self, command: str, timeout: float) -> bytes:
        self.send_line(command)
        return self.read_until_any((PROMPT_MARKER,), timeout)


def main() -> int:
    args = parse_args()
    password = os.environ.get(args.password_env)
    if password is None:
        print(f"missing password env var: {args.password_env}", file=sys.stderr)
        return 2

    session = RouterOSSerialSession(args.port, args.baud, password)
    transcript = b""
    try:
        transcript += session.login(args.username, args.login_timeout)
        for command in args.command:
            transcript += session.run_command(command, args.command_timeout)
    except Exception as exc:
        print(sanitize_transcript(transcript.decode("utf-8", "replace"), password), end="")
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        session.close()

    print(sanitize_transcript(transcript.decode("utf-8", "replace"), password), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
