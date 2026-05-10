#!/usr/bin/env python3
"""Validate syslog-to-Elasticsearch ingestion with a searchable marker."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ValidationResult:
    service_name: str
    success: bool
    marker: str
    hits: int
    attempts: int
    syslog_target: str
    syslog_port: int
    syslog_protocol: str
    elasticsearch_url: str
    index_pattern: str
    field: str
    error: str = ""

    def as_dict(self) -> dict[str, Any]:
        payload = {
            "service_name": self.service_name,
            "success": self.success,
            "marker": self.marker,
            "hits": self.hits,
            "attempts": self.attempts,
            "syslog_target": self.syslog_target,
            "syslog_port": self.syslog_port,
            "syslog_protocol": self.syslog_protocol,
            "elasticsearch_url": self.elasticsearch_url,
            "index_pattern": self.index_pattern,
            "field": self.field,
        }
        if self.error:
            payload["error"] = self.error
        return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send a syslog marker and verify it is searchable in Elasticsearch."
    )
    parser.add_argument("--service-name", default="syslog-elasticsearch-ingest")
    parser.add_argument("--syslog-target", required=True)
    parser.add_argument("--syslog-port", type=int, default=514)
    parser.add_argument("--syslog-protocol", choices=("tcp", "udp"), default="tcp")
    parser.add_argument("--elasticsearch-url", required=True)
    parser.add_argument("--index-pattern", default="stage5-syslog*")
    parser.add_argument("--field", default="message")
    parser.add_argument("--marker", default="")
    parser.add_argument("--host", default=socket.gethostname())
    parser.add_argument("--program", default="stage5-syslog-elasticsearch-validator")
    parser.add_argument("--message-suffix", default="full-text-search-validation")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--query-timeout", type=float, default=8.0)
    parser.add_argument("--retries", type=int, default=10)
    parser.add_argument("--delay", type=float, default=2.0)
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def build_marker(args: argparse.Namespace) -> str:
    if args.marker:
        return args.marker
    return f"forge-syslog-es-smoke-{int(time.time())}-{uuid.uuid4().hex[:8]}"


def build_syslog_line(args: argparse.Namespace, marker: str) -> bytes:
    timestamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    if timestamp.endswith("+00:00"):
        timestamp = timestamp[:-6] + "Z"
    message = f"{marker} {args.message_suffix}".strip()
    line = f"<13>1 {timestamp} {args.host} {args.program} {uuid.uuid4().hex[:8]} - - {message}\n"
    return line.encode("utf-8")


def send_syslog(args: argparse.Namespace, marker: str) -> None:
    payload = build_syslog_line(args, marker)
    if args.syslog_protocol == "tcp":
        with socket.create_connection(
            (args.syslog_target, args.syslog_port), timeout=args.timeout
        ) as sock:
            sock.sendall(payload)
        return

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(args.timeout)
        sock.sendto(payload, (args.syslog_target, args.syslog_port))


def elasticsearch_search_url(args: argparse.Namespace) -> str:
    base = args.elasticsearch_url.rstrip("/")
    index = urllib.parse.quote(args.index_pattern, safe="*,")
    return f"{base}/{index}/_search"


def query_elasticsearch(args: argparse.Namespace, marker: str) -> tuple[int, dict[str, Any]]:
    payload = {
        "query": {"match_phrase": {args.field: marker}},
        "size": 5,
    }
    request = urllib.request.Request(
        elasticsearch_search_url(args),
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=args.query_timeout) as response:
        data = json.load(response)
    hits = data.get("hits", {}).get("hits", [])
    return len(hits), data


def validate(args: argparse.Namespace) -> ValidationResult:
    marker = build_marker(args)
    try:
        send_syslog(args, marker)
    except OSError as exc:
        return ValidationResult(
            service_name=args.service_name,
            success=False,
            marker=marker,
            hits=0,
            attempts=0,
            syslog_target=args.syslog_target,
            syslog_port=args.syslog_port,
            syslog_protocol=args.syslog_protocol,
            elasticsearch_url=args.elasticsearch_url,
            index_pattern=args.index_pattern,
            field=args.field,
            error=f"syslog send failed: {exc}",
        )

    last_error = ""
    for attempt in range(1, args.retries + 1):
        try:
            hits, _ = query_elasticsearch(args, marker)
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
            hits = 0
            last_error = f"elasticsearch query failed: {exc}"
        if hits > 0:
            return ValidationResult(
                service_name=args.service_name,
                success=True,
                marker=marker,
                hits=hits,
                attempts=attempt,
                syslog_target=args.syslog_target,
                syslog_port=args.syslog_port,
                syslog_protocol=args.syslog_protocol,
                elasticsearch_url=args.elasticsearch_url,
                index_pattern=args.index_pattern,
                field=args.field,
            )
        if attempt < args.retries:
            time.sleep(args.delay)

    return ValidationResult(
        service_name=args.service_name,
        success=False,
        marker=marker,
        hits=0,
        attempts=args.retries,
        syslog_target=args.syslog_target,
        syslog_port=args.syslog_port,
        syslog_protocol=args.syslog_protocol,
        elasticsearch_url=args.elasticsearch_url,
        index_pattern=args.index_pattern,
        field=args.field,
        error=last_error or "marker was not found in Elasticsearch",
    )


def emit_result(result: ValidationResult, json_output: bool) -> None:
    if json_output:
        print(json.dumps(result.as_dict(), sort_keys=True))
        return

    status = "ok" if result.success else "failed"
    detail = f" hits={result.hits}" if result.success else f" error={result.error}"
    print(
        f"{result.service_name} {status} marker={result.marker} "
        f"attempts={result.attempts}{detail}"
    )


def main() -> int:
    args = parse_args()
    result = validate(args)
    emit_result(result, args.json)
    return 0 if result.success else 1


if __name__ == "__main__":
    raise SystemExit(main())
