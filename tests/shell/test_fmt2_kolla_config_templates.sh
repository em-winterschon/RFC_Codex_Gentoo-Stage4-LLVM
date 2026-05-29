#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
GLOBALS="${ANSIBLE_ROOT}/templates/kolla/globals.yml.j2"
MULTINODE="${ANSIBLE_ROOT}/templates/kolla/multinode.j2"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/render-fmt2-kolla-config.yml"
INVENTORY="${ANSIBLE_ROOT}/inventories/fmt2-openstack-kolla/hosts.yml"
GROUP_VARS="${ANSIBLE_ROOT}/inventories/fmt2-openstack-kolla/group_vars/all.yml"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

test -f "${GLOBALS}"
test -f "${MULTINODE}"
test -f "${PLAYBOOK}"
test -f "${INVENTORY}"
test -f "${GROUP_VARS}"

assert_file_contains "${GLOBALS}" 'kolla_container_engine: podman'
assert_file_contains "${GLOBALS}" 'kolla_base_distro: "rocky"'
assert_file_contains "${GLOBALS}" 'openstack_release: "2026.1"'
assert_file_contains "${GLOBALS}" 'kolla_internal_vip_address: "10.200.99.220"'
assert_file_contains "${GLOBALS}" 'kolla_external_vip_address: "10.200.99.221"'
assert_file_contains "${GLOBALS}" 'network_interface: "bond0"'
assert_file_contains "${GLOBALS}" 'api_interface: "bond0"'
assert_file_contains "${GLOBALS}" 'kolla_external_vip_interface: "bond0"'
assert_file_contains "${GLOBALS}" 'neutron_external_interface: "bond1"'
assert_file_contains "${GLOBALS}" 'enable_haproxy: "yes"'
assert_file_contains "${GLOBALS}" 'enable_openvswitch: "yes"'
assert_file_contains "${GLOBALS}" 'enable_neutron_provider_networks: "yes"'
assert_file_contains "${GLOBALS}" 'enable_cinder: "no"'
assert_file_contains "${GLOBALS}" 'enable_barbican: "yes"'
assert_file_contains "${GLOBALS}" 'enable_prometheus: "no"'
assert_file_contains "${GLOBALS}" 'enable_grafana: "no"'

assert_file_contains "${MULTINODE}" '\[control\]'
assert_file_contains "${MULTINODE}" '\[network\]'
assert_file_contains "${MULTINODE}" '\[compute\]'
assert_file_contains "${MULTINODE}" '\[monitoring\]'
assert_file_contains "${MULTINODE}" '\[deployment\]'
assert_file_contains "${MULTINODE}" 'kvm-sfo200-pri-9922'
assert_file_contains "${MULTINODE}" 'kvm-sfo200-sec-9923'
assert_file_contains "${MULTINODE}" 'localhost ansible_connection=local'

assert_file_contains "${PLAYBOOK}" 'hosts: fmt2_kolla_deployers'
assert_file_contains "${PLAYBOOK}" '/etc/kolla/globals.yml'
assert_file_contains "${PLAYBOOK}" '/etc/kolla/multinode'
assert_file_contains "${PLAYBOOK}" 'mode: '\''0640'\'''
assert_file_contains "${PLAYBOOK}" 'passwords.yml is generated on the deployer'

assert_file_contains "${INVENTORY}" 'fmt2_openstack_kolla'
assert_file_contains "${INVENTORY}" 'fmt2_kolla_deployers'
assert_file_contains "${INVENTORY}" 'ops_fmt2_kolla_deployer_9928'
assert_file_contains "${INVENTORY}" 'kvm_sfo200_pri_9922'
assert_file_contains "${INVENTORY}" 'kvm_sfo200_sec_9923'
assert_file_contains "${INVENTORY}" 'kvm_sfo200_ter_9924'
assert_file_contains "${GROUP_VARS}" 'kolla_internal_vip_address: 10.200.99.220'
assert_file_contains "${GROUP_VARS}" 'kolla_external_vip_address: 10.200.99.221'
assert_file_contains "${GROUP_VARS}" 'fmt2_kolla_controller_host: kvm-sfo200-pri-9922'
assert_file_contains "${GROUP_VARS}" 'fmt2_kolla_initial_compute_hosts:'

printf 'PASS: %s\n' "$(basename "$0")"
