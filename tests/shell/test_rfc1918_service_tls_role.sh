#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/rfc1918_service_tls"
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

assert_file_contains "${ROLE_DIR}/defaults/main.yml" "rfc1918_service_tls_enabled: false"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "rfc1918_service_tls_apply: false"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "rfc1918_service_tls_service_ids: []"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "service_tls_certificate_matrix"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "rfc1918_service_tls_apply | bool"
assert_file_contains "${ROLE_DIR}/tasks/deploy_one.yml" "'0600'"
assert_file_contains "${ROLE_DIR}/tasks/deploy_one.yml" "'0644'"
assert_file_contains "${ROLE_DIR}/tasks/deploy_one.yml" "no_log: true"
assert_file_contains "${ROLE_DIR}/tasks/deploy_one.yml" "openssl x509 -noout"
assert_file_contains "${ROLE_DIR}/tasks/deploy_one.yml" "unsafe_writes"
assert_file_contains "${ROLE_DIR}/tasks/deploy_one.yml" "manage_file_modes"
assert_file_contains "${ROLE_DIR}/tasks/deploy_one.yml" "changed_when: true"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_service_tls_certificates"
assert_file_contains "${ROLE_DIR}/handlers/main.yml" "Run rfc1918 service TLS reload commands"
assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" "rfc1918_service_tls"
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" "rfc1918_service_tls"
assert_file_contains "${RUN_TESTS}" "test_rfc1918_service_tls_role.sh"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
