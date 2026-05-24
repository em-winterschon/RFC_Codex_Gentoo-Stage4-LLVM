#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY="${REPO_ROOT}/docs/backup-policies/hasslehoff-backup-policy.yml"
VALIDATOR="${REPO_ROOT}/scripts/validate-hasslehoff-backup-policy.py"
DOC="${REPO_ROOT}/docs/HASSLEHOFF-BACKUP.md"
WIKI="${REPO_ROOT}/docs/wiki/Hasslehoff-Backup.md"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
validation_output="${tmpdir}/hasslehoff-backup-policy-validation.json"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_grep() {
  local pattern=$1
  local file=$2
  grep -q -- "${pattern}" "${file}" || fail "missing pattern '${pattern}' in ${file}"
}

require_file "${POLICY}"
require_file "${VALIDATOR}"
bash -n "${RUN_TESTS}"
python3 -m py_compile "${VALIDATOR}"

require_grep 'policy_id: rfc1918.hasslehoff.backup-policy.v1' "${POLICY}"
require_grep 'external_target_id: nasa-m70-nfs-relay' "${POLICY}"
require_grep 'x12again_allowed: false' "${POLICY}"
require_grep 'hasslehoff-config-state' "${POLICY}"
require_grep 'vm_lxc_coverage:' "${POLICY}"
require_grep 'netbox' "${POLICY}"
require_grep 'freeipa' "${POLICY}"
require_grep 'observability' "${POLICY}"
require_grep 'syslog-search' "${POLICY}"
require_grep 'netboot-publisher' "${POLICY}"
require_grep 'container-services' "${POLICY}"
require_grep 'workstation-validation' "${POLICY}"
require_grep 'restore_validation:' "${POLICY}"
require_grep 'disposable_restore' "${POLICY}"
require_grep 'offline_image_inspection' "${POLICY}"
require_grep 'ntfy_topic: forge-ops' "${POLICY}"

require_grep 'validate-hasslehoff-backup-policy.py' "${VALIDATOR}"
require_grep 'policy_id' "${VALIDATOR}"
require_grep 'x12again_allowed' "${VALIDATOR}"
require_grep 'required_service_classes' "${VALIDATOR}"
require_grep 'restore_validation' "${VALIDATOR}"

python3 "${VALIDATOR}" "${POLICY}" --format json > "${validation_output}"
grep -q '"ok": true' "${validation_output}" || fail "policy validation did not pass"
grep -q '"vm_lxc_services": 7' "${validation_output}" ||
  fail "unexpected VM/LXC service coverage count"
grep -q '"external_target_id": "nasa-m70-nfs-relay"' "${validation_output}" ||
  fail "validation summary missing NASA relay target"

require_file "${DOC}"
require_grep 'Hasslehoff Backup Policy' "${DOC}"
require_grep 'docs/backup-policies/hasslehoff-backup-policy.yml' "${DOC}"
require_grep 'NetBox, FreeIPA, observability, syslog/search, netboot publisher, container-services, and workstation validation' "${DOC}"

require_file "${WIKI}"
require_grep 'Hasslehoff Backup Policy' "${WIKI}"
require_grep 'docs/backup-policies/hasslehoff-backup-policy.yml' "${WIKI}"

require_grep 'test_hasslehoff_backup_policy.sh' "${RUN_TESTS}"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
