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

for role_dir in \
  jenkins_controller \
  distcc_farm
do
  test -d "${ANSIBLE_ROOT}/roles/${role_dir}"
  test -f "${ANSIBLE_ROOT}/roles/${role_dir}/tasks/main.yml"
done

for profile in \
  vm-jenkins-controller.yml \
  metal-builder-farm-node.yml
do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${profile}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  vm-jenkins-controller.metadata.yml \
  metal-builder-farm-node.metadata.yml
do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${metadata}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${metadata}" '^gentoo_system_profile_metadata:'
done

for package_list in \
  stage5-virtual-host-jenkins-controller.packages \
  stage5-metal-host-builder-farm-node.packages
do
  test -f "${ANSIBLE_ROOT}/profile-package-lists/${package_list}"
done

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'jenkins_controller'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'distcc_farm'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'ci_controllers:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'builder_farm_nodes:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-jenkins-controller.yml" '^profile_definition_files:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/builder_farm_nodes.yml" '^profile_definition_files:'

printf 'PASS: %s\n' "$(basename "$0")"
