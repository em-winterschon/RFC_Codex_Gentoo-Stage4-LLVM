#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PROFILE="${ANSIBLE_ROOT}/profile-definitions/metal-fmt2-r630-openstack-roce.yml"
METADATA="${ANSIBLE_ROOT}/profile-definitions/metal-fmt2-r630-openstack-roce.metadata.yml"
RDMA_FRAGMENT="${ANSIBLE_ROOT}/kernel-config/fragments/storage/rdma-storage-fabric.config"
FMT2_DOC="${REPO_ROOT}/docs/FMT2-R630-HCI-STAGED-REBUILD.md"
RDMA_DOC="${REPO_ROOT}/docs/RDMA-STORAGE-FABRIC-PLAN.md"
FMT2_INVENTORY="${ANSIBLE_ROOT}/inventory-intake/sites/fmt2.yml"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

test -f "${PROFILE}"
test -f "${METADATA}"

assert_file_contains "${PROFILE}" 'profile_id: metal-fmt2-r630-openstack-roce'
assert_file_contains "${PROFILE}" 'kernel_strategy: gentoo-kernel'
assert_file_contains "${PROFILE}" 'kernel_package_atom_override: =sys-kernel/gentoo-kernel-6.18.18'
assert_file_contains "${PROFILE}" 'stage5-metal-intel-platform.packages'
assert_file_contains "${PROFILE}" 'stage5-base-hypervisor-qemu-libvirt.packages'
assert_file_contains "${PROFILE}" 'stage5-storage-nfs-client.packages'
assert_file_contains "${PROFILE}" 'stage5-domain-client.packages'
assert_file_contains "${PROFILE}" 'stage5-observability-client.packages'
assert_file_contains "${PROFILE}" 'fragments/machine/hypervisor-qemu-libvirt.config'
assert_file_contains "${PROFILE}" 'fragments/network/roce-v2-host.config'
assert_file_contains "${PROFILE}" 'fragments/storage/rdma-storage-fabric.config'
assert_file_contains "${PROFILE}" 'fragments/storage/nvmeof-initiator.config'
assert_file_contains "${PROFILE}" 'fragments/storage/nfs-client.config'
assert_file_contains "${PROFILE}" 'mlx5_core'
assert_file_contains "${PROFILE}" 'mlx5_ib'
assert_file_contains "${PROFILE}" 'nvme-rdma'
assert_file_contains "${PROFILE}" 'rpcrdma'
assert_file_contains "${PROFILE}" 'openvswitch'
assert_file_contains "${PROFILE}" 'rdma_admission_state: gated-until-ofed-and-roce-e2et-pass'
assert_file_contains "${PROFILE}" 'required_variable: fmt2_r630_reimage_apply_required'

assert_file_contains "${METADATA}" '^gentoo_system_profile_metadata:'
assert_file_contains "${METADATA}" 'id: metal-fmt2-r630-openstack-roce'
assert_file_contains "${METADATA}" '=sys-kernel/gentoo-kernel-6.18.18'
assert_file_contains "${METADATA}" 'ConnectX-4'
assert_file_contains "${METADATA}" 'Arista DCS-7060CX-32S'

assert_file_contains "${RDMA_FRAGMENT}" 'CONFIG_INFINIBAND_ISER=m'
assert_file_contains "${RDMA_FRAGMENT}" 'CONFIG_DM_MULTIPATH=m'

assert_file_contains "${FMT2_DOC}" 'Gentoo stage4 kernel pivot'
assert_file_contains "${FMT2_DOC}" 'metal-fmt2-r630-openstack-roce'
assert_file_contains "${FMT2_DOC}" '=sys-kernel/gentoo-kernel-6.18.18'
assert_file_contains "${FMT2_DOC}" 'diagnostic-only'
assert_file_contains "${RDMA_DOC}" 'Gentoo stage4 R630 admission target'
assert_file_contains "${RDMA_DOC}" 'in-kernel `mlx5_core` remains discovery-only'
assert_file_contains "${FMT2_INVENTORY}" 'stage4_profile: metal-fmt2-r630-openstack-roce'

printf 'PASS: %s\n' "$(basename "$0")"
