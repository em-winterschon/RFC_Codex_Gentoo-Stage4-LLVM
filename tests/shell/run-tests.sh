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
bash "${SCRIPT_DIR}/test_ansible_vault_tools.sh"
bash "${SCRIPT_DIR}/test_local_network_inventory.sh"
bash "${SCRIPT_DIR}/test_ntfy_tools.sh"
bash "${SCRIPT_DIR}/test_control_flow_tools.sh"
bash "${SCRIPT_DIR}/test_system_profiles.sh"
bash "${SCRIPT_DIR}/test_container_service_roles.sh"
bash "${SCRIPT_DIR}/test_container_service_image_definitions.sh"
bash "${SCRIPT_DIR}/test_ci_builder_farm_roles.sh"
bash "${SCRIPT_DIR}/test_identity_aaa_roles.sh"
bash "${SCRIPT_DIR}/test_netbox_essential_integrations.sh"
bash "${SCRIPT_DIR}/test_operational_validation_playbooks.sh"
bash "${SCRIPT_DIR}/test_observability_access_roles.sh"
bash "${SCRIPT_DIR}/test_service_validator.sh"
bash "${SCRIPT_DIR}/test_telemetry_observability_roles.sh"
bash "${SCRIPT_DIR}/test_binpkg_repository_roles.sh"
bash "${SCRIPT_DIR}/test_netboot_assets.sh"
bash "${SCRIPT_DIR}/test_routeros_pathb_role.sh"
bash "${SCRIPT_DIR}/test_install_codex_approval_watcher_service.sh"
bash "${SCRIPT_DIR}/test_workflow_manifests.sh"
bash "${SCRIPT_DIR}/test_zfs_layout_specs.sh"
bash "${SCRIPT_DIR}/test_build_stage3_qcow.sh"
bash "${SCRIPT_DIR}/test_validate_llvm_qcow_builder.sh"
bash "${SCRIPT_DIR}/test_generate_cloud_init_seed.sh"
bash "${SCRIPT_DIR}/test_ntfy_tools.sh"
bash "${SCRIPT_DIR}/test_watch_vm_serial.sh"
bash "${SCRIPT_DIR}/test_publish_container_ghcr.sh"
bash "${SCRIPT_DIR}/test_build_gentoo_rootfs_container.sh"
bash "${SCRIPT_DIR}/test_run_container_service_layer_build_pathb.sh"
bash "${SCRIPT_DIR}/test_sync_binpkgs_to_repo.sh"
bash "${SCRIPT_DIR}/test_watch_sync_binpkgs_to_repo.sh"
bash "${SCRIPT_DIR}/test_export_build_metrics.sh"
bash "${SCRIPT_DIR}/test_qemu_memory_drives.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_pathb_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_binpkg_repository_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_container_services_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_elasticsearch_test_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_cloudinit_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_stage3_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_launch_minimal_vm.sh"
bash "${SCRIPT_DIR}/test_qemu_pci_remap.sh"

printf 'PASS: %s\n' "$(basename "$0")"
