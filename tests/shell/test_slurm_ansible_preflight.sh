#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PREFLIGHT_SCRIPT="${ANSIBLE_ROOT}/scripts/slurm-ansible-preflight.sh"
ROLLOUT_SCRIPT="${ANSIBLE_ROOT}/scripts/slurm-ansible-sshd-rollout.sh"
RUN_TESTS="${SCRIPT_DIR}/run-tests.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2
  if grep -Fq -- "${pattern}" "${file}"; then
    fail "expected ${file} not to contain ${pattern}"
  fi
}

for file in "${PREFLIGHT_SCRIPT}" "${ROLLOUT_SCRIPT}"; do
  [[ -f "${file}" ]] || fail "missing ${file}"
  bash -n "${file}"
done

assert_file_contains "${RUN_TESTS}" "test_slurm_ansible_preflight.sh"
assert_file_contains "${PREFLIGHT_SCRIPT}" "ansible-galaxy collection list"
assert_file_contains "${PREFLIGHT_SCRIPT}" "ansible-doc -t cache community.general.redis"
assert_file_contains "${PREFLIGHT_SCRIPT}" "redis-cli"
assert_file_contains "${PREFLIGHT_SCRIPT}" "requirements.yml"
assert_file_contains "${PREFLIGHT_SCRIPT}" "collections/requirements.yml"
assert_file_contains "${PREFLIGHT_SCRIPT}" "ansible-playbook --syntax-check"
assert_file_contains "${PREFLIGHT_SCRIPT}" "ANSIBLE_CACHE_PLUGIN=community.general.redis"
assert_file_contains "${PREFLIGHT_SCRIPT}" "sinfo -h -N -o '%N'"
assert_file_contains "${PREFLIGHT_SCRIPT}" "--nodelist"
assert_file_not_contains "${PREFLIGHT_SCRIPT}" "ssh -o"

assert_file_contains "${ROLLOUT_SCRIPT}" "--skip-preflight"
assert_file_contains "${ROLLOUT_SCRIPT}" "slurm-ansible-preflight.sh"
assert_file_contains "${ROLLOUT_SCRIPT}" "afterok:"
assert_file_contains "${ROLLOUT_SCRIPT}" "paste -sd ':'"
assert_file_not_contains "${ROLLOUT_SCRIPT}" "ssh -o"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
node_file="${tmpdir}/slurm-nodes.txt"
printf '%s\n' node-a node-b > "${node_file}"

preflight_output="$(${PREFLIGHT_SCRIPT} --run-id preflight-test --slurm-node-file "${node_file}" --dry-run)"
case "${preflight_output}" in
*'DRY-RUN sbatch'*'ansible-preflight-preflight-test-node-a'*'--nodelist node-a'*'redis-cli'*'ansible-doc -t cache community.general.redis'*'ansible-preflight-preflight-test-node-b'*'--nodelist node-b'*) ;;
*)
  printf 'unexpected preflight dry-run output:\n%s\n' "${preflight_output}" >&2
  exit 1
  ;;
esac
[[ "$(grep -c 'DRY-RUN sbatch' <<< "${preflight_output}")" -eq 2 ]] || fail "preflight dry-run should submit one Slurm job per node"

rollout_output="$(${ROLLOUT_SCRIPT} audit --run-id preflight-test --dry-run)"
case "${rollout_output}" in
*'ansible-preflight-preflight-test'*'sshd-audit-preflight-test'*) ;;
*)
  printf 'rollout dry-run did not include preflight and audit jobs:\n%s\n' "${rollout_output}" >&2
  exit 1
  ;;
esac

skip_output="$(${ROLLOUT_SCRIPT} audit --run-id preflight-test --skip-preflight --dry-run)"
case "${skip_output}" in
*'ansible-preflight-preflight-test'*)
  printf 'skip-preflight still submitted preflight:\n%s\n' "${skip_output}" >&2
  exit 1
  ;;
*'sshd-audit-preflight-test'*) ;;
*)
  printf 'skip-preflight dry-run missing audit job:\n%s\n' "${skip_output}" >&2
  exit 1
  ;;
esac

printf 'PASS: %s\n' "$(basename "$0")"
