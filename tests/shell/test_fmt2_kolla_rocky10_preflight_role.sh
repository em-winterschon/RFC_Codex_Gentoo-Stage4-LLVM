#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/fmt2_kolla_rocky10_preflight"
DEFAULTS="${ROLE_DIR}/defaults/main.yml"
TASKS="${ROLE_DIR}/tasks/main.yml"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/fmt2-kolla-rocky10-preflight.yml"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

test -f "${DEFAULTS}"
test -f "${TASKS}"
test -f "${PLAYBOOK}"

assert_file_contains "${DEFAULTS}" 'fmt2_kolla_target_os_name: Rocky Linux'
assert_file_contains "${DEFAULTS}" 'fmt2_kolla_target_os_major: "10"'
assert_file_contains "${DEFAULTS}" 'fmt2_kolla_container_engine: podman'
assert_file_contains "${DEFAULTS}" 'fmt2_kolla_base_distro: rocky'
assert_file_contains "${DEFAULTS}" 'fmt2_kolla_openstack_release: "2026.1"'
assert_file_contains "${DEFAULTS}" 'fmt2_kolla_require_container_engine: true'
assert_file_contains "${DEFAULTS}" 'fmt2_kolla_required_sol: true'
assert_file_contains "${DEFAULTS}" 'HUSMM3240ASS'
assert_file_contains "${DEFAULTS}" 'INTEL SSDPED1D480GA'
assert_file_contains "${DEFAULTS}" 'SSDSCKKB240G8R'
assert_file_contains "${DEFAULTS}" 'IDSDM'
assert_file_contains "${DEFAULTS}" 'bond0'
assert_file_contains "${DEFAULTS}" 'bond1'
assert_file_contains "${DEFAULTS}" 'fmt2_kolla_require_management_bond'
assert_file_contains "${DEFAULTS}" 'false'
assert_file_contains "${DEFAULTS}" 'bootnet'
assert_file_contains "${DEFAULTS}" 'eno2np1'
assert_file_contains "${DEFAULTS}" 'eno3np2'
assert_file_contains "${DEFAULTS}" 'eno4np3'
assert_file_contains "${DEFAULTS}" 'eno2'
assert_file_contains "${DEFAULTS}" 'eno3'
assert_file_contains "${DEFAULTS}" 'eno4'
assert_file_contains "${DEFAULTS}" 'enp130s0f0np0'
assert_file_contains "${DEFAULTS}" 'enp130s0f1np1'

assert_file_contains "${TASKS}" 'ansible.builtin.raw'
assert_file_contains "${TASKS}" '/etc/os-release'
if grep -q -- 'regex_search' "${TASKS}"; then
  printf 'FAIL: avoid regex_search in live preflight parsing; use line selection plus regex_replace for M70 Ansible compatibility\n' >&2
  exit 1
fi
assert_file_contains "${TASKS}" 'ansible_distribution'
assert_file_contains "${TASKS}" 'ansible_distribution_major_version'
assert_file_contains "${TASKS}" 'SOL remains enabled'
assert_file_contains "${TASKS}" 'fmt2_kolla_sol_evidence_state'
assert_file_contains "${TASKS}" 'kolla_container_engine'
assert_file_contains "${TASKS}" 'kolla_base_distro'
assert_file_contains "${TASKS}" 'Assert Podman container engine is installed when required'
assert_file_contains "${TASKS}" 'fmt2_kolla_required_interfaces'
assert_file_contains "${TASKS}" 'fmt2_kolla_required_rdma_interfaces'
assert_file_contains "${TASKS}" 'fmt2_kolla_candidate_os_devices'
assert_file_contains "${TASKS}" 'fmt2_kolla_disallowed_storage_patterns'
assert_file_contains "${TASKS}" 'Refusing FMT2 Kolla preflight'
assert_file_contains "${TASKS}" 'ansible.builtin.meta: end_host'

assert_file_contains "${PLAYBOOK}" 'hosts: fmt2_openstack_kolla'
assert_file_contains "${PLAYBOOK}" 'gather_facts: false'
assert_file_contains "${PLAYBOOK}" 'fmt2_kolla_rocky10_preflight'

printf 'PASS: %s\n' "$(basename "$0")"
