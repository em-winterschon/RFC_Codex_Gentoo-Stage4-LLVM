#!/usr/bin/env python3
"""Validate the RDMA production-promotion readiness manifest."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import yaml

REQUIRED_ISSUES = {
    "vendor_ofed_doca_path": 111,
    "rdma_storage_client_baseline": 117,
    "fmt2_arista_r630_fabric": 130,
}
REQUIRED_STAGES = {
    "rdma-storage-client-baseline",
    "vendor-ofed-doca-convergence",
    "fmt2-r630-arista-fabric-admission",
    "pairwise-rdma-smoke",
    "storage-protocol-pilots",
    "failure-injection-and-reboot-conformance",
}
REQUIRED_INVARIANTS = {
    "do-not-enable-connectx-lacp-before-pairwise-rdma-and-one-path-failure-pass",
    "do-not-admit-in-kernel-mlx5-as-production-rdma-without-vendor-driver-decision",
    "do-not-enable-nfs-rdma-or-nvme-rdma-before-lossless-class-validation",
    "do-not-mutate-arista-without-pre-change-snapshot-and-rollback-commands",
}


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise ValueError("manifest must contain a top-level mapping")
    return payload


def validate_manifest(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if payload.get("kind") != "RdmaPromotionReadiness":
        errors.append("kind must be RdmaPromotionReadiness")
    if payload.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    if payload.get("mutation_default") != "blocked":
        errors.append("mutation_default must remain blocked")

    issue_links = payload.get("issue_links", {})
    for key, expected in REQUIRED_ISSUES.items():
        if issue_links.get(key) != expected:
            errors.append(f"issue_links.{key} must be {expected}")

    stage_ids = {
        str(stage.get("id", ""))
        for stage in payload.get("promotion_stages", [])
        if isinstance(stage, dict)
    }
    missing_stages = sorted(REQUIRED_STAGES - stage_ids)
    if missing_stages:
        errors.append(f"missing promotion stages: {', '.join(missing_stages)}")

    invariants = {str(item) for item in payload.get("safety_invariants", [])}
    missing_invariants = sorted(REQUIRED_INVARIANTS - invariants)
    if missing_invariants:
        errors.append(f"missing safety invariants: {', '.join(missing_invariants)}")

    issue_status = payload.get("issue_status", {})
    if issue_status.get("117", {}).get("closeable_after_merge") is not True:
        errors.append("issue 117 must be marked closeable_after_merge=true")
    for issue in ("111", "130"):
        if issue_status.get(issue, {}).get("status") != "live-gated":
            errors.append(f"issue {issue} must remain live-gated")

    return errors


def build_summary(path: Path, payload: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    issue_status = payload.get("issue_status", {})
    return {
        "manifest": str(path),
        "valid": not errors,
        "errors": errors,
        "production_admission_state": payload.get("production_admission_state", "unknown"),
        "production_blockers": payload.get("production_blockers", []),
        "issues": {
            issue: {
                "status": data.get("status"),
                "closeable_after_merge": bool(data.get("closeable_after_merge", False)),
                "closeout_reason": data.get("closeout_reason", ""),
            }
            for issue, data in sorted(issue_status.items())
            if isinstance(data, dict)
        },
        "promotion_stage_count": len(payload.get("promotion_stages", [])),
        "safety_invariant_count": len(payload.get("safety_invariants", [])),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--enforce-production-ready",
        action="store_true",
        help="exit non-zero when production_admission_state is not ready",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        payload = load_manifest(args.manifest)
        errors = validate_manifest(payload)
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"manifest": str(args.manifest), "valid": False, "errors": [str(exc)]}))
        return 1

    summary = build_summary(args.manifest, payload, errors)
    print(json.dumps(summary, sort_keys=True))
    if errors:
        return 1
    if args.enforce_production_ready and summary["production_admission_state"] != "ready":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
