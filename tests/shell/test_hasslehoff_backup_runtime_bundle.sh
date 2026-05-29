#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/hasslehoff_backup_scheduler"
DOC="${ROOT_DIR}/docs/HASSLEHOFF-BACKUP.md"
RUN_TESTS="${ROOT_DIR}/tests/shell/run-tests.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_contains "${ROLE_DIR}/defaults/main.yml" "hasslehoff_backup_scheduler_runtime_root: /opt/rfc1918/hasslehoff-backup"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "hasslehoff_backup_scheduler_install_runtime_bundle: true"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "Ensure Hasslehoff backup runtime directories exist"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "Install Hasslehoff backup runtime scripts"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "Install Hasslehoff backup policy"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "Install Hasslehoff backup policy validator"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "backup-hasslehoff-config.sh"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "backup-hasslehoff-scheduled.sh"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "validate-hasslehoff-backup-policy.py"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "hasslehoff_backup_scheduler_runtime_root"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "hasslehoff_backup_scheduler_command:"
assert_file_contains "${DOC}" "/opt/rfc1918/hasslehoff-backup"
assert_file_contains "${DOC}" "runtime bundle"
assert_file_contains "${RUN_TESTS}" "test_hasslehoff_backup_runtime_bundle.sh"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
