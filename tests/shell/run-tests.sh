#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

mapfile -t shell_scripts < <(find \
  "${REPO_ROOT}/scripts" \
  "${REPO_ROOT}/gentoo-virt-qemu" \
  "${REPO_ROOT}/scripts" \
  "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/scripts" \
  "${REPO_ROOT}/tests/shell" \
  -type f -name '*.sh' | sort)

for script in "${shell_scripts[@]}"; do
  bash -n "${script}"
done

bash "${SCRIPT_DIR}/test_generate_ansible_python_setup.sh"
bash "${SCRIPT_DIR}/test_ntfy_tools.sh"
bash "${SCRIPT_DIR}/test_control_flow_tools.sh"
bash "${SCRIPT_DIR}/test_system_profiles.sh"
bash "${SCRIPT_DIR}/test_container_service_roles.sh"
bash "${SCRIPT_DIR}/test_netboot_assets.sh"
bash "${SCRIPT_DIR}/test_routeros_pathb_role.sh"
bash "${SCRIPT_DIR}/test_install_codex_approval_watcher_service.sh"
bash "${SCRIPT_DIR}/test_workflow_manifests.sh"
bash "${SCRIPT_DIR}/test_zfs_layout_specs.sh"
bash "${SCRIPT_DIR}/test_build_stage3_qcow.sh"
bash "${SCRIPT_DIR}/test_validate_llvm_qcow_builder.sh"
bash "${SCRIPT_DIR}/test_generate_cloud_init_seed.sh"
bash "${SCRIPT_DIR}/test_ntfy_tools.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_cloudinit_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_stage3_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_minimal_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_pci_remap.sh"

printf 'PASS: %s\n' "$(basename "$0")"
