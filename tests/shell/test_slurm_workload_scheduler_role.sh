#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/slurm_cluster"
PROFILE_DIR="${ANSIBLE_ROOT}/profile-definitions"
PACKAGE_LIST_DIR="${ANSIBLE_ROOT}/profile-package-lists"
SERVICE_ATOMS="${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml"
INSTALL_SEQUENCE="${ANSIBLE_ROOT}/vars/install_sequences.yml"
INSTALL_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/install.yml"
DOC="${REPO_ROOT}/docs/HPC-WORKLOAD-SCHEDULER-PLAN.md"
WIKI="${REPO_ROOT}/docs/wiki/HPC-Workload-Scheduler-Plan.md"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

for file in \
  "${PROFILE_DIR}/vm-slurm-controller.yml" \
  "${PROFILE_DIR}/vm-slurm-controller.metadata.yml" \
  "${PROFILE_DIR}/slurm-worker-node.yml" \
  "${PROFILE_DIR}/slurm-worker-node.metadata.yml" \
  "${PACKAGE_LIST_DIR}/stage5-virtual-host-slurm-controller.packages" \
  "${PACKAGE_LIST_DIR}/stage5-slurm-worker-node.packages" \
  "${ROLE_DIR}/defaults/main.yml" \
  "${ROLE_DIR}/tasks/main.yml" \
  "${ROLE_DIR}/templates/slurm.conf.j2" \
  "${ROLE_DIR}/templates/slurmdbd.conf.j2" \
  "${ROLE_DIR}/templates/cgroup.conf.j2" \
  "${DOC}" \
  "${WIKI}"; do
  test -f "${file}"
done

assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" '^gentoo_profile_definition:'
assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" 'slurm_cluster:'
assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" 'controller_enabled: true'
assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" 'dbd_enabled: true'
assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" 'partitions:'
assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" 'rdma-test'
assert_file_contains "${PROFILE_DIR}/slurm-worker-node.yml" 'worker_enabled: true'
assert_file_contains "${PROFILE_DIR}/slurm-worker-node.yml" 'node_features:'

for package_atom in \
  '^sys-cluster/slurm$' \
  '^sys-auth/munge$' \
  '^dev-db/mariadb$' \
  '^sys-process/numactl$'; do
  assert_file_contains "${PACKAGE_LIST_DIR}/stage5-virtual-host-slurm-controller.packages" "${package_atom}"
done

for package_atom in \
  '^sys-cluster/slurm$' \
  '^sys-auth/munge$' \
  '^sys-process/numactl$' \
  '^sys-cluster/rdma-core$'; do
  assert_file_contains "${PACKAGE_LIST_DIR}/stage5-slurm-worker-node.packages" "${package_atom}"
done

assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'slurm_cluster_default_enabled: false'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'slurm_cluster_default_partitions:'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'resolved_profile_slurm_cluster'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'openrc_action_services'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'slurmctld'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'slurmd'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'slurmdbd'
assert_file_contains "${ROLE_DIR}/templates/slurm.conf.j2" 'ClusterName='
assert_file_contains "${ROLE_DIR}/templates/slurm.conf.j2" 'PartitionName='
assert_file_contains "${ROLE_DIR}/templates/slurmdbd.conf.j2" 'StorageType=accounting_storage/mysql'
assert_file_contains "${ROLE_DIR}/templates/cgroup.conf.j2" 'ConstrainCores=yes'

assert_file_contains "${SERVICE_ATOMS}" 'vm-slurm-controller:'
assert_file_contains "${SERVICE_ATOMS}" 'slurm-worker-node:'
assert_file_contains "${SERVICE_ATOMS}" 'tcp/6817'
assert_file_contains "${SERVICE_ATOMS}" 'tcp/6818'
assert_file_contains "${SERVICE_ATOMS}" 'tcp/6819'
assert_file_contains "${INSTALL_SEQUENCE}" 'slurm_cluster'
assert_file_contains "${INSTALL_PLAYBOOK}" 'slurm_cluster'
assert_file_contains "${DOC}" 'Repo Scaffold State'
assert_file_contains "${DOC}" 'vm-slurm-controller'
assert_file_contains "${WIKI}" 'Repo Scaffold State'

printf 'PASS: %s\n' "$(basename "$0")"
