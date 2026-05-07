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

test_netboot_assets_exist() {
  assert_file_contains "${ANSIBLE_ROOT}/playbooks/netboot-path-b.yml" "hosts: netboot_publishers"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_publish_root:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "netboot_boot_type_enum:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/defaults/main.yml" "root=live:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Build resolved Path B host map from install_targets inventory"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Render Path B bootstrap iPXE script"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/tasks/main.yml" "Render Path B MAC dispatch iPXE script"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/bootstrap.ipxe.j2" "chain \${base-url}/hosts/by-mac.ipxe"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/hosts-by-mac.ipxe.j2" "iseq \${net0/mac}"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/menu.ipxe.j2" "RFC Codex Gentoo Stage4 LLVM - Path B iPXE"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "kernel {{ netboot_role.value.kernel_url }} initrd=initramfs.img"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/role.ipxe.j2" "initrd --name initramfs.img"
  assert_file_contains "${ANSIBLE_ROOT}/roles/netboot_assets/templates/netboot-manifest.json.j2" "\"bootType\":"
  assert_file_contains "${ANSIBLE_ROOT}/scripts/build-path-b-netboot-artifacts.sh" "Built Path B netboot artifacts"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/netboot_publishers.yml" "netboot_host_map_extra:"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" "netboot_machine_type: qemu"
  assert_file_contains "${REPO_ROOT}/docs/workflows/stage4-netboot-path-b.json" "\"name\": \"stage4-netboot-path-b\""
}

test_netboot_playbook_syntax() {
  (
    cd "${ANSIBLE_ROOT}"
    ansible-playbook -i inventories/examples/hosts.yml playbooks/netboot-path-b.yml --syntax-check > /dev/null
  )
}

test_netboot_assets_exist
test_netboot_playbook_syntax

printf 'PASS: %s\n' "$(basename "$0")"
