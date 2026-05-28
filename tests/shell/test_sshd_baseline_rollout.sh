#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE="${ANSIBLE_ROOT}/roles/sshd_baseline"
AUDIT_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/sshd-baseline-audit.yml"
APPLY_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/sshd-baseline-apply.yml"
ROLLBACK_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/sshd-baseline-rollback.yml"
SLURM_SCRIPT="${ANSIBLE_ROOT}/scripts/slurm-ansible-sshd-rollout.sh"
REDIS_ROLE="${ANSIBLE_ROOT}/roles/ansible_redis_cache"
REDIS_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/ansible-redis-cache-local.yml"
ANSIBLE_CFG="${ANSIBLE_ROOT}/ansible.cfg"
REQS="${ANSIBLE_ROOT}/requirements.txt"
IPA_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/ipa-client-live-apply.yml"
RUN_TESTS="${SCRIPT_DIR}/run-tests.sh"

assert_file_contains() {
  local file=$1
  local pattern=$2
  if ! grep -F -q -- "${pattern}" "${file}"; then
    printf 'missing pattern in %s: %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2
  if grep -q -- "${pattern}" "${file}"; then
    printf 'unexpected pattern in %s: %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

for file in \
  "${ROLE}/defaults/main.yml" \
  "${ROLE}/tasks/main.yml" \
  "${ROLE}/handlers/main.yml" \
  "${ROLE}/templates/sshd_config.standard_sssd_no_include.j2" \
  "${ROLE}/templates/sshd_config.installer_recovery_only.j2" \
  "${AUDIT_PLAYBOOK}" \
  "${APPLY_PLAYBOOK}" \
  "${ROLLBACK_PLAYBOOK}" \
  "${SLURM_SCRIPT}" \
  "${REDIS_ROLE}/defaults/main.yml" \
  "${REDIS_ROLE}/tasks/main.yml" \
  "${REDIS_ROLE}/handlers/main.yml" \
  "${REDIS_ROLE}/templates/redis-ansible-cache.conf.j2" \
  "${REDIS_ROLE}/templates/redis-ansible-cache.initd.j2" \
  "${REDIS_PLAYBOOK}"; do
  test -f "${file}"
done

assert_file_contains "${RUN_TESTS}" 'test_sshd_baseline_rollout.sh'

assert_file_contains "${ANSIBLE_CFG}" 'gathering = smart'
assert_file_contains "${ANSIBLE_CFG}" 'fact_caching = community.general.redis'
assert_file_contains "${ANSIBLE_CFG}" 'fact_caching_connection = localhost:6379:0:'
assert_file_contains "${ANSIBLE_CFG}" 'fact_caching_timeout = 86400'
assert_file_contains "${ANSIBLE_CFG}" 'fact_caching_prefix = forge_ansible_facts'
assert_file_contains "${ANSIBLE_CFG}" 'fact_caching_redis_keyset_name = forge_ansible_cache_keys'
assert_file_contains "${REQS}" 'redis>=5.0'

REDIS_TEMPLATE="${REDIS_ROLE}/templates/redis-ansible-cache.conf.j2"
assert_file_contains "${REDIS_TEMPLATE}" 'bind {{ ansible_redis_cache_bind | join'
assert_file_contains "${REDIS_TEMPLATE}" 'protected-mode yes'
assert_file_contains "${REDIS_TEMPLATE}" 'save ""'
assert_file_contains "${REDIS_TEMPLATE}" 'appendonly no'
assert_file_contains "${REDIS_TEMPLATE}" 'maxmemory {{ ansible_redis_cache_maxmemory }}'
assert_file_contains "${REDIS_ROLE}/defaults/main.yml" 'ansible_redis_cache_port: 6379'
assert_file_contains "${REDIS_ROLE}/defaults/main.yml" 'dev-db/redis'
assert_file_contains "${REDIS_ROLE}/tasks/main.yml" 'redis-cli'
assert_file_contains "${REDIS_ROLE}/tasks/main.yml" 'CONFIG'
assert_file_contains "${REDIS_PLAYBOOK}" 'Configure localhost Redis cache for Ansible facts'
assert_file_contains "${REDIS_PLAYBOOK}" 'ansible_redis_cache_install_package: true'

STANDARD_TEMPLATE="${ROLE}/templates/sshd_config.standard_sssd_no_include.j2"
standard_template_sha256="$(sha256sum "${STANDARD_TEMPLATE}" | awk '{print $1}')"
if [[ "${standard_template_sha256}" != "26f6487c46b763e5ba43509da87d689076a7c146defb106c1d63e7398daffd25" ]]; then
  printf 'unexpected canonical SSHD template sha256: %s\n' "${standard_template_sha256}" >&2
  exit 1
fi
assert_file_contains "${STANDARD_TEMPLATE}" 'Standardized SSHD config'
assert_file_contains "${STANDARD_TEMPLATE}" 'AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys'
assert_file_contains "${STANDARD_TEMPLATE}" 'AuthorizedKeysCommandUser nobody'
assert_file_contains "${STANDARD_TEMPLATE}" 'PermitRootLogin prohibit-password'
assert_file_contains "${STANDARD_TEMPLATE}" 'UsePAM yes'
assert_file_contains "${STANDARD_TEMPLATE}" 'StrictModes yes'
assert_file_contains "${STANDARD_TEMPLATE}" '# Include "/etc/ssh/sshd_config.d/*.conf"'
assert_file_not_contains "${STANDARD_TEMPLATE}" '^Include '

RECOVERY_TEMPLATE="${ROLE}/templates/sshd_config.installer_recovery_only.j2"
assert_file_contains "${RECOVERY_TEMPLATE}" 'installer/recovery only'
assert_file_contains "${RECOVERY_TEMPLATE}" 'PermitRootLogin Yes'
assert_file_contains "${RECOVERY_TEMPLATE}" 'Include "/etc/ssh/sshd_config.d/*.conf"'

TASKS="${ROLE}/tasks/main.yml"
assert_file_contains "${TASKS}" 'sshd_baseline_apply_required'
assert_file_contains "${TASKS}" 'sshd_baseline_variant'
assert_file_contains "${TASKS}" 'installer_recovery_only'
assert_file_contains "${TASKS}" 'sshd_config.d/60-sssd-authorized-keys.conf'
assert_file_contains "${TASKS}" 'validate: "{{ sshd_baseline_validate_command }}"'
assert_file_contains "${TASKS}" 'sshd -T'
assert_file_contains "${TASKS}" 'delegate_to: localhost'
assert_file_contains "${TASKS}" 'sshd_baseline_report_dir'
assert_file_contains "${ROLE}/handlers/main.yml" 'sshd_baseline_restart_service'

assert_file_contains "${AUDIT_PLAYBOOK}" 'sshd_baseline_mode: audit'
assert_file_contains "${APPLY_PLAYBOOK}" 'sshd_baseline_mode: apply'
assert_file_contains "${APPLY_PLAYBOOK}" 'sshd_baseline_apply_required=true'
assert_file_contains "${ROLLBACK_PLAYBOOK}" 'sshd_baseline_rollback_source'
assert_file_contains "${ROLLBACK_PLAYBOOK}" 'validate: "{{ sshd_baseline_validate_command }}"'

assert_file_contains "${IPA_PLAYBOOK}" 'name: Apply canonical SSHD baseline with inline SSSD key lookup'
assert_file_contains "${IPA_PLAYBOOK}" 'name: sshd_baseline'
assert_file_not_contains "${IPA_PLAYBOOK}" '60-sssd-authorized-keys.conf'

assert_file_contains "${SLURM_SCRIPT}" 'sbatch'
assert_file_contains "${SLURM_SCRIPT}" '--array=0-'
assert_file_contains "${SLURM_SCRIPT}" 'ANSIBLE_CACHE_PLUGIN_CONNECTION'
assert_file_contains "${SLURM_SCRIPT}" 'playbooks/sshd-baseline-audit.yml'
assert_file_contains "${SLURM_SCRIPT}" 'playbooks/sshd-baseline-apply.yml'
assert_file_contains "${SLURM_SCRIPT}" 'playbooks/sshd-baseline-rollback.yml'
assert_file_not_contains "${SLURM_SCRIPT}" 'ssh -o'

cd "${ANSIBLE_ROOT}"
ANSIBLE_CACHE_PLUGIN=memory ansible-playbook -i inventories/local-network/hosts.yml playbooks/sshd-baseline-audit.yml --syntax-check >/dev/null
ANSIBLE_CACHE_PLUGIN=memory ansible-playbook -i inventories/local-network/hosts.yml playbooks/sshd-baseline-apply.yml --syntax-check >/dev/null
ANSIBLE_CACHE_PLUGIN=memory ansible-playbook -i inventories/local-network/hosts.yml playbooks/sshd-baseline-rollback.yml --syntax-check >/dev/null
ANSIBLE_CACHE_PLUGIN=memory ansible-playbook -i localhost, playbooks/ansible-redis-cache-local.yml --syntax-check >/dev/null

bash -n "${SLURM_SCRIPT}"

tmp_audit_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_audit_dir}"' EXIT
cat > "${tmp_audit_dir}/drift-host.json" <<'JSON'
{"host":"drift-host","managed":true,"variant":"standard_sssd_no_include","syntax_ok":true,"drift":true}
JSON
cat > "${tmp_audit_dir}/clean-host.json" <<'JSON'
{"host":"clean-host","managed":true,"variant":"standard_sssd_no_include","syntax_ok":true,"drift":false}
JSON

slurm_test_run_id="sshd-test-$$"
slurm_audit_dry_run="$("${SLURM_SCRIPT}" audit --run-id "${slurm_test_run_id}" --dry-run)"
slurm_apply_dry_run="$("${SLURM_SCRIPT}" apply --run-id "${slurm_test_run_id}" --audit-dir "${tmp_audit_dir}" --shard-size 1 --max-parallel-shards 2 --dry-run)"
slurm_rollback_dry_run="$("${SLURM_SCRIPT}" rollback --run-id "${slurm_test_run_id}" --rollback-source /var/backups/sshd_config/example --limit drift-host --dry-run)"
case "${slurm_audit_dry_run}" in
  *'DRY-RUN sbatch'*'playbooks/sshd-baseline-audit.yml'*) ;;
  *) printf 'unexpected audit dry-run output: %s\n' "${slurm_audit_dry_run}" >&2; exit 1 ;;
esac
case "${slurm_apply_dry_run}" in
  *'eligible_hosts=1'*'--array=0-0%2'*'playbooks/sshd-baseline-apply.yml'*) ;;
  *) printf 'unexpected apply dry-run output: %s\n' "${slurm_apply_dry_run}" >&2; exit 1 ;;
esac
case "${slurm_rollback_dry_run}" in
  *'DRY-RUN sbatch'*'playbooks/sshd-baseline-rollback.yml'*'--limit drift-host'*) ;;
  *) printf 'unexpected rollback dry-run output: %s\n' "${slurm_rollback_dry_run}" >&2; exit 1 ;;
esac

printf 'PASS: %s\n' "$(basename "$0")"
