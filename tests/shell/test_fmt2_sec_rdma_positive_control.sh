#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
REPORTER="${REPO_ROOT}/scripts/host_e2et_conformance.py"
MANIFEST="${ANSIBLE_ROOT}/host-e2et-definitions/fmt2-sec-rdma-positive-control.yml"
WORKFLOW="${REPO_ROOT}/docs/workflows/fmt2-sec-rdma-positive-control.json"
FMT2_DOC="${REPO_ROOT}/docs/FMT2-R630-HCI-STAGED-REBUILD.md"
RDMA_DOC="${REPO_ROOT}/docs/RDMA-STORAGE-FABRIC-PLAN.md"

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

test -f "${MANIFEST}"
test -f "${WORKFLOW}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

if "${REPORTER}" --manifest "${MANIFEST}" --json-output "${tmpdir}/sec-rdma.json" --markdown-output "${tmpdir}/sec-rdma.md" > "${tmpdir}/stdout.json"; then
  fail "sec positive-control manifest unexpectedly passed before vendor driver and pairwise RDMA gates"
fi

python3 - "${tmpdir}/sec-rdma.json" "${WORKFLOW}" << 'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
workflow = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert report["host"]["name"] == "kvm_sfo200_sec_9923"
assert report["recommended_release_state"] == "blocked"
assert report["e2et_pass"] is False
assert any(
    failure["check"] == "Vendor OFED or DOCA line is installed and reported"
    for failure in report["hard_failures"]
)
assert any(
    failure["check"] == "Pairwise RDMA smoke tooling is installed"
    for failure in report["hard_failures"]
)

stage_ids = {stage["id"] for stage in workflow["stages"]}
required = {
    "read-only-sec-evidence-capture",
    "switch-positive-control-capture",
    "vendor-driver-preflight",
    "rdma-tooling-gap-closeout",
    "sec-ter-pairwise-rdma-smoke",
    "sec-rdma-admission-report",
}
missing = required - stage_ids
assert not missing, missing
PY

assert_file_contains "${MANIFEST}" 'pre-rdma-admission-discovery-positive'
assert_file_contains "${MANIFEST}" 'ConnectX-4 endpoint enumerates in Linux PCI tree'
assert_file_contains "${MANIFEST}" 'rdma link show reported mlx5_0 and mlx5_1 as ACTIVE'
assert_file_contains "${MANIFEST}" 'DOCA/OFED apply=false preflight detected both ConnectX-4 PCI functions'
assert_file_contains "${MANIFEST}" 'ofed_info is absent'
assert_file_contains "${MANIFEST}" 'placeholder ConnectX MACs'
assert_file_contains "${WORKFLOW}" 'Do not mutate sec storage, pri, ter, or X12AGAIN'
assert_file_contains "${WORKFLOW}" 'same vendor driver family used by ConnectX-4 and BlueField-2'
assert_file_contains "${FMT2_DOC}" 'sec RDMA Positive-Control Path'
assert_file_contains "${RDMA_DOC}" 'positive-control host for the R630 RDMA path'

printf 'PASS: %s\n' "$(basename "$0")"
