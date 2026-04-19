#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

mapfile -t shell_scripts < <(find \
  "${REPO_ROOT}/gentoo-virt-qemu" \
  "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/scripts" \
  "${REPO_ROOT}/tests/shell" \
  -type f -name '*.sh' | sort)

for script in "${shell_scripts[@]}"; do
  bash -n "${script}"
done

"${SCRIPT_DIR}/test_generate_ansible_python_setup.sh"
"${SCRIPT_DIR}/test_qemu_launch_minimal_vm.sh"
"${SCRIPT_DIR}/test_qemu_pci_remap.sh"

printf 'PASS: %s\n' "$(basename "$0")"
