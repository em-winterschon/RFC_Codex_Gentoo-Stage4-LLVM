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
  service_readiness \
  netbox_connector \
  zerotier_access \
  container_app_rsyslog_collector \
  container_app_elastic_apm; do
  test -d "${ANSIBLE_ROOT}/roles/${role_dir}"
  test -f "${ANSIBLE_ROOT}/roles/${role_dir}/tasks/main.yml"
done

for profile in \
  logging-rsyslog-client.yml \
  netbox-managed-inventory.yml \
  netbox-pathb-lab-ipam-plan.yml \
  zerotier-managed-access.yml \
  container-rsyslog-collector.yml \
  container-elastic-apm.yml \
  container-haproxy-elasticsearch-test-vip.yml \
  vm-elasticsearch-node.yml \
  vm-elasticsearch-test.yml \
  vm-kibana-interface.yml; do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${profile}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  vm-elasticsearch-node.metadata.yml \
  vm-kibana-interface.metadata.yml; do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${metadata}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${metadata}" '^gentoo_system_profile_metadata:'
done

for package_list in \
  stage5-observability-client.packages \
  stage5-managed-access-zerotier.packages \
  stage5-virtual-host-elasticsearch-node.packages \
  stage5-virtual-host-kibana-interface.packages; do
  test -f "${ANSIBLE_ROOT}/profile-package-lists/${package_list}"
done

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'rsyslog_base'
assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'container_app_rsyslog_collector'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'zerotier_access'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'service_readiness'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'elasticsearch_nodes:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'elasticsearch_test_nodes:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'kibana_interfaces:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/elasticsearch_nodes.yml" '^profile_elasticsearch_cluster:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/kibana_interfaces.yml" '^profile_kibana:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-elasticsearch-node01.yml" '^profile_definition_files:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-elasticsearch-test.yml" 'vm-elasticsearch-test.yml'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-kibana-interface.yml" '^profile_definition_files:'
assert_file_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-elasticsearch-node.packages" '=app-misc/elasticsearch-9.3.1'
assert_file_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-elasticsearch-node.packages" 'net-analyzer/nmap'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-elasticsearch-node.yml" 'package_license_files:'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-elasticsearch-test.yml" 'app-misc/elasticsearch Elastic-2.0'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/telemetry-elasticsearch-exporter.yml" 'app-metrics/elasticsearch_exporter ~amd64'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/telemetry-podman-exporter.yml" 'app-metrics/prometheus-podman-exporter ~amd64'
assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml" 'resolved_portage_package_license_files'
assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml" 'package_license_files'
assert_file_contains "${ANSIBLE_ROOT}/roles/portage/tasks/main.yml" 'package.license'
assert_file_contains "${ANSIBLE_ROOT}/roles/elasticsearch_cluster/templates/elasticsearch.yml.j2" 'xpack.security.enabled'
assert_file_contains "${ANSIBLE_ROOT}/roles/elasticsearch_cluster/templates/elasticsearch.yml.j2" 'action.auto_create_index'
assert_file_contains "${ANSIBLE_ROOT}/roles/elasticsearch_cluster/templates/elasticsearch.yml.j2" 'discovery.type'
assert_file_contains "${ANSIBLE_ROOT}/roles/elasticsearch_cluster/tasks/main.yml" 'ES_JAVA_HOME'
assert_file_contains "${ANSIBLE_ROOT}/roles/elasticsearch_cluster/tasks/main.yml" 'need localmount'
assert_file_contains "${ANSIBLE_ROOT}/roles/elasticsearch_cluster/tasks/main.yml" 'index-templates.d'
assert_file_contains "${ANSIBLE_ROOT}/roles/elasticsearch_cluster/templates/stage5-elasticsearch-apply-index-templates.sh.j2" '_index_template'
assert_file_contains "${ANSIBLE_ROOT}/roles/network/templates/networkmanager-connection.nmconnection.j2" 'mac-address='
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" '/etc/hostid'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_rsyslog_collector/templates/rsyslog.conf.j2" 'module(load="omelasticsearch")'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_rsyslog_collector/templates/rsyslog.conf.j2" 'bulkmode="on"'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_rsyslog_collector/templates/rsyslog.conf.j2" 'esVersion.major'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_rsyslog_collector/templates/rsyslog.conf.j2" 'constant(value="\\",\\"message\\":\\"")'
assert_file_contains "${ANSIBLE_ROOT}/roles/container_app_rsyslog_collector/templates/rsyslog.conf.j2" 'constant(value="\\"}")'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-rsyslog-collector.yml" 'app-admin/rsyslog elasticsearch'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-rsyslog-collector.yml" 'elasticsearch_es_version_major: 9'
assert_file_contains "${ANSIBLE_ROOT}/roles/service_readiness/tasks/validate_check.yml" 'scripts/service_validator.py'
assert_file_contains "${ANSIBLE_ROOT}/roles/service_readiness/tasks/main.yml" 'block:'
assert_file_contains "${ANSIBLE_ROOT}/roles/service_readiness/tasks/main.yml" 'resolved_service_readiness_phase'
assert_file_contains "${ANSIBLE_ROOT}/roles/netbox_connector/templates/netbox-connector.yml.j2" 'planned_prefixes'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/netbox-pathb-lab-ipam-plan.yml" '10.9.8.0/24'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/netbox-pathb-lab-ipam-plan.yml" 'ccr2004-pcie-routeros'
assert_file_contains "${ANSIBLE_ROOT}/roles/telemetry_elasticsearch_exporter/tasks/main.yml" '/var/log/elasticsearch_exporter'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-elasticsearch-test.yml" 'post_boot'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-elasticsearch-test.yml" 'number_of_replicas: 0'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-haproxy-elasticsearch-test-vip.yml" '10.9.8.92:9200'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-haproxy-elasticsearch-test-vip.yml" '10.9.8.91'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/container-haproxy-elasticsearch-test-vip.yml" 'ip -o route get 10.9.8.1'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-jenkins-controller.yml" 'jenkins-http'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-identity-controller.yml" 'freeipa-ldaps'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-observability-prometheus.yml" 'prometheus-http'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/vm-observability-grafana.yml" 'grafana-http'

test -f "${REPO_ROOT}/docs/OBSERVABILITY-ACCESS.md"
test -f "${REPO_ROOT}/docs/wiki/Observability-Access.md"
test -f "${REPO_ROOT}/scripts/service_validator.py"

printf 'PASS: %s\n' "$(basename "$0")"
