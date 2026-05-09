#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/vm_redfish_emulator"
PROFILE="${ANSIBLE_ROOT}/profile-definitions/vm-redfish-emulator.yml"
METADATA="${ANSIBLE_ROOT}/profile-definitions/vm-redfish-emulator.metadata.yml"
PACKAGES="${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-redfish-emulator.packages"
INSTALL_SEQUENCES="${ANSIBLE_ROOT}/vars/install_sequences.yml"
PREFLIGHT_MAIN="${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml"
PREFLIGHT_LOAD="${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -Eq -- "${pattern}" "${file}" || fail "missing pattern '${pattern}' in ${file}"
}

for path in \
  "${ROLE_DIR}/defaults/main.yml" \
  "${ROLE_DIR}/tasks/main.yml" \
  "${ROLE_DIR}/templates/sushy-emulator.conf.j2" \
  "${ROLE_DIR}/templates/vm-redfish-emulator.initd.j2" \
  "${PROFILE}" \
  "${METADATA}" \
  "${PACKAGES}"; do
  [[ -f "${path}" ]] || fail "missing file: ${path}"
done

assert_file_contains "${PROFILE}" "vm_redfish_emulator:"
assert_file_contains "${PROFILE}" "sushy-tools-libvirt"
assert_file_contains "${PROFILE}" "qemu:///system"
assert_file_contains "${METADATA}" "docs.openstack.org/sushy-tools"
assert_file_contains "${METADATA}" "DMTF/Redfish-Interface-Emulator"
assert_file_contains "${PACKAGES}" "^app-emulation/libvirt$"
assert_file_contains "${PACKAGES}" "^app-emulation/qemu$"
assert_file_contains "${PACKAGES}" "^dev-python/pip$"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "sushy-tools"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "Create VM Redfish emulator virtualenv"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "Install VM Redfish emulator Python packages"
assert_file_contains "${ROLE_DIR}/templates/vm-redfish-emulator.initd.j2" "SUSHY_EMULATOR_CONFIG"
assert_file_contains "${ROLE_DIR}/templates/sushy-emulator.conf.j2" "SUSHY_EMULATOR_LIBVIRT_URI"
assert_file_contains "${INSTALL_SEQUENCES}" "vm_redfish_emulator"
assert_file_contains "${PREFLIGHT_MAIN}" "resolved_profile_vm_redfish_emulator"
assert_file_contains "${PREFLIGHT_LOAD}" "gentoo_profile_definition.vm_redfish_emulator"

printf 'PASS: %s\n' "$(basename "$0")"
