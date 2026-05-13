#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/x12again-reimage-preflight.yml"
HOST_VARS="${ANSIBLE_ROOT}/inventories/local-network/host_vars/x12again_workstation_xen_coherent.yml"
LOCAL_INVENTORY="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
MANIFEST="${ANSIBLE_ROOT}/host-e2et-definitions/x12again-reimage-preflight.yml"
DOC="${REPO_ROOT}/docs/X12AGAIN-REIMAGE-PREFLIGHT.md"
WIKI="${REPO_ROOT}/docs/wiki/X12AGAIN-Reimage-Preflight.md"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  test -f "${file}" || fail "missing file ${file}"
  grep -q -- "${pattern}" "${file}" || fail "expected ${pattern} in ${file}"
}

for file in "${PLAYBOOK}" "${HOST_VARS}" "${MANIFEST}" "${DOC}" "${WIKI}"; do
  test -f "${file}" || fail "missing file ${file}"
done

assert_file_contains "${RUN_TESTS}" 'test_x12again_live_reimage_preflight.sh'

assert_file_contains "${LOCAL_INVENTORY}" 'reimage_candidates:'
assert_file_contains "${LOCAL_INVENTORY}" 'x12again_workstation_xen_coherent:'
assert_file_contains "${LOCAL_INVENTORY}" 'stage5_profile: metal-x12again-workstation-xen-coherent'

assert_file_contains "${HOST_VARS}" 'x12again_reimage_apply_required: false'
assert_file_contains "${HOST_VARS}" 'x12again_reimage_backup_verified: false'
assert_file_contains "${HOST_VARS}" 'x12again_reimage_services_offloaded_verified: false'
assert_file_contains "${HOST_VARS}" 'x12again_reimage_emergency_console_verified: false'
assert_file_contains "${HOST_VARS}" 'x12again_reimage_human_change_window_approved: false'
assert_file_contains "${HOST_VARS}" 'netboot_enabled: false'

assert_file_contains "${PLAYBOOK}" 'x12again_reimage_apply_required'
assert_file_contains "${PLAYBOOK}" 'x12again_reimage_backup_verified'
assert_file_contains "${PLAYBOOK}" 'x12again_reimage_services_offloaded_verified'
assert_file_contains "${PLAYBOOK}" 'x12again_reimage_emergency_console_verified'
assert_file_contains "${PLAYBOOK}" 'x12again_reimage_human_change_window_approved'
assert_file_contains "${PLAYBOOK}" 'metal-x12again-workstation-xen-coherent'
assert_file_contains "${PLAYBOOK}" 'no_production_storage_mutation'
assert_file_contains "${PLAYBOOK}" 'worker_enabled'
assert_file_contains "${PLAYBOOK}" 'host_e2et_conformance.py'
assert_file_contains "${PLAYBOOK}" 'Destructive X12AGAIN reimage gates are not satisfied'

assert_file_contains "${MANIFEST}" 'x12again-reimage-preflight-20260513'
assert_file_contains "${MANIFEST}" 'Backup Gate'
assert_file_contains "${MANIFEST}" 'Service Continuity Gate'
assert_file_contains "${MANIFEST}" 'Serial And OOB Gate'
assert_file_contains "${MANIFEST}" 'Mutation Gate'
assert_file_contains "${MANIFEST}" 'status: fail'
assert_file_contains "${MANIFEST}" 'hard_fail: true'

assert_file_contains "${DOC}" 'No-Mutation Default'
assert_file_contains "${DOC}" 'Required Live Gates'
assert_file_contains "${DOC}" 'Backout Boundary'
assert_file_contains "${DOC}" 'x12again_reimage_apply_required=true'
assert_file_contains "${DOC}" 'Destructive disk mutation is blocked'

assert_file_contains "${WIKI}" 'No-Mutation Default'
assert_file_contains "${WIKI}" 'Required Live Gates'

if command -v ansible-playbook >/dev/null 2>&1; then
  ansible-playbook -i "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "${PLAYBOOK}" --syntax-check >/dev/null
fi

printf 'PASS: %s\n' "$(basename "$0")"
