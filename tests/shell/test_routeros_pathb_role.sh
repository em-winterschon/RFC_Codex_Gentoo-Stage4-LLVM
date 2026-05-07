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

test_routeros_role_assets_exist() {
  assert_file_contains "${ANSIBLE_ROOT}/playbooks/routeros-path-b.yml" "hosts: routeros_pathb"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/defaults/main.yml" "routeros_pathb_boot_mode: uefi-http-ipxe"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/defaults/main.yml" "routeros_pathb_routeros_arch: x86"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/defaults/main.yml" "ZeroTier is documented by MikroTik only for ARM and ARM64 RouterOS targets"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/tasks/main.yml" "Assert Path B RouterOS role is UEFI-only"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/tasks/main.yml" "Classify RouterOS Path B required packages by architecture support"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/tasks/main.yml" "Build RouterOS Path B managed target host list"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/templates/routeros-pathb.rsc.j2" "legacy BIOS is unsupported"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/templates/routeros-pathb.rsc.j2" "Required package missing:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/templates/routeros-pathb-manifest.json.j2" "\"requiredPackages\":"
  assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_pathb/templates/routeros-pathb-manifest.json.j2" "\"unsupportedRequiredPackages\":"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/routeros_pathb.yml" "routeros_pathb_required_packages:"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" "routeros_pathb_primary:"
  assert_file_contains "${REPO_ROOT}/docs/workflows/stage4-routeros-pathb-deployment.json" "\"name\": \"stage4-routeros-pathb-deployment\""
  assert_file_contains "${REPO_ROOT}/docs/ROUTEROS-PATH-B.md" "# RouterOS Path B Role"
  assert_file_contains "${REPO_ROOT}/docs/wiki/RouterOS-Path-B.md" "# RouterOS Path B Role"
}

test_routeros_playbook_syntax() {
  (
    cd "${ANSIBLE_ROOT}"
    ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACKS_ENABLED=control_flow \
      ansible-playbook -i inventories/examples/hosts.yml playbooks/routeros-path-b.yml --syntax-check > /dev/null
  )
}

test_routeros_role_assets_exist
test_routeros_playbook_syntax

printf 'PASS: %s\n' "$(basename "$0")"
