#!/usr/bin/env python3
"""Collect read-only MikroTik RouterOS state through a serial console."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_COMMANDS: tuple[tuple[str, str], ...] = (
    ("identity", "/system identity print"),
    ("resource", "/system resource print"),
    ("routerboard", "/system routerboard print"),
    ("packages", "/system package print"),
    ("ethernet-detail", "/interface ethernet print detail"),
    ("ethernet-monitor", "/interface ethernet monitor [find] once"),
    ("bonding-detail", "/interface bonding print detail"),
    ("bridge-detail", "/interface bridge print detail"),
    ("bridge-port-detail", "/interface bridge port print detail"),
    ("vlan-detail", "/interface vlan print detail"),
    ("ip-address-detail", "/ip address print detail"),
    ("ip-route-detail", "/ip route print detail"),
    ("ip-service-detail", "/ip service print detail"),
    ("neighbor-detail", "/ip neighbor print detail"),
    ("lldp-detail", "/ip neighbor discovery-settings print"),
    ("export-hide-sensitive", "/export hide-sensitive"),
)

SENSITIVE_EXPORT_COMMAND: tuple[str, str] = (
    "export-show-sensitive",
    "/export show-sensitive",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Snapshot RouterOS read-only state through serial console automation.",
    )
    parser.add_argument("--port", required=True, help="Serial device, e.g. /dev/ttyUSB2")
    parser.add_argument("--baud", type=int, default=115200, help="Serial baud rate")
    parser.add_argument("--username", default="admin", help="RouterOS username")
    parser.add_argument(
        "--password-env",
        default="ROUTEROS_PASSWORD",
        help="Environment variable containing the RouterOS password",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="Directory for command outputs and manifest.json",
    )
    parser.add_argument(
        "--serial-command-script",
        type=Path,
        default=Path(__file__).resolve().with_name("routeros-serial-command.py"),
        help="Path to routeros-serial-command.py.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=20,
        help="Per-command timeout in seconds",
    )
    parser.add_argument(
        "--include-sensitive-export",
        action="store_true",
        help="Also collect /export show-sensitive for encrypted config backup workflows.",
    )
    parser.add_argument(
        "--allow-failures",
        action="store_true",
        help="Write partial snapshots and exit zero even when one command fails.",
    )
    return parser.parse_args()


def safe_filename(name: str) -> str:
    return "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in name).strip("-")


def run_serial_command(
    *,
    script: Path,
    port: str,
    baud: int,
    username: str,
    password_env: str,
    command: str,
    timeout: int,
) -> subprocess.CompletedProcess[str]:
    argv = [
        "timeout",
        "--kill-after=2s",
        f"{max(timeout + 8, 1)}s",
        "python3",
        str(script),
        "--port",
        port,
        "--baud",
        str(baud),
        "--username",
        username,
        "--password-env",
        password_env,
        "--login-timeout",
        "8",
        "--command-timeout",
        str(timeout),
        "--command",
        command,
    ]
    return subprocess.run(
        argv,
        env=os.environ.copy(),
        text=True,
        capture_output=True,
        timeout=timeout + 12,
        check=False,
    )


def main() -> int:
    args = parse_args()
    password = os.environ.get(args.password_env)
    if password is None:
        print(f"missing password env var: {args.password_env}", file=sys.stderr)
        return 2
    if not password:
        print(f"empty password env var: {args.password_env}", file=sys.stderr)
        return 2
    if not args.serial_command_script.exists():
        print(f"missing serial command script: {args.serial_command_script}", file=sys.stderr)
        return 2

    commands = list(DEFAULT_COMMANDS)
    if args.include_sensitive_export:
        commands.append(SENSITIVE_EXPORT_COMMAND)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, object] = {
        "port": args.port,
        "username": args.username,
        "collected_at_epoch": int(time.time()),
        "commands": [],
        "transport": "serial",
    }
    failures = 0

    for name, command in commands:
        filename = safe_filename(name) + ".txt"
        result = run_serial_command(
            script=args.serial_command_script,
            port=args.port,
            baud=args.baud,
            username=args.username,
            password_env=args.password_env,
            command=command,
            timeout=args.timeout,
        )
        output = result.stdout
        if result.stderr:
            output += ("\n" if output else "") + "STDERR:\n" + result.stderr
        (args.output_dir / filename).write_text(output, encoding="utf-8")
        if result.returncode != 0:
            failures += 1
        manifest["commands"].append(
            {
                "name": name,
                "command": command,
                "file": filename,
                "returncode": result.returncode,
            }
        )

    (args.output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0 if args.allow_failures or failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
