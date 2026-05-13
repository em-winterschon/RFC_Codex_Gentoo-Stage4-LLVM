#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/slurm-pilot-live-apply.yml"
SERVICES_ROLE="${ANSIBLE_ROOT}/roles/services/tasks/main.yml"
SLURM_ROLE="${ANSIBLE_ROOT}/roles/slurm_cluster/tasks/main.yml"
SLURM_TEMPLATE="${ANSIBLE_ROOT}/roles/slurm_cluster/templates/slurm.conf.j2"
CONTROLLER_PROFILE="${ANSIBLE_ROOT}/profile-definitions/vm-slurm-controller.yml"
WORKER_PROFILE="${ANSIBLE_ROOT}/profile-definitions/slurm-worker-node.yml"
LOCAL_INVENTORY="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

for file in \
  "${PLAYBOOK}" \
  "${SERVICES_ROLE}" \
  "${SLURM_ROLE}" \
  "${SLURM_TEMPLATE}" \
  "${CONTROLLER_PROFILE}" \
  "${WORKER_PROFILE}" \
  "${LOCAL_INVENTORY}"; do
  test -f "${file}"
done

assert_file_contains "${RUN_TESTS}" 'test_slurm_live_apply_playbook.sh'

assert_file_contains "${PLAYBOOK}" 'slurm_pilot_live_apply_required'
assert_file_contains "${PLAYBOOK}" 'package.accept_keywords/30-slurm-pilot'
assert_file_contains "${PLAYBOOK}" 'sys-cluster/slurm ~amd64'
assert_file_contains "${PLAYBOOK}" 'package.use/30-slurm-pilot'
assert_file_contains "${PLAYBOOK}" 'sys-cluster/slurm munge mysql slurmdbd'
assert_file_contains "${PLAYBOOK}" 'sys-auth/munge gcrypt'
assert_file_contains "${PLAYBOOK}" 'slurm-24.05.3-r1-gres-sysmacros.patch'
assert_file_contains "${PLAYBOOK}" 'sys/sysmacros.h'
assert_file_contains "${PLAYBOOK}" '--buildpkg=y'
assert_file_contains "${PLAYBOOK}" '--complete-graph=y'
assert_file_contains "${PLAYBOOK}" '--binpkg-respect-use=y'
assert_file_contains "${PLAYBOOK}" 'stage5_profile'
assert_file_contains "${PLAYBOOK}" 'slurm_pilot_worker_nodes'
assert_file_contains "${PLAYBOOK}" 'resolved_profile_slurm_cluster'
assert_file_contains "${PLAYBOOK}" 'vault_slurmdbd_storage_password'
assert_file_contains "${PLAYBOOK}" 'vault_slurm_munge_key_b64'
assert_file_contains "${PLAYBOOK}" 'mariadb-install-db'
assert_file_contains "${PLAYBOOK}" 'CREATE DATABASE IF NOT EXISTS'
assert_file_contains "${PLAYBOOK}" 'CREATE USER IF NOT EXISTS'
assert_file_contains "${PLAYBOOK}" 'GRANT ALL PRIVILEGES'
assert_file_contains "${PLAYBOOK}" 'no_log: true'
assert_file_contains "${PLAYBOOK}" 'openrc_action_services_live: true'
assert_file_contains "${PLAYBOOK}" 'rc-service'
assert_file_contains "${PLAYBOOK}" 'slurmctld'
assert_file_contains "${PLAYBOOK}" 'slurmdbd'
assert_file_contains "${PLAYBOOK}" 'slurmd'
assert_file_contains "${PLAYBOOK}" 'sinfo'
assert_file_contains "${PLAYBOOK}" 'srun'

assert_file_contains "${SERVICES_ROLE}" 'openrc_action_services_live'
assert_file_contains "${SERVICES_ROLE}" 'rc-update add'
assert_file_contains "${SERVICES_ROLE}" 'chroot-runner.sh'

assert_file_contains "${SLURM_ROLE}" 'owner: "{{ resolved_slurm_cluster.user }}"'
assert_file_contains "${SLURM_ROLE}" 'owner: "{{ resolved_slurm_cluster.munge_user }}"'
assert_file_contains "${SLURM_ROLE}" 'Render SLURM accounting daemon configuration'
assert_file_contains "${SLURM_ROLE}" 'no_log: true'

assert_file_contains "${SLURM_TEMPLATE}" 'NodeHostname='
assert_file_contains "${SLURM_TEMPLATE}" 'NodeAddr='

assert_file_contains "${CONTROLLER_PROFILE}" 'package_accept_keywords_files:'
assert_file_contains "${CONTROLLER_PROFILE}" '30-slurm-pilot:'
assert_file_contains "${CONTROLLER_PROFILE}" 'sys-cluster/slurm ~amd64'
assert_file_contains "${CONTROLLER_PROFILE}" 'package_use_files:'
assert_file_contains "${CONTROLLER_PROFILE}" 'sys-cluster/slurm munge mysql slurmdbd'
assert_file_contains "${CONTROLLER_PROFILE}" 'sys-auth/munge gcrypt'
assert_file_contains "${CONTROLLER_PROFILE}" 'patch_files:'
assert_file_contains "${CONTROLLER_PROFILE}" 'slurm-24.05.3-r1-gres-sysmacros.patch'
assert_file_contains "${CONTROLLER_PROFILE}" 'sys/sysmacros.h'

assert_file_contains "${WORKER_PROFILE}" 'package_accept_keywords_files:'
assert_file_contains "${WORKER_PROFILE}" '30-slurm-pilot:'
assert_file_contains "${WORKER_PROFILE}" 'sys-cluster/slurm ~amd64'
assert_file_contains "${WORKER_PROFILE}" 'package_use_files:'
assert_file_contains "${WORKER_PROFILE}" 'sys-cluster/slurm munge'
assert_file_contains "${WORKER_PROFILE}" 'sys-auth/munge gcrypt'
assert_file_contains "${WORKER_PROFILE}" 'patch_files:'
assert_file_contains "${WORKER_PROFILE}" 'slurm-24.05.3-r1-gres-sysmacros.patch'
assert_file_contains "${WORKER_PROFILE}" 'sys/sysmacros.h'

assert_file_contains "${LOCAL_INVENTORY}" 'slurm_node_name: sched-sun99-slurmwkr-099072'
assert_file_contains "${LOCAL_INVENTORY}" 'slurm_node_cpus: 8'
assert_file_contains "${LOCAL_INVENTORY}" 'slurm_node_real_memory_mb: 15000'
assert_file_contains "${LOCAL_INVENTORY}" 'slurm_node_features:'

printf 'PASS: %s\n' "$(basename "$0")"
