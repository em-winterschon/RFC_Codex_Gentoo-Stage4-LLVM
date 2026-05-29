#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${REPO_ROOT}/docs/workflows/rdma-fabric-promotion-readiness.yml"
VALIDATOR="${REPO_ROOT}/scripts/validate-rdma-promotion-readiness.py"
DOC="${REPO_ROOT}/docs/RDMA-PROMOTION-READINESS.md"
WIKI="${REPO_ROOT}/docs/wiki/RDMA-Promotion-Readiness.md"
RDMA_DOC="${REPO_ROOT}/docs/RDMA-STORAGE-FABRIC-PLAN.md"
NFS_DOC="${REPO_ROOT}/docs/NFS-STORAGE-CLIENT.md"
ROADMAP="${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  test -f "${file}" || fail "missing file ${file}"
  grep -q -- "${pattern}" "${file}" || fail "expected '${pattern}' in ${file}"
}

test -f "${MANIFEST}" || fail "missing file ${MANIFEST}"
test -x "${VALIDATOR}" || fail "missing executable ${VALIDATOR}"
test -f "${DOC}" || fail "missing file ${DOC}"
test -f "${WIKI}" || fail "missing file ${WIKI}"

python3 - "${MANIFEST}" "${VALIDATOR}" << 'PY'
import json
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    raise SystemExit(f"PyYAML missing: {exc}") from exc

manifest = Path(sys.argv[1])
validator = Path(sys.argv[2])
payload = yaml.safe_load(manifest.read_text(encoding="utf-8"))

assert payload["kind"] == "RdmaPromotionReadiness"
assert payload["schema_version"] == 1
assert payload["issue_links"]["rdma_storage_client_baseline"] == 117
assert payload["issue_links"]["vendor_ofed_doca_path"] == 111
assert payload["issue_links"]["fmt2_arista_r630_fabric"] == 130
assert payload["mutation_default"] == "blocked"
assert payload["production_admission_state"] == "blocked"

stage_ids = {stage["id"] for stage in payload["promotion_stages"]}
required_stages = {
    "rdma-storage-client-baseline",
    "vendor-ofed-doca-convergence",
    "fmt2-r630-arista-fabric-admission",
    "pairwise-rdma-smoke",
    "storage-protocol-pilots",
    "failure-injection-and-reboot-conformance",
}
missing = required_stages - stage_ids
assert not missing, sorted(missing)

issue_status = payload["issue_status"]
assert issue_status["117"]["status"] == "baseline-defined"
assert issue_status["117"]["closeable_after_merge"] is True
assert issue_status["111"]["status"] == "live-gated"
assert issue_status["130"]["status"] == "live-gated"

invariants = set(payload["safety_invariants"])
for invariant in (
    "do-not-enable-connectx-lacp-before-pairwise-rdma-and-one-path-failure-pass",
    "do-not-admit-in-kernel-mlx5-as-production-rdma-without-vendor-driver-decision",
    "do-not-enable-nfs-rdma-or-nvme-rdma-before-lossless-class-validation",
    "do-not-mutate-arista-without-pre-change-snapshot-and-rollback-commands",
):
    assert invariant in invariants

result = subprocess.run(
    [str(validator), str(manifest)],
    check=True,
    text=True,
    stdout=subprocess.PIPE,
)
summary = json.loads(result.stdout)
assert summary["manifest"] == str(manifest)
assert summary["production_admission_state"] == "blocked"
assert summary["issues"]["117"]["closeable_after_merge"] is True
assert summary["issues"]["111"]["status"] == "live-gated"
assert summary["issues"]["130"]["status"] == "live-gated"
assert "vendor-ofed-doca-not-installed" in summary["production_blockers"]
assert "pairwise-rdma-smoke-not-run" in summary["production_blockers"]

blocked = subprocess.run(
    [str(validator), str(manifest), "--enforce-production-ready"],
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
assert blocked.returncode == 2
blocked_summary = json.loads(blocked.stdout)
assert blocked_summary["production_admission_state"] == "blocked"
assert blocked_summary["production_blockers"]
PY

assert_file_contains "${MANIFEST}" 'ib_write_bw'
assert_file_contains "${MANIFEST}" 'ibv_rc_pingpong'
assert_file_contains "${MANIFEST}" 'nfs-rdma'
assert_file_contains "${MANIFEST}" 'nvme-rdma'
assert_file_contains "${MANIFEST}" 'iser'
assert_file_contains "${MANIFEST}" 'PFC'
assert_file_contains "${MANIFEST}" 'ECN'
assert_file_contains "${MANIFEST}" 'DSCP'
assert_file_contains "${MANIFEST}" 'one-path-failure'
assert_file_contains "${MANIFEST}" 'reboot-conformance'
assert_file_contains "${DOC}" 'Issue #117 is closeable'
assert_file_contains "${DOC}" 'Issues #111 and #130 remain live-gated'
assert_file_contains "${WIKI}" 'Issue #117 is closeable'
assert_file_contains "${RDMA_DOC}" 'rdma-fabric-promotion-readiness.yml'
assert_file_contains "${NFS_DOC}" 'RDMA promotion readiness gate'
assert_file_contains "${ROADMAP}" 'rdma-fabric-promotion-readiness.yml'

printf 'PASS: %s\n' "$(basename "$0")"
