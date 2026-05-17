#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PROFILE_DIR="${ANSIBLE_ROOT}/profile-definitions"
PROFILE="${PROFILE_DIR}/metal-x12again-workstation-xen-coherent.yml"
METADATA="${PROFILE_DIR}/metal-x12again-workstation-xen-coherent.metadata.yml"
DOC="${REPO_ROOT}/docs/X12AGAIN-WORKSTATION-XEN-COHERENT-SCALE.md"
WIKI="${REPO_ROOT}/docs/wiki/X12AGAIN-Workstation-Xen-Coherent-Scale.md"
COHERENT_DOC="${REPO_ROOT}/docs/PROJECT-COHERENT-FLASH-SLURM-SCALE-MODEL.md"
COHERENT_WIKI="${REPO_ROOT}/docs/wiki/Project-Coherent-Flash-SLURM-Scale-Model.md"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"
ROADMAP="${REPO_ROOT}/docs/wiki/Roadmap-and-TODO.md"
CHANGELOG="${REPO_ROOT}/docs/wiki/Changelog.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

for file in "${PROFILE}" "${METADATA}" "${DOC}" "${WIKI}" "${COHERENT_DOC}" "${COHERENT_WIKI}"; do
  test -f "${file}" || fail "missing file: ${file}"
done

assert_file_contains "${RUN_TESTS}" 'test_x12again_reimage_coherent_scale.sh'

assert_file_contains "${PROFILE}" '^gentoo_profile_definition:'
assert_file_contains "${PROFILE}" 'profile_id: metal-x12again-workstation-xen-coherent'
assert_file_contains "${PROFILE}" 'vm-workstation-nscde'
assert_file_contains "${PROFILE}" 'hypervisor-xen-qemu-libvirt-host'
assert_file_contains "${PROFILE}" 'aaa-domain-client'
assert_file_contains "${PROFILE}" 'nfs-storage-client'
assert_file_contains "${PROFILE}" 'slurm-worker-node'
assert_file_contains "${PROFILE}" 'stage5-metal-intel-platform.packages'
assert_file_contains "${PROFILE}" 'stage5-virtual-host-workstation-nscde.packages'
assert_file_contains "${PROFILE}" 'stage5-metal-host-hypervisor.packages'
assert_file_contains "${PROFILE}" 'stage5-storage-nfs-client.packages'
assert_file_contains "${PROFILE}" 'stage5-domain-client.packages'
assert_file_contains "${PROFILE}" 'stage5-slurm-worker-node.packages'
assert_file_contains "${PROFILE}" 'fragments/machine/metal-host.config'
assert_file_contains "${PROFILE}" 'fragments/machine/hypervisor-xen.config'
assert_file_contains "${PROFILE}" 'fragments/machine/hypervisor-qemu-libvirt.config'
assert_file_contains "${PROFILE}" 'fragments/hardware/gpu-universal-xorg.config'
assert_file_contains "${PROFILE}" 'fragments/hardware/optane-nvdimm.config'
assert_file_contains "${PROFILE}" 'fragments/network/roce-v2-host.config'
assert_file_contains "${PROFILE}" 'fragments/storage/rdma-storage-fabric.config'
assert_file_contains "${PROFILE}" 'fragments/storage/nvmeof-initiator.config'
assert_file_contains "${PROFILE}" 'worker_enabled: false'
assert_file_contains "${PROFILE}" 'admission_state: gated-until-e2et-pass'
assert_file_contains "${PROFILE}" 'project_coherent_flash_scale_model'
assert_file_contains "${PROFILE}" 'no_production_storage_mutation: true'

assert_file_contains "${METADATA}" '^gentoo_system_profile_metadata:'
assert_file_contains "${METADATA}" 'id: metal-x12again-workstation-xen-coherent'
assert_file_contains "${METADATA}" 'Intel Optane Persistent Memory 200'
assert_file_contains "${METADATA}" 'BlueField-2'
assert_file_contains "${METADATA}" 'Project Coherent Flash'
assert_file_contains "${METADATA}" 'package_pins:'

for file in "${DOC}" "${WIKI}"; do
  assert_file_contains "${file}" 'ITIL Change Control'
  assert_file_contains "${file}" 'Hard Gates'
  assert_file_contains "${file}" 'Backout'
  assert_file_contains "${file}" 'SLURM Admission'
  assert_file_contains "${file}" 'BlueField2'
  assert_file_contains "${file}" 'Project Coherent Flash'
  assert_file_contains "${file}" 'no production storage mutation'
done

for file in "${COHERENT_DOC}" "${COHERENT_WIKI}"; do
  assert_file_contains "${file}" 'simulation-only'
  assert_file_contains "${file}" 'ADR-001'
  assert_file_contains "${file}" 'ADR-009'
  assert_file_contains "${file}" 'KV/prefix cache'
  assert_file_contains "${file}" 'RAG/vector tier'
  assert_file_contains "${file}" 'DPU boundary'
  assert_file_contains "${file}" 'SLURM'
  assert_file_contains "${file}" 'conformance report'
done

assert_file_contains "${ROADMAP}" 'metal-x12again-workstation-xen-coherent'
assert_file_contains "${ROADMAP}" 'Project Coherent Flash scale model'
assert_file_contains "${CHANGELOG}" 'X12AGAIN Reimage And Coherent Scale Model'

printf 'PASS: %s\n' "$(basename "$0")"
