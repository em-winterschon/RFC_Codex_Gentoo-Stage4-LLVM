#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
REPORTER="${REPO_ROOT}/scripts/host_e2et_conformance.py"
MANIFEST="${ANSIBLE_ROOT}/host-e2et-definitions/fmt2-r630-kolla-podman-rocky10.yml"

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

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

if "${REPORTER}" --manifest "${MANIFEST}" --json-output "${tmpdir}/kolla-e2et.json" --markdown-output "${tmpdir}/kolla-e2et.md" > "${tmpdir}/stdout.json"; then
  fail "FMT2 Kolla E2ET manifest unexpectedly passed before live deployment evidence"
fi

python3 - "${tmpdir}/kolla-e2et.json" << 'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

assert report["host"]["name"] == "fmt2_r630_kolla_podman_rocky10"
assert report["recommended_release_state"] == "blocked"
assert report["e2et_pass"] is False
assert any(
    failure["check"] == "Rocky Linux 10 installed on approved OS mirror media"
    for failure in report["hard_failures"]
)
assert any(
    failure["check"] == "kolla-ansible prechecks passed"
    for failure in report["hard_failures"]
)
assert any(
    failure["check"] == "OpenStack smoke instance reached ACTIVE"
    for failure in report["hard_failures"]
)
PY

assert_file_contains "${MANIFEST}" 'Rocky Linux 10'
assert_file_contains "${MANIFEST}" 'Kolla-Ansible'
assert_file_contains "${MANIFEST}" 'Podman'
assert_file_contains "${MANIFEST}" 'kolla-ansible prechecks'
assert_file_contains "${MANIFEST}" 'openstack hypervisor list'
assert_file_contains "${MANIFEST}" 'SOL remains enabled'
assert_file_contains "${MANIFEST}" 'Cinder disabled for first-pass baseline'
assert_file_contains "${MANIFEST}" 'rsyslog, node exporter, Check_MK, NTP, CA trust, and AAA validated'

printf 'PASS: %s\n' "$(basename "$0")"
