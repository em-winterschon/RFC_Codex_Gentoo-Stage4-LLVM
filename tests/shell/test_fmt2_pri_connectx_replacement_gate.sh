#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
REPORTER="${REPO_ROOT}/scripts/host_e2et_conformance.py"
MANIFEST="${ANSIBLE_ROOT}/host-e2et-definitions/fmt2-pri-rdma-admission.yml"
WORKFLOW="${REPO_ROOT}/docs/workflows/fmt2-pri-connectx-replacement.json"
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

if "${REPORTER}" --manifest "${MANIFEST}" --json-output "${tmpdir}/pri-rdma.json" --markdown-output "${tmpdir}/pri-rdma.md" > "${tmpdir}/stdout.json"; then
  fail "blocked pri RDMA manifest unexpectedly exited 0"
fi

python3 - "${tmpdir}/pri-rdma.json" "${WORKFLOW}" << 'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
workflow = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert report["host"]["name"] == "kvm_sfo200_pri_9922"
assert report["recommended_release_state"] == "blocked"
assert report["e2et_pass"] is False
assert any(
    failure["check"] == "ConnectX endpoint enumerates in Linux PCI tree"
    for failure in report["hard_failures"]
)
assert any(
    failure["check"] == "Arista LLDP sees pri ConnectX neighbor"
    for failure in report["hard_failures"]
)

stage_ids = {stage["id"] for stage in workflow["stages"]}
required = {
    "pre-change-freeze",
    "pre-swap-evidence-capture",
    "power-off-maintenance-window",
    "physical-replacement",
    "post-swap-host-inventory",
    "post-swap-arista-validation",
    "rdma-admission-e2et",
}
missing = required - stage_ids
assert not missing, missing
PY

assert_file_contains "${MANIFEST}" 'pre-rdma-admission-blocked'
assert_file_contains "${MANIFEST}" 'Slot 1 reports populated after replacement'
assert_file_contains "${MANIFEST}" 'ofed_info cannot be accepted until the replacement ConnectX endpoint is visible'
assert_file_contains "${WORKFLOW}" 'Do not touch sec, ter, or X12AGAIN'
assert_file_contains "${WORKFLOW}" 'record model, PSID, serial, port MACs'
assert_file_contains "${FMT2_DOC}" 'Physical ConnectX Replacement Path'
assert_file_contains "${RDMA_DOC}" 'physical ConnectX replacement path'

printf 'PASS: %s\n' "$(basename "$0")"
