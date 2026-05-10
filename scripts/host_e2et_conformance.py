#!/usr/bin/env python3
"""Render RFC99 host E2ET conformance reports from acceptance manifests."""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class E2ETConformanceError(Exception):
    """Raised when a host E2ET manifest is invalid."""


VALID_STATUSES = {"pass", "fail", "warn", "skip"}


@dataclass(frozen=True)
class CheckResult:
    gate: str
    name: str
    status: str
    hard_fail: bool
    evidence: str

    @property
    def success(self) -> bool:
        return self.status == "pass"

    def as_dict(self) -> dict[str, Any]:
        return {
            "gate": self.gate,
            "name": self.name,
            "status": self.status,
            "hard_fail": self.hard_fail,
            "evidence": self.evidence,
        }


@dataclass(frozen=True)
class GateResult:
    name: str
    weight: float
    hard_required: bool
    checks: list[CheckResult]

    @property
    def score_fraction(self) -> float:
        scored = [check for check in self.checks if check.status != "skip"]
        if not scored:
            return 0.0
        passed = sum(1 for check in scored if check.status == "pass")
        return passed / len(scored)

    @property
    def weighted_score(self) -> float:
        return self.weight * self.score_fraction

    def as_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "weight": self.weight,
            "hard_required": self.hard_required,
            "score_fraction": round(self.score_fraction, 4),
            "weighted_score": round(self.weighted_score, 4),
            "checks": [check.as_dict() for check in self.checks],
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render RFC99 host E2ET conformance reports."
    )
    parser.add_argument("--manifest", required=True, help="JSON or YAML host E2ET manifest.")
    parser.add_argument("--json-output", help="Optional JSON report output path.")
    parser.add_argument("--markdown-output", help="Optional Markdown report output path.")
    parser.add_argument("--junit-output", help="Optional JUnit XML report output path.")
    return parser.parse_args()


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise E2ETConformanceError(f"manifest does not exist: {path}")
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        payload = json.loads(text)
    else:
        try:
            import yaml  # type: ignore[import-not-found]
        except ImportError as exc:
            raise E2ETConformanceError("PyYAML is required for YAML E2ET manifests") from exc
        payload = yaml.safe_load(text)
    if not isinstance(payload, dict):
        raise E2ETConformanceError("manifest top-level document must be a mapping")
    return payload


def require_mapping(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload.get(key)
    if not isinstance(value, dict):
        raise E2ETConformanceError(f"manifest {key} must be a mapping")
    return value


def require_string(payload: dict[str, Any], key: str, label: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise E2ETConformanceError(f"{label}: missing required string field {key}")
    return value.strip()


def optional_string(payload: dict[str, Any], key: str, default: str = "") -> str:
    value = payload.get(key, default)
    if value is None:
        return default
    if not isinstance(value, str):
        raise E2ETConformanceError(f"{key} must be a string")
    return value.strip()


def parse_weight(gate: dict[str, Any], label: str) -> float:
    value = gate.get("weight", 1)
    if not isinstance(value, int | float) or value < 0:
        raise E2ETConformanceError(f"{label}: weight must be a non-negative number")
    return float(value)


def parse_bool(payload: dict[str, Any], key: str, default: bool = False) -> bool:
    value = payload.get(key, default)
    if not isinstance(value, bool):
        raise E2ETConformanceError(f"{key} must be a boolean")
    return value


def parse_check(gate_name: str, gate_hard_required: bool, check: dict[str, Any]) -> CheckResult:
    name = require_string(check, "name", gate_name)
    status = require_string(check, "status", f"{gate_name}.{name}").lower()
    if status not in VALID_STATUSES:
        raise E2ETConformanceError(
            f"{gate_name}.{name}: status must be one of {sorted(VALID_STATUSES)}"
        )
    explicit_hard_fail = parse_bool(check, "hard_fail", False)
    hard_fail = status == "fail" and (gate_hard_required or explicit_hard_fail)
    return CheckResult(
        gate=gate_name,
        name=name,
        status=status,
        hard_fail=hard_fail,
        evidence=optional_string(check, "evidence"),
    )


def parse_gates(manifest: dict[str, Any]) -> list[GateResult]:
    raw_gates = manifest.get("gates")
    if not isinstance(raw_gates, list) or not raw_gates:
        raise E2ETConformanceError("manifest gates must be a non-empty list")

    gates: list[GateResult] = []
    for raw_gate in raw_gates:
        if not isinstance(raw_gate, dict):
            raise E2ETConformanceError("each gate must be a mapping")
        gate_name = require_string(raw_gate, "name", "gate")
        weight = parse_weight(raw_gate, gate_name)
        hard_required = parse_bool(raw_gate, "hard_required", False)
        raw_checks = raw_gate.get("checks")
        if not isinstance(raw_checks, list) or not raw_checks:
            raise E2ETConformanceError(f"{gate_name}: checks must be a non-empty list")
        checks = []
        for raw_check in raw_checks:
            if not isinstance(raw_check, dict):
                raise E2ETConformanceError(f"{gate_name}: each check must be a mapping")
            checks.append(parse_check(gate_name, hard_required, raw_check))
        gates.append(
            GateResult(
                name=gate_name,
                weight=weight,
                hard_required=hard_required,
                checks=checks,
            )
        )
    return gates


def tier_for_score(score: float) -> str:
    if score >= 99:
        return "p99"
    if score >= 95:
        return "p95"
    if score >= 90:
        return "p90"
    if score >= 80:
        return "p80"
    if score >= 60:
        return "p60"
    return "below-p60"


def tier_rank(tier: str) -> int:
    order = {
        "below-p60": 0,
        "p60": 60,
        "p80": 80,
        "p90": 90,
        "p95": 95,
        "p99": 99,
    }
    return order.get(tier, 0)


def release_state(hard_failures: list[CheckResult], current_tier: str, target_tier: str) -> str:
    if hard_failures:
        return "blocked"
    if tier_rank(current_tier) >= tier_rank(target_tier):
        return "release-candidate"
    if tier_rank(current_tier) >= 80:
        return "lab-accepted"
    if tier_rank(current_tier) >= 60:
        return "provisional"
    return "blocked"


def evaluate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    run = require_mapping(manifest, "run")
    host = require_mapping(manifest, "host")
    baseline = require_mapping(manifest, "baseline")
    gates = parse_gates(manifest)

    checks = [check for gate in gates for check in gate.checks]
    hard_failures = [check for check in checks if check.hard_fail]
    total_weight = sum(gate.weight for gate in gates)
    weighted_score = sum(gate.weighted_score for gate in gates)
    score = 0.0 if total_weight == 0 else (weighted_score / total_weight) * 100
    current_tier = tier_for_score(score)
    target_tier = optional_string(baseline, "target_tier", "p90") or "p90"
    recommended_state = release_state(hard_failures, current_tier, target_tier)
    e2et_pass = not hard_failures and tier_rank(current_tier) >= tier_rank(target_tier)

    return {
        "schema": "rfc99.host-e2et-conformance.v1",
        "run": {
            "id": require_string(run, "id", "run"),
            "phase": optional_string(run, "phase", "unspecified") or "unspecified",
            "timestamp": optional_string(run, "timestamp"),
        },
        "host": {
            "name": require_string(host, "name", "host"),
            "fqdn": optional_string(host, "fqdn"),
            "profile": optional_string(host, "profile"),
        },
        "baseline": {
            "name": require_string(baseline, "name", "baseline"),
            "target_tier": target_tier,
        },
        "e2et_pass": e2et_pass,
        "recommended_release_state": recommended_state,
        "summary": {
            "checks_total": len(checks),
            "checks_passed": sum(1 for check in checks if check.status == "pass"),
            "checks_failed": sum(1 for check in checks if check.status == "fail"),
            "checks_warned": sum(1 for check in checks if check.status == "warn"),
            "checks_skipped": sum(1 for check in checks if check.status == "skip"),
            "hard_failures": len(hard_failures),
        },
        "conformance": {
            "score": round(score, 2),
            "current_tier": current_tier,
            "target_tier": target_tier,
            "weighted_score": round(weighted_score, 4),
            "total_weight": round(total_weight, 4),
        },
        "hard_failures": [
            {
                "gate": check.gate,
                "check": check.name,
                "evidence": check.evidence,
            }
            for check in hard_failures
        ],
        "gates": [gate.as_dict() for gate in gates],
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# RFC99 Host E2ET Conformance Report",
        "",
        f"- Host: `{report['host']['name']}`",
        f"- FQDN: `{report['host']['fqdn']}`",
        f"- Run ID: `{report['run']['id']}`",
        f"- Phase: `{report['run']['phase']}`",
        f"- Baseline: `{report['baseline']['name']}`",
        f"- E2ET pass: `{str(report['e2et_pass']).lower()}`",
        f"- Release state: `{report['recommended_release_state']}`",
        f"- Score: `{report['conformance']['score']}`",
        f"- Tier: `{report['conformance']['current_tier']}`",
        "",
        "## Summary",
        "",
        "| Metric | Value |",
        "| --- | --- |",
    ]
    for key, value in report["summary"].items():
        lines.append(f"| `{key}` | `{value}` |")
    lines.extend(["", "## Gates", ""])
    for gate in report["gates"]:
        lines.append(f"### {gate['name']}")
        lines.append("")
        lines.append(
            f"Weight `{gate['weight']}`, score fraction `{gate['score_fraction']}`, "
            f"weighted score `{gate['weighted_score']}`."
        )
        lines.append("")
        lines.append("| Check | Status | Hard Fail | Evidence |")
        lines.append("| --- | --- | --- | --- |")
        for check in gate["checks"]:
            evidence = str(check["evidence"]).replace("|", "\\|")
            lines.append(
                f"| {check['name']} | `{check['status']}` | "
                f"`{str(check['hard_fail']).lower()}` | {evidence} |"
            )
        lines.append("")
    if report["hard_failures"]:
        lines.extend(["## Hard Failures", ""])
        for failure in report["hard_failures"]:
            lines.append(
                f"- `{failure['gate']}` / `{failure['check']}`: {failure['evidence']}"
            )
        lines.append("")
    return "\n".join(lines)


def render_junit(report: dict[str, Any]) -> str:
    summary = report["summary"]
    suite = ET.Element(
        "testsuite",
        {
            "name": f"host-e2et-{report['host']['name']}",
            "tests": str(summary["checks_total"]),
            "failures": str(summary["checks_failed"]),
            "skipped": str(summary["checks_skipped"]),
            "errors": "0",
        },
    )
    for gate in report["gates"]:
        for check in gate["checks"]:
            case = ET.SubElement(
                suite,
                "testcase",
                {
                    "classname": gate["name"],
                    "name": check["name"],
                },
            )
            if check["status"] == "fail":
                failure = ET.SubElement(case, "failure", {"message": check["evidence"]})
                failure.text = check["evidence"]
            elif check["status"] == "skip":
                skipped = ET.SubElement(case, "skipped", {"message": check["evidence"]})
                skipped.text = check["evidence"]
            elif check["status"] == "warn":
                system_out = ET.SubElement(case, "system-out")
                system_out.text = f"warning: {check['evidence']}"
    return ET.tostring(suite, encoding="unicode")


def write_output(path: str | None, content: str) -> None:
    if not path:
        return
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content, encoding="utf-8")


def main() -> int:
    args = parse_args()
    try:
        manifest = load_manifest(Path(args.manifest))
        report = evaluate_manifest(manifest)
    except (E2ETConformanceError, json.JSONDecodeError) as exc:
        payload = {"e2et_pass": False, "recommended_release_state": "error", "error": str(exc)}
        print(json.dumps(payload, sort_keys=True))
        return 2

    json_payload = json.dumps(report, indent=2, sort_keys=True)
    write_output(args.json_output, json_payload + "\n")
    write_output(args.markdown_output, render_markdown(report) + "\n")
    write_output(args.junit_output, render_junit(report) + "\n")
    print(json_payload)
    return 0 if report["e2et_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
