#!/usr/bin/env python3
"""Run SLO-style point-in-time service health validations.

This complements the nmap-based port validator with service-level indicators:
availability, latency, and protocol response correctness. It is intentionally
dependency-light; YAML manifests are supported when PyYAML is available and
JSON manifests always work.
"""

from __future__ import annotations

import argparse
import http.client
import json
import socket
import ssl
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class SLOValidationError(Exception):
    """Raised when a manifest or probe definition is invalid."""


@dataclass(frozen=True)
class ProbeResult:
    service_name: str
    check_name: str
    protocol: str
    target: str
    port: int
    success: bool
    latency_ms: float | None
    latency_budget_ms: float | None
    status_code: int | None = None
    error: str | None = None

    @property
    def latency_within_budget(self) -> bool:
        if self.latency_budget_ms is None or self.latency_ms is None:
            return self.success
        return self.latency_ms <= self.latency_budget_ms

    def as_dict(self) -> dict[str, Any]:
        return {
            "service_name": self.service_name,
            "check_name": self.check_name,
            "protocol": self.protocol,
            "target": self.target,
            "port": self.port,
            "success": self.success,
            "latency_ms": self.latency_ms,
            "latency_budget_ms": self.latency_budget_ms,
            "latency_within_budget": self.latency_within_budget,
            "status_code": self.status_code,
            "error": self.error,
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate service SLO probe manifests.")
    parser.add_argument("--manifest", required=True, help="YAML or JSON SLO manifest.")
    parser.add_argument(
        "--phase",
        default="any",
        help="Validation phase to run. Checks without phases run in every phase.",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    return parser.parse_args()


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise SLOValidationError(f"manifest does not exist: {path}")
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        payload = json.loads(text)
    else:
        try:
            import yaml  # type: ignore[import-not-found]
        except ImportError as exc:
            raise SLOValidationError("PyYAML is required for YAML SLO manifests") from exc
        payload = yaml.safe_load(text)
    if not isinstance(payload, dict):
        raise SLOValidationError("manifest top-level document must be a mapping")
    return payload


def required_string(row: dict[str, Any], key: str, label: str) -> str:
    value = row.get(key)
    if not isinstance(value, str) or not value.strip():
        raise SLOValidationError(f"{label}: missing required string field {key}")
    return value.strip()


def required_port(row: dict[str, Any], label: str) -> int:
    value = row.get("port")
    if not isinstance(value, int) or value < 1 or value > 65535:
        raise SLOValidationError(f"{label}: port must be an integer from 1 to 65535")
    return value


def optional_float(row: dict[str, Any], key: str, label: str) -> float | None:
    value = row.get(key)
    if value is None:
        return None
    if not isinstance(value, int | float) or value < 0:
        raise SLOValidationError(f"{label}: {key} must be a non-negative number")
    return float(value)


def should_run(check: dict[str, Any], phase: str) -> bool:
    phases = check.get("phases")
    if phases is None or phase == "any":
        return True
    if not isinstance(phases, list):
        raise SLOValidationError("check phases must be a list when provided")
    return phase in phases


def tcp_probe(
    service_name: str,
    check_name: str,
    target: str,
    port: int,
    timeout_seconds: float,
    latency_budget_ms: float | None,
) -> ProbeResult:
    start = time.perf_counter()
    try:
        with socket.create_connection((target, port), timeout=timeout_seconds):
            latency_ms = (time.perf_counter() - start) * 1000
            return ProbeResult(
                service_name=service_name,
                check_name=check_name,
                protocol="tcp",
                target=target,
                port=port,
                success=latency_budget_ms is None or latency_ms <= latency_budget_ms,
                latency_ms=round(latency_ms, 3),
                latency_budget_ms=latency_budget_ms,
            )
    except OSError as exc:
        latency_ms = (time.perf_counter() - start) * 1000
        return ProbeResult(
            service_name=service_name,
            check_name=check_name,
            protocol="tcp",
            target=target,
            port=port,
            success=False,
            latency_ms=round(latency_ms, 3),
            latency_budget_ms=latency_budget_ms,
            error=str(exc),
        )


def http_probe(
    service_name: str,
    check_name: str,
    protocol: str,
    target: str,
    port: int,
    path: str,
    expected_status: list[int],
    timeout_seconds: float,
    latency_budget_ms: float | None,
) -> ProbeResult:
    connection_cls = (
        http.client.HTTPSConnection if protocol == "https" else http.client.HTTPConnection
    )
    context = ssl._create_unverified_context() if protocol == "https" else None
    start = time.perf_counter()
    try:
        if protocol == "https":
            connection = connection_cls(target, port, timeout=timeout_seconds, context=context)
        else:
            connection = connection_cls(target, port, timeout=timeout_seconds)
        try:
            connection.request("GET", path)
            response = connection.getresponse()
            response.read(256)
            latency_ms = (time.perf_counter() - start) * 1000
            status_ok = response.status in expected_status
            latency_ok = latency_budget_ms is None or latency_ms <= latency_budget_ms
            return ProbeResult(
                service_name=service_name,
                check_name=check_name,
                protocol=protocol,
                target=target,
                port=port,
                success=status_ok and latency_ok,
                latency_ms=round(latency_ms, 3),
                latency_budget_ms=latency_budget_ms,
                status_code=response.status,
            )
        finally:
            connection.close()
    except OSError as exc:
        latency_ms = (time.perf_counter() - start) * 1000
        return ProbeResult(
            service_name=service_name,
            check_name=check_name,
            protocol=protocol,
            target=target,
            port=port,
            success=False,
            latency_ms=round(latency_ms, 3),
            latency_budget_ms=latency_budget_ms,
            error=str(exc),
        )


def validate_check(service_name: str, check: dict[str, Any], phase: str) -> ProbeResult | None:
    if not should_run(check, phase):
        return None
    label = f"{service_name}.{check.get('name', 'check')}"
    check_name = required_string(check, "name", label)
    protocol = required_string(check, "protocol", label).lower()
    target = required_string(check, "target", label)
    port = required_port(check, label)
    timeout_seconds = optional_float(check, "timeout_seconds", label) or 3.0
    latency_budget_ms = optional_float(check, "latency_budget_ms", label)

    if protocol == "tcp":
        return tcp_probe(service_name, check_name, target, port, timeout_seconds, latency_budget_ms)

    if protocol in {"http", "https"}:
        path = check.get("path", "/")
        if not isinstance(path, str) or not path.startswith("/"):
            raise SLOValidationError(f"{label}: path must be an absolute HTTP path")
        expected_status_raw = check.get("expected_status", [200])
        if not isinstance(expected_status_raw, list) or not expected_status_raw:
            raise SLOValidationError(f"{label}: expected_status must be a non-empty list")
        expected_status = []
        for status in expected_status_raw:
            if not isinstance(status, int) or status < 100 or status > 599:
                raise SLOValidationError(f"{label}: invalid expected HTTP status {status}")
            expected_status.append(status)
        return http_probe(
            service_name,
            check_name,
            protocol,
            target,
            port,
            path,
            expected_status,
            timeout_seconds,
            latency_budget_ms,
        )

    raise SLOValidationError(f"{label}: unsupported protocol {protocol}")


def validate_manifest(manifest: dict[str, Any], phase: str) -> dict[str, Any]:
    services = manifest.get("services")
    if not isinstance(services, list) or not services:
        raise SLOValidationError("manifest services must be a non-empty list")

    results: list[ProbeResult] = []
    for service in services:
        if not isinstance(service, dict):
            raise SLOValidationError("each service must be a mapping")
        service_name = required_string(service, "name", "service")
        checks = service.get("checks")
        if not isinstance(checks, list) or not checks:
            raise SLOValidationError(f"{service_name}: checks must be a non-empty list")
        for check in checks:
            if not isinstance(check, dict):
                raise SLOValidationError(f"{service_name}: each check must be a mapping")
            result = validate_check(service_name, check, phase)
            if result is not None:
                results.append(result)

    successful = sum(1 for result in results if result.success)
    total = len(results)
    return {
        "manifest_name": manifest.get("name", "unnamed"),
        "phase": phase,
        "slo_met": total > 0 and successful == total,
        "checks_total": total,
        "checks_successful": successful,
        "checks_failed": total - successful,
        "results": [result.as_dict() for result in results],
    }


def emit_text(report: dict[str, Any]) -> None:
    print(
        f"{report['manifest_name']} phase={report['phase']} "
        f"slo_met={str(report['slo_met']).lower()} "
        f"checks={report['checks_successful']}/{report['checks_total']}"
    )
    for result in report["results"]:
        status = "ok" if result["success"] else "failed"
        print(
            f"{status} {result['service_name']} {result['check_name']} "
            f"{result['protocol']}://{result['target']}:{result['port']} "
            f"latency_ms={result['latency_ms']}"
        )


def main() -> int:
    args = parse_args()
    try:
        manifest = load_manifest(Path(args.manifest))
        report = validate_manifest(manifest, args.phase)
    except (SLOValidationError, json.JSONDecodeError) as exc:
        payload = {"slo_met": False, "error": str(exc)}
        if args.json:
            print(json.dumps(payload, sort_keys=True))
        else:
            print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(report, sort_keys=True))
    else:
        emit_text(report)
    return 0 if report["slo_met"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
