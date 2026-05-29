#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKFLOW="${REPO_ROOT}/docs/workflows/fmt2-kolla-storage-rdma-promotion.json"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

test -f "${WORKFLOW}"

python3 - "${WORKFLOW}" << 'PY'
import json
import sys
from pathlib import Path

workflow = Path(sys.argv[1])
payload = json.loads(workflow.read_text(encoding="utf-8"))

if payload.get("kind") != "WorkflowManifest":
    raise SystemExit("workflow kind must be WorkflowManifest")

stage_ids = {stage["id"] for stage in payload.get("stages", [])}
required = {
    "api-baseline-gate",
    "glance-image-smoke",
    "nova-ephemeral-smoke",
    "nfs-backend-smoke",
    "cinder-nfs-pilot",
    "pairwise-rocev2-rdma-smoke",
    "nvmeof-iser-pilot",
    "nfs-rdma-pilot",
    "one-path-failure-reboot-conformance",
}
missing = required - stage_ids
if missing:
    raise SystemExit(f"missing required stages: {sorted(missing)}")
PY

assert_file_contains "${WORKFLOW}" 'Cinder remains disabled before promotion'
assert_file_contains "${WORKFLOW}" 'API/control plane baseline with Cinder disabled'
assert_file_contains "${WORKFLOW}" 'Glance image import/export smoke'
assert_file_contains "${WORKFLOW}" 'Nova ephemeral instance smoke'
assert_file_contains "${WORKFLOW}" 'NFS backend smoke'
assert_file_contains "${WORKFLOW}" 'NFSv3/NFSv4 backend smoke from NASA or ter'
assert_file_contains "${WORKFLOW}" 'Cinder NFS backend pilot'
assert_file_contains "${WORKFLOW}" 'Pairwise RoCEv2 RDMA smoke between sec and ter, then pri after ConnectX repair'
assert_file_contains "${WORKFLOW}" 'NVMe-oF promotion gate'
assert_file_contains "${WORKFLOW}" 'NVMe-oF or iSER backend pilot'
assert_file_contains "${WORKFLOW}" 'NFS-RDMA promotion gate'
assert_file_contains "${WORKFLOW}" 'NFS-RDMA backend pilot'
assert_file_contains "${WORKFLOW}" 'one-path-failure'
assert_file_contains "${WORKFLOW}" 'reboot conformance'
assert_file_contains "${WORKFLOW}" 'do not use ConnectX LACP before pairwise RDMA evidence'
assert_file_contains "${WORKFLOW}" 'independent 50GbE links with protocol-layer multipath'
assert_file_contains "${WORKFLOW}" 'keep RDMA out of OpenStack scheduling'

printf 'PASS: %s\n' "$(basename "$0")"
