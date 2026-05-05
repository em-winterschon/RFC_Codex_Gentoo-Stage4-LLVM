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
  freeipa_controller \
  ipa_client \
  freeradius_bridge
do
  test -d "${ANSIBLE_ROOT}/roles/${role_dir}"
  test -f "${ANSIBLE_ROOT}/roles/${role_dir}/tasks/main.yml"
done

for profile in \
  aaa-domain-client.yml \
  vm-identity-controller.yml \
  metal-identity-controller.yml
do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${profile}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  aaa-domain-client.metadata.yml \
  vm-identity-controller.metadata.yml \
  metal-identity-controller.metadata.yml
do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${metadata}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${metadata}" '^gentoo_system_profile_metadata:'
done

for package_list in \
  stage5-domain-client.packages \
  stage5-virtual-host-identity-controller.packages \
  stage5-metal-host-identity-controller.packages
do
  test -f "${ANSIBLE_ROOT}/profile-package-lists/${package_list}"
done

test -f "${ANSIBLE_ROOT}/aaa-policy-definitions/site-baseline.yml"
assert_file_contains "${ANSIBLE_ROOT}/aaa-policy-definitions/site-baseline.yml" '^aaa_policy_definition:'

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'freeipa_controller'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'freeradius_bridge'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'identity_controllers:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'aaa_domain_clients:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/identity_controllers.yml" '^profile_freeipa_controller:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/aaa_domain_clients.yml" '^profile_ipa_client:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-identity-controller.yml" '^profile_definition_files:'

test -f "${REPO_ROOT}/docs/IDENTITY-AAA.md"
test -f "${REPO_ROOT}/docs/wiki/Identity-AAA.md"
test -x "${REPO_ROOT}/scripts/configure-freeradius-freeipa.sh"
assert_file_contains "${REPO_ROOT}/scripts/configure-freeradius-freeipa.sh" 'codex-admin'
assert_file_contains "${REPO_ROOT}/scripts/configure-freeradius-freeipa.sh" 'network-readonly'
assert_file_contains "${REPO_ROOT}/scripts/configure-freeradius-freeipa.sh" 'FreeRADIUS FreeIPA bridge validated'

printf 'PASS: %s\n' "$(basename "$0")"
