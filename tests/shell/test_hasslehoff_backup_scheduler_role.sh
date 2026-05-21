#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/hasslehoff_backup_scheduler"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/hasslehoff-backup-scheduler.yml"
POLICY="${ROOT_DIR}/docs/backup-policies/hasslehoff-backup-policy.yml"
DOC="${ROOT_DIR}/docs/HASSLEHOFF-BACKUP.md"
WIKI="${ROOT_DIR}/docs/wiki/Hasslehoff-Backup.md"
RUN_TESTS="${ROOT_DIR}/tests/shell/run-tests.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_contains "${ROLE_DIR}/defaults/main.yml" "hasslehoff_backup_scheduler_enabled: false"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "hasslehoff_backup_scheduler_apply: false"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "hasslehoff_backup_scheduler_mode: cron"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "hasslehoff_backup_scheduler_cron_file: /etc/cron.d/hasslehoff-backup"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "hasslehoff_backup_scheduler_policy_path: docs/backup-policies/hasslehoff-backup-policy.yml"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "hasslehoff_backup_scheduler_mirror_target: root@admin-sun99-forge-099070:/mnt/nasa/hasslehoff/config-bundles"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "HASSLEHOFF_BACKUP_MIRROR_VERIFY=1"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "HASSLEHOFF_BACKUP_RESTORE_VERIFY=1"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "HASSLEHOFF_BACKUP_NOTIFY=1"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS='--no-owner --no-group'"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "validate-hasslehoff-backup-policy.py"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "Refuse Hasslehoff backup scheduler mutation without explicit apply gate"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "hasslehoff_backup_scheduler_apply | bool"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "reject X12AGAIN"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "backup-hasslehoff-scheduled.sh"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "cron"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "HASSLEHOFF_BACKUP_MIRROR_TARGET"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "HASSLEHOFF_BACKUP_PREFLIGHT_ONLY=1"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "hasslehoff_backup_scheduler_run_preflight | bool"
assert_file_contains "${PLAYBOOK}" "Install Hasslehoff scheduled external backup job"
assert_file_contains "${PLAYBOOK}" "hasslehoff_backup_scheduler"
assert_file_contains "${POLICY}" "nasa-m70-nfs-relay"
assert_file_contains "${DOC}" "Recurring Scheduler Installation"
assert_file_contains "${DOC}" "hasslehoff-backup-scheduler.yml"
assert_file_contains "${DOC}" "HASSLEHOFF_BACKUP_PREFLIGHT_ONLY=1"
assert_file_contains "${WIKI}" "Recurring Scheduler Installation"
assert_file_contains "${RUN_TESTS}" "test_hasslehoff_backup_scheduler_role.sh"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -f "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  children:
    hasslehoff_backup_scheduler_hosts:
      hosts:
        localhost:
          ansible_connection: local
EOF
  ANSIBLE_CONFIG="${ANSIBLE_ROOT}/ansible.cfg" \
    ANSIBLE_ROLES_PATH="${ANSIBLE_ROOT}/roles" \
    ansible-playbook --syntax-check -i "${tmp_inventory}" "${PLAYBOOK}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
