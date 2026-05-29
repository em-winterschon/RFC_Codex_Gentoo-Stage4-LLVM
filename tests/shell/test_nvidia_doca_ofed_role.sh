#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/nvidia_doca_ofed"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/nvidia-doca-ofed.yml"
DOC="${REPO_ROOT}/docs/HASSLEHOFF-MAINTENANCE-UPGRADE.md"
WIKI="${REPO_ROOT}/docs/wiki/Hasslehoff-Maintenance-Upgrade.md"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

for file in \
  "${ROLE_DIR}/defaults/main.yml" \
  "${ROLE_DIR}/tasks/main.yml" \
  "${PLAYBOOK}" \
  "${DOC}" \
  "${WIKI}"; do
  test -f "${file}"
done

assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_supported_pci_vendor_ids:'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" '15b3'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'BlueField'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'ConnectX-4'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'ConnectX-5'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_required_kernel_modules:'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'mlx5_core'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'mlx5_ib'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_vendor_driver_required: true'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'missing ofed_info'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_roce_validation_commands:'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'ofed_info -s'
if grep -q '{{ item }}' "${ROLE_DIR}/defaults/main.yml"; then
  printf 'FAIL: nvidia_doca_ofed defaults must not contain unbound Jinja item placeholders\n' >&2
  exit 1
fi
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'Preflight-compatible raw command path'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'ansible.builtin.raw: uname -r'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'Detect NVIDIA/Mellanox PCI devices'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'ansible.builtin.raw: >-'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'lspci -Dnn'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'nvidia_doca_ofed_detected_devices'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'Assert NVIDIA/Mellanox device detection before apply'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'nvidia_doca_ofed_skip_device_detection'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'roce_validation_commands'
assert_file_contains "${PLAYBOOK}" 'nvidia_doca_ofed'
assert_file_contains "${DOC}" 'BlueField-2'
assert_file_contains "${DOC}" 'ConnectX-4'
assert_file_contains "${DOC}" 'ConnectX-5'
assert_file_contains "${DOC}" 'lspci -Dnn'
assert_file_contains "${WIKI}" 'BlueField-2'

printf 'PASS: %s\n' "$(basename "$0")"
