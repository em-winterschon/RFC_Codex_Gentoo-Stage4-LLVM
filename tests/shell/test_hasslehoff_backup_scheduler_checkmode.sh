#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/hasslehoff-backup-scheduler.yml"
RUN_TESTS="${ROOT_DIR}/tests/shell/run-tests.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "${PLAYBOOK}" ]] || fail "missing playbook ${PLAYBOOK}"
grep -Fq "test_hasslehoff_backup_scheduler_checkmode.sh" "${RUN_TESTS}" ||
  fail "run-tests.sh must include scheduler check-mode regression"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  tmp_runtime="$(mktemp -d)"
  checkmode_output="${tmp_runtime}/hasslehoff-backup-scheduler-checkmode.out"
  trap 'rm -f "${tmp_inventory}"; rm -rf "${tmp_runtime}"' EXIT
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  children:
    hasslehoff_backup_scheduler_hosts:
      hosts:
        localhost:
          ansible_connection: local
EOF
  ANSIBLE_STDOUT_CALLBACK=default \
    ANSIBLE_CONFIG="${ANSIBLE_ROOT}/ansible.cfg" \
    ANSIBLE_ROLES_PATH="${ANSIBLE_ROOT}/roles" \
    ansible-playbook \
    -i "${tmp_inventory}" \
    "${PLAYBOOK}" \
    --check \
    -e hasslehoff_backup_scheduler_enabled=true \
    -e hasslehoff_backup_scheduler_apply=true \
    -e hasslehoff_backup_scheduler_run_preflight=false \
    -e hasslehoff_backup_scheduler_runtime_root="${tmp_runtime}" \
    > "${checkmode_output}"
  grep -Fq "PLAY RECAP" "${checkmode_output}" ||
    fail "check-mode run did not reach recap"
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
