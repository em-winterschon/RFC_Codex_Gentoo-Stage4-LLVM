#!/usr/bin/env python3
"""Validate service reachability with nmap and machine-readable output."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ValidationResult:
    service_name: str
    target: str
    port: int
    protocol: str
    status: str
    service: str
    success: bool
    command: list[str]

    def as_dict(self) -> dict[str, Any]:
        return {
            "service_name": self.service_name,
            "target": self.target,
            "port": self.port,
            "protocol": self.protocol,
            "status": self.status,
            "service": self.service,
            "success": self.success,
            "command": self.command,
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate TCP/UDP service readiness using nmap XML output."
    )
    parser.add_argument("--target", required=True, help="Target IP address or hostname.")
    parser.add_argument("--port", required=True, type=int, help="Service port to scan.")
    parser.add_argument(
        "--protocol",
        choices=("tcp", "udp"),
        default="tcp",
        help="Transport protocol to validate.",
    )
    parser.add_argument(
        "--service-name",
        default="service",
        help="Logical service name for reports.",
    )
    parser.add_argument(
        "--nmap-bin",
        default="nmap",
        help="Path to nmap executable. Useful for tests.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Process timeout in seconds.",
    )
    parser.add_argument(
        "--allow-open-filtered",
        action="store_true",
        help="Treat nmap open|filtered as success, mainly for UDP readiness probes.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON. Default emits a concise text line.",
    )
    return parser.parse_args()


def build_nmap_command(args: argparse.Namespace) -> list[str]:
    scan_arg = "-sT" if args.protocol == "tcp" else "-sU"
    return [
        args.nmap_bin,
        scan_arg,
        "-Pn",
        "-p",
        str(args.port),
        "-oX",
        "-",
        args.target,
    ]


def run_nmap(command: list[str], timeout: int) -> str:
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(f"nmap executable not found: {command[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"nmap timed out after {timeout}s") from exc

    if completed.returncode not in (0, 1):
        stderr = completed.stderr.strip()
        raise RuntimeError(f"nmap failed with exit {completed.returncode}: {stderr}")
    if not completed.stdout.strip():
        raise RuntimeError("nmap produced no XML output")
    return completed.stdout


def extract_port_state(xml_payload: str, protocol: str, port: int) -> tuple[str, str]:
    try:
        root = ET.fromstring(xml_payload)
    except ET.ParseError as exc:
        raise RuntimeError(f"failed to parse nmap XML: {exc}") from exc

    for port_node in root.findall(".//port"):
        if port_node.get("protocol") != protocol:
            continue
        if port_node.get("portid") != str(port):
            continue
        state_node = port_node.find("state")
        service_node = port_node.find("service")
        state = state_node.get("state", "unknown") if state_node is not None else "unknown"
        service = service_node.get("name", "") if service_node is not None else ""
        return state, service

    return "missing", ""


def validate(args: argparse.Namespace) -> ValidationResult:
    command = build_nmap_command(args)
    xml_payload = run_nmap(command, args.timeout)
    status, service = extract_port_state(xml_payload, args.protocol, args.port)
    acceptable = {"open"}
    if args.allow_open_filtered:
        acceptable.add("open|filtered")

    return ValidationResult(
        service_name=args.service_name,
        target=args.target,
        port=args.port,
        protocol=args.protocol,
        status=status,
        service=service,
        success=status in acceptable,
        command=command,
    )


def emit_result(result: ValidationResult, json_output: bool) -> None:
    if json_output:
        print(json.dumps(result.as_dict(), sort_keys=True))
        return
    print(
        f"{result.service_name} {result.protocol}/{result.port} "
        f"{result.target} status={result.status}"
    )


def main() -> int:
    args = parse_args()
    try:
        result = validate(args)
    except RuntimeError as exc:
        payload = {
            "service_name": args.service_name,
            "target": args.target,
            "port": args.port,
            "protocol": args.protocol,
            "status": "error",
            "success": False,
            "error": str(exc),
        }
        if args.json:
            print(json.dumps(payload, sort_keys=True))
        else:
            print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    emit_result(result, args.json)
    return 0 if result.success else 1


if __name__ == "__main__":
    raise SystemExit(main())
