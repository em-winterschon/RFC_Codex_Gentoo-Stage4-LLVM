#!/usr/bin/env python3
"""Validate DNS resolvers referenced by netboot manifests and iPXE cmdlines."""

from __future__ import annotations

import argparse
import ipaddress
import json
import random
import re
import socket
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

NAMESERVER_ARG_RE = re.compile(r"(?<![A-Za-z0-9_.-])nameserver=(\[[0-9a-fA-F:.]+\]|[0-9A-Fa-f:.]+)")
DNS_KEY_NAMES = {
    "dns_nameserver",
    "dns_nameservers",
    "name_server",
    "name_servers",
    "nameserver",
    "nameservers",
}


class NetbootDnsValidationError(Exception):
    """Raised when netboot DNS policy validation cannot continue."""


@dataclass(frozen=True)
class NameServerReference:
    address: str
    source: str
    context: str


@dataclass(frozen=True)
class ApprovedNameServer:
    address: str
    live_queries: tuple[str, ...] = ()
    tcp_required: bool = True
    udp_required: bool = True


@dataclass
class DnsPolicy:
    approved: dict[str, ApprovedNameServer] = field(default_factory=dict)
    denied: set[str] = field(default_factory=set)
    default_live_queries: tuple[str, ...] = ()


@dataclass
class ValidationResult:
    references: list[NameServerReference] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


def require_yaml() -> Any:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - depends on local environment
        raise SystemExit("PyYAML is required. Install python yaml support first.") from exc
    return yaml


def normalize_ip(value: Any, *, label: str) -> str:
    text = str(value).strip()
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    try:
        return str(ipaddress.ip_address(text))
    except ValueError as exc:
        raise NetbootDnsValidationError(f"{label}: invalid DNS IP address {text}") from exc


def as_string_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        result: list[str] = []
        for item in value:
            result.extend(as_string_list(item))
        return result
    if isinstance(value, dict):
        return []
    return [part for part in re.split(r"[\s,]+", str(value).strip()) if part]


def load_policy(path: Path) -> DnsPolicy:
    yaml = require_yaml()
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle) or {}
    if not isinstance(payload, dict):
        raise NetbootDnsValidationError(f"{path}: policy document must be a mapping")
    policy_data = payload.get("netboot_dns_policy", payload)
    if not isinstance(policy_data, dict):
        raise NetbootDnsValidationError(f"{path}: netboot_dns_policy must be a mapping")

    default_live_queries = tuple(as_string_list(policy_data.get("default_live_queries", [])))
    approved: dict[str, ApprovedNameServer] = {}
    for index, item in enumerate(policy_data.get("approved_nameservers", []) or []):
        label = f"{path}: approved_nameservers[{index}]"
        if isinstance(item, dict):
            address = normalize_ip(item.get("address", ""), label=label)
            live_queries = tuple(as_string_list(item.get("live_queries", default_live_queries)))
            tcp_required = bool(item.get("tcp_required", policy_data.get("tcp_required", True)))
            udp_required = bool(item.get("udp_required", policy_data.get("udp_required", True)))
        else:
            address = normalize_ip(item, label=label)
            live_queries = default_live_queries
            tcp_required = bool(policy_data.get("tcp_required", True))
            udp_required = bool(policy_data.get("udp_required", True))
        approved[address] = ApprovedNameServer(
            address=address,
            live_queries=live_queries,
            tcp_required=tcp_required,
            udp_required=udp_required,
        )

    denied = set()
    for item in policy_data.get("denied_nameservers", []) or []:
        denied.add(
            normalize_ip(
                item.get("address") if isinstance(item, dict) else item,
                label=f"{path}: denied_nameservers",
            )
        )

    if not approved:
        raise NetbootDnsValidationError(
            f"{path}: at least one approved_nameservers entry is required"
        )
    overlap = sorted(set(approved) & denied)
    if overlap:
        overlap_text = ", ".join(overlap)
        raise NetbootDnsValidationError(
            f"{path}: nameservers cannot be both approved and denied: {overlap_text}"
        )
    return DnsPolicy(
        approved=approved,
        denied=denied,
        default_live_queries=default_live_queries,
    )


def add_nameserver(
    references: list[NameServerReference], raw_value: Any, *, source: str, context: str
) -> None:
    for item in as_string_list(raw_value):
        try:
            address = normalize_ip(item, label=f"{source}:{context}")
        except NetbootDnsValidationError:
            continue
        references.append(NameServerReference(address=address, source=source, context=context))


def extract_from_string(text: str, *, source: str, context: str) -> list[NameServerReference]:
    references: list[NameServerReference] = []
    for match in NAMESERVER_ARG_RE.finditer(text):
        add_nameserver(references, match.group(1), source=source, context=context)
    return references


def walk_payload(payload: Any, *, source: str, context: str = "$") -> list[NameServerReference]:
    references: list[NameServerReference] = []
    if isinstance(payload, dict):
        for key, value in payload.items():
            key_text = str(key)
            child_context = f"{context}.{key_text}"
            if key_text.lower() in DNS_KEY_NAMES:
                add_nameserver(references, value, source=source, context=child_context)
            if isinstance(value, str):
                references.extend(extract_from_string(value, source=source, context=child_context))
            references.extend(walk_payload(value, source=source, context=child_context))
    elif isinstance(payload, list):
        for index, item in enumerate(payload):
            item_context = f"{context}[{index}]"
            if isinstance(item, str):
                references.extend(extract_from_string(item, source=source, context=item_context))
            references.extend(walk_payload(item, source=source, context=item_context))
    elif isinstance(payload, str):
        references.extend(extract_from_string(payload, source=source, context=context))
    return references


def candidate_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if path.is_dir():
        return sorted(
            item
            for item in path.rglob("*")
            if item.is_file() and item.suffix.lower() in {".json", ".yaml", ".yml"}
        )
    raise NetbootDnsValidationError(f"{path}: path does not exist")


def extract_from_path(path: Path) -> list[NameServerReference]:
    yaml = require_yaml()
    references: list[NameServerReference] = []
    for file_path in candidate_files(path):
        with file_path.open("r", encoding="utf-8") as handle:
            payload = yaml.safe_load(handle) or {}
        references.extend(walk_payload(payload, source=str(file_path)))
    return references


def build_dns_query(name: str) -> tuple[int, bytes]:
    query_id = random.randint(0, 0xFFFF)
    header = struct.pack("!HHHHHH", query_id, 0x0100, 1, 0, 0, 0)
    labels = b"".join(
        bytes([len(label)]) + label.encode("ascii") for label in name.rstrip(".").split(".")
    )
    return query_id, header + labels + b"\x00" + struct.pack("!HH", 1, 1)


def validate_udp_dns(address: str, query_name: str, timeout: float) -> None:
    query_id, payload = build_dns_query(query_name)
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    with socket.socket(family, socket.SOCK_DGRAM) as sock:
        sock.settimeout(timeout)
        sock.sendto(payload, (address, 53))
        response, _peer = sock.recvfrom(512)
    if len(response) < 12:
        raise NetbootDnsValidationError(f"{address}: short DNS response for {query_name}")
    response_id, _flags, _qdcount, ancount, _nscount, _arcount = struct.unpack(
        "!HHHHHH", response[:12]
    )
    rcode = response[3] & 0x0F
    if response_id != query_id:
        raise NetbootDnsValidationError(f"{address}: mismatched DNS response ID for {query_name}")
    if rcode != 0:
        raise NetbootDnsValidationError(f"{address}: DNS query {query_name} returned rcode {rcode}")
    if ancount < 1:
        raise NetbootDnsValidationError(f"{address}: DNS query {query_name} returned no answers")


def validate_tcp_dns(address: str, timeout: float) -> None:
    with socket.create_connection((address, 53), timeout=timeout):
        return


def validate_references(
    references: list[NameServerReference],
    policy: DnsPolicy,
    *,
    live: bool,
    timeout: float,
) -> ValidationResult:
    result = ValidationResult(references=references)
    for reference in references:
        if reference.address in policy.denied:
            result.errors.append(
                f"{reference.source} {reference.context}: "
                f"DNS resolver {reference.address} is denied"
            )
            continue
        if reference.address not in policy.approved:
            approved = ", ".join(sorted(policy.approved))
            result.errors.append(
                f"{reference.source} {reference.context}: "
                f"DNS resolver {reference.address} "
                f"is not approved; approved resolvers: {approved}"
            )

    if not result.ok or not live:
        return result

    used_addresses = sorted({reference.address for reference in references})
    for address in used_addresses:
        server = policy.approved.get(address)
        if server is None:
            continue
        if server.tcp_required:
            try:
                validate_tcp_dns(address, timeout)
            except OSError as exc:
                result.errors.append(f"{address}: TCP/53 validation failed: {exc}")
        if server.udp_required:
            queries = server.live_queries or policy.default_live_queries
            if not queries:
                result.errors.append(f"{address}: no live DNS query names are configured")
                continue
            for query_name in queries:
                try:
                    validate_udp_dns(address, query_name, timeout)
                except (OSError, NetbootDnsValidationError) as exc:
                    result.errors.append(
                        f"{address}: UDP/53 validation failed for {query_name}: {exc}"
                    )
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", required=True, type=Path, help="Netboot DNS policy YAML file.")
    parser.add_argument(
        "--path",
        action="append",
        type=Path,
        default=[],
        help="YAML/JSON file or directory to scan for nameserver references.",
    )
    parser.add_argument(
        "--value",
        action="append",
        default=[],
        help="Literal command-line or config string to scan for nameserver references.",
    )
    parser.add_argument("--live", action="store_true", help="Validate TCP/UDP DNS reachability.")
    parser.add_argument("--timeout", type=float, default=2.0, help="Live DNS timeout in seconds.")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        policy = load_policy(args.policy)
        references: list[NameServerReference] = []
        for path in args.path:
            references.extend(extract_from_path(path))
        for index, value in enumerate(args.value):
            references.extend(extract_from_string(value, source=f"--value[{index}]", context="$"))
        result = validate_references(
            references,
            policy,
            live=args.live,
            timeout=args.timeout,
        )
    except NetbootDnsValidationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if args.format == "json":
        print(
            json.dumps(
                {
                    "ok": result.ok,
                    "nameservers": sorted({reference.address for reference in result.references}),
                    "references": [
                        {
                            "address": reference.address,
                            "source": reference.source,
                            "context": reference.context,
                        }
                        for reference in result.references
                    ],
                    "errors": result.errors,
                },
                indent=2,
                sort_keys=True,
            )
        )
    elif result.ok:
        addresses = (
            ", ".join(sorted({reference.address for reference in result.references})) or "none"
        )
        print(f"PASS: netboot DNS policy validated ({addresses})")
    else:
        for error in result.errors:
            print(f"ERROR: {error}", file=sys.stderr)

    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
