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
  telemetry_node_exporter \
  telemetry_podman_exporter \
  telemetry_elasticsearch_exporter \
  telemetry_blackbox_exporter \
  telemetry_snmp_exporter \
  telemetry_prometheus \
  telemetry_alertmanager \
  telemetry_grafana \
  container_app_ipmi_exporter \
  container_app_redfish_exporter; do
  test -d "${ANSIBLE_ROOT}/roles/${role_dir}"
  test -f "${ANSIBLE_ROOT}/roles/${role_dir}/tasks/main.yml"
done

for profile in \
  telemetry-node-exporter-client.yml \
  telemetry-podman-exporter.yml \
  telemetry-elasticsearch-exporter.yml \
  container-ipmi-exporter.yml \
  container-redfish-exporter.yml \
  vm-observability-prometheus.yml \
  vm-observability-grafana.yml; do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${profile}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  vm-observability-prometheus.metadata.yml \
  vm-observability-grafana.metadata.yml; do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${metadata}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${metadata}" '^gentoo_system_profile_metadata:'
done

for package_list in \
  stage5-observability-metrics-client.packages \
  stage5-observability-metrics-podman-exporter.packages \
  stage5-observability-metrics-elasticsearch-exporter.packages \
  stage5-virtual-host-observability-prometheus.packages \
  stage5-virtual-host-observability-grafana.packages; do
  test -f "${ANSIBLE_ROOT}/profile-package-lists/${package_list}"
done

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'telemetry_prometheus'
assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'container_app_ipmi_exporter'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'telemetry_blackbox_exporter'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'container_app_redfish_exporter'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'observability_prometheus:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'observability_grafana:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/observability_prometheus.yml" '^profile_telemetry:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/observability_grafana.yml" '^profile_telemetry:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-observability-prometheus.yml" '^profile_definition_files:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-observability-grafana.yml" '^profile_definition_files:'

test -f "${REPO_ROOT}/docs/TELEMETRY-OBSERVABILITY.md"
test -f "${REPO_ROOT}/docs/wiki/Telemetry-Observability.md"

printf 'PASS: %s\n' "$(basename "$0")"
