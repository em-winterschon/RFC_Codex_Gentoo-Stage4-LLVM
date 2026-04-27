#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROFILE_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions"
HOST_VARS_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/examples/host_vars"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q "${pattern}" "${file}"
}

for profile in \
  llvm-clang-hardened-portage.yml \
  hypervisor-xen-qemu-libvirt-host.yml \
  vm-container-services.yml \
  vm-guest-application-server.yml \
  vm-guest-simple-ipxe.yml
do
  test -f "${PROFILE_DIR}/${profile}"
  assert_file_contains "${PROFILE_DIR}/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  hypervisor-xen-qemu-libvirt-host.metadata.yml \
  vm-container-services.metadata.yml \
  vm-guest-application-server.metadata.yml \
  vm-guest-simple-ipxe.metadata.yml
do
  test -f "${PROFILE_DIR}/${metadata}"
  assert_file_contains "${PROFILE_DIR}/${metadata}" '^gentoo_system_profile_metadata:'
done

for host_var in \
  hypervisor-host.yml \
  vm-container-services.yml \
  vm-guest-appserver.yml \
  vm-guest-simple.yml
do
  test -f "${HOST_VARS_DIR}/${host_var}"
  assert_file_contains "${HOST_VARS_DIR}/${host_var}" '^profile_definition_files:'
done

printf 'PASS: %s\n' "$(basename "$0")"
