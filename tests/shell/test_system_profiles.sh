#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROFILE_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions"
PACKAGE_LIST_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists"
HOST_VARS_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/examples/host_vars"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q "${pattern}" "${file}"
}

for profile in \
  cloud-init-baremetal.yml \
  cloud-init-vm.yml \
  llvm-clang-hardened-portage.yml \
  hypervisor-xen-qemu-libvirt-host.yml \
  metal-builder-farm-node.yml \
  vm-container-services.yml \
  vm-jenkins-controller.yml \
  vm-guest-application-server.yml \
  vm-guest-simple-ipxe.yml
do
  test -f "${PROFILE_DIR}/${profile}"
  assert_file_contains "${PROFILE_DIR}/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  cloud-init-baremetal.metadata.yml \
  cloud-init-vm.metadata.yml \
  hypervisor-xen-qemu-libvirt-host.metadata.yml \
  metal-builder-farm-node.metadata.yml \
  vm-container-services.metadata.yml \
  vm-jenkins-controller.metadata.yml \
  vm-guest-application-server.metadata.yml \
  vm-guest-simple-ipxe.metadata.yml
do
  test -f "${PROFILE_DIR}/${metadata}"
  assert_file_contains "${PROFILE_DIR}/${metadata}" '^gentoo_system_profile_metadata:'
done

for host_var in \
  hypervisor-host.yml \
  vm-jenkins-controller.yml \
  vm-container-services.yml \
  vm-guest-appserver.yml \
  vm-guest-simple.yml
do
  test -f "${HOST_VARS_DIR}/${host_var}"
  assert_file_contains "${HOST_VARS_DIR}/${host_var}" '^profile_definition_files:'
done

for package_list in \
  cloud-init-base.packages \
  stage5-metal-host-builder-farm-node.packages \
  stage5-metal-host-hypervisor.packages \
  stage5-virtual-host-base.packages \
  stage5-virtual-host-appserver.packages \
  stage5-virtual-host-jenkins-controller.packages \
  stage5-virtual-host-container-services.packages
do
  test -f "${PACKAGE_LIST_DIR}/${package_list}"
done

printf 'PASS: %s\n' "$(basename "$0")"
