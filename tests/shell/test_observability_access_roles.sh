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
  rsyslog_base \
  elasticsearch_cluster \
  kibana_interface \
  netbox_connector \
  zerotier_access \
  container_app_rsyslog_collector \
  container_app_elastic_apm
do
  test -d "${ANSIBLE_ROOT}/roles/${role_dir}"
  test -f "${ANSIBLE_ROOT}/roles/${role_dir}/tasks/main.yml"
done

for profile in \
  logging-rsyslog-client.yml \
  netbox-managed-inventory.yml \
  zerotier-managed-access.yml \
  container-rsyslog-collector.yml \
  container-elastic-apm.yml \
  vm-elasticsearch-node.yml \
  vm-kibana-interface.yml
do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${profile}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  vm-elasticsearch-node.metadata.yml \
  vm-kibana-interface.metadata.yml
do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${metadata}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${metadata}" '^gentoo_system_profile_metadata:'
done

for package_list in \
  stage5-observability-client.packages \
  stage5-managed-access-zerotier.packages \
  stage5-virtual-host-elasticsearch-node.packages \
  stage5-virtual-host-kibana-interface.packages
do
  test -f "${ANSIBLE_ROOT}/profile-package-lists/${package_list}"
done

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'rsyslog_base'
assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'container_app_rsyslog_collector'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'zerotier_access'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'elasticsearch_nodes:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'kibana_interfaces:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/elasticsearch_nodes.yml" '^profile_elasticsearch_cluster:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/kibana_interfaces.yml" '^profile_kibana:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-elasticsearch-node01.yml" '^profile_definition_files:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-kibana-interface.yml" '^profile_definition_files:'

test -f "${REPO_ROOT}/docs/OBSERVABILITY-ACCESS.md"
test -f "${REPO_ROOT}/docs/wiki/Observability-Access.md"

printf 'PASS: %s\n' "$(basename "$0")"
