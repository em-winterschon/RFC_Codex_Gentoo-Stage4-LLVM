#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

test_ntfy_server_role_layout() {
  [[ -f "${ANSIBLE_ROOT}/playbooks/ntfy-server.yml" ]] || fail "missing ntfy-server playbook"
  [[ -f "${ANSIBLE_ROOT}/roles/ntfy_server/defaults/main.yml" ]] || fail "missing ntfy_server defaults"
  [[ -f "${ANSIBLE_ROOT}/roles/ntfy_server/tasks/main.yml" ]] || fail "missing ntfy_server tasks"
  [[ -f "${ANSIBLE_ROOT}/roles/ntfy_server/templates/server.yml.j2" ]] || fail "missing ntfy server config template"
  [[ -f "${ANSIBLE_ROOT}/roles/ntfy_server/templates/ntfy.initd.j2" ]] || fail "missing ntfy init.d template"
  [[ -f "${ANSIBLE_ROOT}/roles/ntfy_server/templates/ntfy.confd.j2" ]] || fail "missing ntfy conf.d template"
}

test_ntfy_server_role_content() {
  assert_file_contains "${ANSIBLE_ROOT}/playbooks/ntfy-server.yml" "hosts: ntfy_servers"
  assert_file_contains "${ANSIBLE_ROOT}/playbooks/ntfy-server.yml" "role: ntfy_server"
  assert_file_contains "${ANSIBLE_ROOT}/roles/ntfy_server/defaults/main.yml" "ntfy_server_install_method: binary"
  assert_file_contains "${ANSIBLE_ROOT}/roles/ntfy_server/defaults/main.yml" "ntfy_server_auth_default_access: deny-all"
  assert_file_contains "${ANSIBLE_ROOT}/roles/ntfy_server/templates/server.yml.j2" "listen-http:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/ntfy_server/templates/server.yml.j2" "cache-file:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/ntfy_server/templates/server.yml.j2" "auth-default-access:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/ntfy_server/templates/server.yml.j2" "auth-users:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/ntfy_server/templates/ntfy.initd.j2" "supervisor=\"supervise-daemon\""
  assert_file_contains "${ANSIBLE_ROOT}/roles/ntfy_server/templates/ntfy.confd.j2" "command_args=\"serve\""
  assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/ntfy_servers.yml" "ntfy_server_auth_users:"
  assert_file_contains "${REPO_ROOT}/docs/workflows/ntfy-server-deployment.json" "\"name\": \"ntfy-server-deployment\""
}

test_ntfy_server_role_layout
test_ntfy_server_role_content

printf 'PASS: %s\n' "$(basename "$0")"
