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
  container_host \
  container_app_ntfy \
  container_app_nginx \
  container_app_haproxy \
  container_net_policy \
  container_service_segments
do
  test -d "${ANSIBLE_ROOT}/roles/${role_dir}"
  test -f "${ANSIBLE_ROOT}/roles/${role_dir}/tasks/main.yml"
done

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'container_host'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'container_service_segments'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-service-base-image.yml" '^gentoo_profile_definition:'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-service-base-image.yml" 'ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc:latest'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-service-base-image.yml" 'ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc:git-e5bf45f'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-service-base-image.yml" 'sha256:4c0cc158b9ab55f7b126dcd80deb8327959a0fd8cd132af7fa09a438df4e85b6'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-container-services.yml" '^gentoo_profile_definition:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-container-services.yml" '^profile_definition_files:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-container-services.yml" 'container-service-base-image.yml'
assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml" 'resolved_profile_container_base_image'
assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml" 'container_base_image'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_host/tasks/main.yml" 'base-image.yml'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_host/templates/base-image.yml.j2" 'resolved_profile_container_base_image'

printf 'PASS: %s\n' "$(basename "$0")"
