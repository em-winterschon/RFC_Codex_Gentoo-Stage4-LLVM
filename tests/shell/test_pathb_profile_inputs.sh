#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PATHB_SCRIPT="${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}'"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

PATHB_BUILD_DRY_RUN=1
QEMU_STAGE3_BUILD_DRY_RUN=1
PATHB_PROFILE_DEFINITION_FILES='profile-definitions/aaa-domain-client.yml'
PATHB_EXTRA_PACKAGES='app-admin/sudo'
PATHB_PACKAGE_USE_APPEND=''
PATHB_PROFILE_PACKAGE_LIST_FILES=''
PATHB_OPENRC_SERVICES_EXTRA=''

# shellcheck disable=SC1090
source "${PATHB_SCRIPT}"

resolve_pathb_profile_inputs

assert_contains "${PATHB_PROFILE_PACKAGE_LIST_FILES}" 'profile-package-lists/stage5-domain-client.packages'
assert_contains "${PATHB_EXTRA_PACKAGES}" 'sys-auth/sssd'
assert_contains "${PATHB_EXTRA_PACKAGES}" 'net-fs/samba'
assert_contains "${PATHB_EXTRA_PACKAGES}" 'app-crypt/mit-krb5'
assert_contains "${PATHB_PACKAGE_USE_APPEND}" 'sys-auth/sssd samba'
assert_contains "${PATHB_PACKAGE_USE_APPEND}" 'net-fs/samba winbind'
assert_contains "${PATHB_OPENRC_SERVICES_EXTRA}" 'sssd'

assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'PATHB_PROFILE_DEFINITION_FILES'
assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'PATHB_ACCEPT_LICENSE_APPEND'
assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'linux-fw-redistributable'
assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'profile_definition_query'
assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'openrc-services-enable'
assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" 'rc-update add "\${pathb_extra_service}" default'

printf 'PASS: %s\n' "$(basename "$0")"
