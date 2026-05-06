#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/workstation_session_stack"
PROFILE_FILE="${ANSIBLE_ROOT}/profile-definitions/vm-workstation-nscde.yml"
PACKAGE_LIST="${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-workstation-nscde.packages"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  grep -Eq "${pattern}" "${file}" || fail "expected ${file} to contain pattern: ${pattern}"
}

assert_file_exists() {
  local file="$1"
  [[ -f "${file}" ]] || fail "expected file to exist: ${file}"
}

assert_file_exists "${ROLE_DIR}/defaults/main.yml"
assert_file_exists "${ROLE_DIR}/tasks/main.yml"
assert_file_exists "${ROLE_DIR}/tasks/gentoo.yml"
assert_file_exists "${ROLE_DIR}/tasks/freebsd.yml"
assert_file_exists "${ROLE_DIR}/tasks/debian.yml"
assert_file_exists "${ROLE_DIR}/tasks/solaris.yml"
assert_file_exists "${ROLE_DIR}/templates/xinitrc.j2"
assert_file_exists "${ROLE_DIR}/templates/xsession.desktop.j2"
assert_file_exists "${ROLE_DIR}/templates/slim.conf.j2"

assert_file_contains "${ROLE_DIR}/defaults/main.yml" '^workstation_session_stack_default_enabled: false$'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'devuan: debian'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'tribblix-ce: solaris'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'openindiana: solaris'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'workstation_session_stack_os_family'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'workstation_session_stack_os_family_aliases.get'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'workstation_session_stack_supported_os_families'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'include_tasks: "\{\{ workstation_session_stack_os_family \}\}\.yml"'
assert_file_contains "${ROLE_DIR}/tasks/gentoo.yml" 'x11-misc/slim'
assert_file_contains "${ROLE_DIR}/tasks/gentoo.yml" 'emerge'
assert_file_contains "${ROLE_DIR}/tasks/freebsd.yml" 'pkg install -y'
assert_file_contains "${ROLE_DIR}/tasks/debian.yml" 'apt-get install -y'
assert_file_contains "${ROLE_DIR}/tasks/solaris.yml" 'pkg install'

assert_file_contains "${PROFILE_FILE}" '^  workstation_session_stack:$'
assert_file_contains "${PROFILE_FILE}" 'desktop_environments:'
assert_file_contains "${PROFILE_FILE}" 'id: nscde'
assert_file_contains "${PROFILE_FILE}" 'display_managers:'
assert_file_contains "${PROFILE_FILE}" 'id: slim'
assert_file_contains "${PACKAGE_LIST}" '^x11-misc/slim$'

printf 'PASS: %s\n' "$(basename "$0")"
