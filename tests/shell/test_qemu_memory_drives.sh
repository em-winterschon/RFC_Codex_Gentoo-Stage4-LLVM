#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q "${pattern}" "${file}"
}

test -f "${ANSIBLE_ROOT}/playbooks/qemu-memory-drives.yml"
test -f "${ANSIBLE_ROOT}/roles/qemu_memory_drives/tasks/main.yml"
test -f "${ANSIBLE_ROOT}/roles/qemu_memory_drives/templates/memory-drives.json.j2"
test -f "${ANSIBLE_ROOT}/inventories/examples/group_vars/qemu_hypervisors.yml"

assert_file_contains "${ANSIBLE_ROOT}/playbooks/qemu-memory-drives.yml" 'hosts: qemu_hypervisors'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/qemu_hypervisors.yml" '^qemu_memory_drives_enabled:'
assert_file_contains "${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-stage3-vm.sh" 'QEMU_MEMORY_DRIVES_FILE'

printf 'PASS: %s\n' "$(basename "$0")"
