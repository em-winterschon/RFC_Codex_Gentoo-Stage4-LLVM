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
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

role_defaults="${ANSIBLE_ROOT}/roles/netbox_server/defaults/main.yml"
role_tasks="${ANSIBLE_ROOT}/roles/netbox_server/tasks/main.yml"
role_template="${ANSIBLE_ROOT}/roles/netbox_server/templates/netbox-service.yml.j2"
profile="${ANSIBLE_ROOT}/profile-definitions/vm-netbox-service.yml"
metadata="${ANSIBLE_ROOT}/profile-definitions/vm-netbox-service.metadata.yml"
packages="${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-netbox-service.packages"
install_playbook="${ANSIBLE_ROOT}/playbooks/install.yml"

assert_file_contains "${role_defaults}" "netbox_server_default_version: v4.5.9"
assert_file_contains "${role_defaults}" "dev-db/postgresql"
assert_file_contains "${role_defaults}" "dev-db/redis"
assert_file_contains "${role_defaults}" "www-servers/nginx"
assert_file_contains "${role_defaults}" "net-misc/curl"
assert_file_contains "${role_tasks}" "resolved_profile_netbox_server"
assert_file_contains "${role_tasks}" "40-netbox-service"
assert_file_contains "${role_template}" "deployment_method"
assert_file_contains "${profile}" "vm-netbox-service"
assert_file_contains "${profile}" "version: v4.5.9"
assert_file_contains "${profile}" "service_host: 172.16.99.62"
assert_file_contains "${metadata}" "NetBox is not packaged in the current Gentoo tree"
assert_file_contains "${packages}" "dev-python/virtualenv"
assert_file_contains "${packages}" "net-misc/curl"
assert_file_contains "${install_playbook}" "netbox_server"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
