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
PREFLIGHT_MAIN="${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml"
PREFLIGHT_LOAD="${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml"
DOC="${REPO_ROOT}/docs/HPC-WORKLOAD-SCHEDULER-PLAN.md"
WIKI="${REPO_ROOT}/docs/wiki/HPC-Workload-Scheduler-Plan.md"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

assert_task_block_contains() {
  local file=$1
  local task_name=$2
  local pattern=$3

  awk -v task_name="${task_name}" '
    $0 == "- name: " task_name { in_task = 1; next }
    in_task && /^- name: / { exit }
    in_task { print }
  ' "${file}" | grep -q -- "${pattern}"
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
assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" 'munge_key_b64: "{{ vault_slurm_munge_key_b64'
assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" 'partitions:'
assert_file_contains "${PROFILE_DIR}/vm-slurm-controller.yml" 'rdma-test'
assert_file_contains "${PROFILE_DIR}/slurm-worker-node.yml" 'worker_enabled: true'
assert_file_contains "${PROFILE_DIR}/slurm-worker-node.yml" 'munge_key_b64: "{{ vault_slurm_munge_key_b64'
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
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'slurm_cluster_default_munge_key_b64: ""'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'slurm_cluster_default_partitions:'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'resolved_profile_slurm_cluster'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" '/etc/munge'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'b64decode'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'no_log: true'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'openrc_action_services'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "'user': 'root'"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'slurmctld'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'slurmd'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'slurmdbd'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "'command': '/usr/sbin/slurmdbd -D'"
if grep -q "'command': '/usr/sbin/slurmdbd -D -f " "${ROLE_DIR}/tasks/main.yml"; then
  printf 'FAIL: slurmdbd must not be launched with unsupported -f option\n' >&2
  exit 1
fi
assert_task_block_contains "${ROLE_DIR}/tasks/main.yml" 'Register SLURM worker OpenRC action service' "'cgroup_v2_system_slice': true"
assert_task_block_contains "${ROLE_DIR}/tasks/main.yml" 'Register SLURM worker OpenRC action service' "'cgroup_v2_controllers': \\['cpuset', 'cpu', 'memory'\\]"
assert_file_contains "${ROLE_DIR}/templates/slurm.conf.j2" 'ClusterName='
assert_file_contains "${ROLE_DIR}/templates/slurm.conf.j2" 'SlurmctldPidFile=/run/slurmctld-daemon.pid'
assert_file_contains "${ROLE_DIR}/templates/slurm.conf.j2" 'SlurmdPidFile=/run/slurmd-daemon.pid'
assert_file_contains "${ROLE_DIR}/templates/slurm.conf.j2" 'PartitionName='
assert_file_contains "${ROLE_DIR}/templates/slurmdbd.conf.j2" 'StorageType=accounting_storage/mysql'
assert_file_contains "${ROLE_DIR}/templates/slurmdbd.conf.j2" 'PidFile=/run/slurmdbd-daemon.pid'
assert_task_block_contains "${ROLE_DIR}/tasks/main.yml" 'Render SLURM accounting daemon configuration' 'owner: "{{ resolved_slurm_cluster.user }}"'
assert_task_block_contains "${ROLE_DIR}/tasks/main.yml" 'Render SLURM accounting daemon configuration' 'group: "{{ resolved_slurm_cluster.group }}"'
assert_file_contains "${ROLE_DIR}/templates/cgroup.conf.j2" 'ConstrainCores=yes'
assert_file_contains "${ROLE_DIR}/templates/cgroup.conf.j2" 'IgnoreSystemd=yes'
assert_file_contains "${ROLE_DIR}/templates/cgroup.conf.j2" 'ConstrainSwapSpace=no'

assert_file_contains "${SERVICE_ATOMS}" 'vm-slurm-controller:'
assert_file_contains "${SERVICE_ATOMS}" 'slurm-worker-node:'
assert_file_contains "${SERVICE_ATOMS}" 'tcp/6817'
assert_file_contains "${SERVICE_ATOMS}" 'tcp/6818'
assert_file_contains "${SERVICE_ATOMS}" 'tcp/6819'
assert_file_contains "${INSTALL_SEQUENCE}" 'slurm_cluster'
assert_file_contains "${INSTALL_PLAYBOOK}" 'slurm_cluster'
assert_file_contains "${PREFLIGHT_MAIN}" 'resolved_profile_slurm_cluster'
assert_file_contains "${PREFLIGHT_LOAD}" 'gentoo_profile_definition.slurm_cluster'
assert_file_contains "${DOC}" 'Repo Scaffold State'
assert_file_contains "${DOC}" 'vm-slurm-controller'
assert_file_contains "${DOC}" 'Issue #118'
assert_file_contains "${DOC}" 'scheduler_node_feature_taxonomy'
assert_file_contains "${WIKI}" 'Repo Scaffold State'
assert_file_contains "${WIKI}" 'Issue #118'

printf 'PASS: %s\n' "$(basename "$0")"
