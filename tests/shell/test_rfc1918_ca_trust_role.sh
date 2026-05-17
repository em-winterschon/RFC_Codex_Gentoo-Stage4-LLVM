#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/rfc1918_ca_trust"
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

assert_file_contains "${ROLE_DIR}/defaults/main.yml" "rfc1918_ca_trust_enabled: false"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "rfc1918_ca_trust_apply: false"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "rfc1918_ca_trust_cert_pem:"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "ansible.builtin.copy:"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "update-ca-certificates"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "update-ca-trust"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "certctl rehash"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "no_log: true"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "rfc1918_ca_trust_apply | bool"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "chroot-runner.sh"
assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" "rfc1918_ca_trust"
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" "rfc1918_ca_trust"
assert_file_contains "${RUN_TESTS}" "test_rfc1918_ca_trust_role.sh"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
