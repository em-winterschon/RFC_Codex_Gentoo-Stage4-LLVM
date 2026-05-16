#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/checkmk_recovery"

assert_file() {
  local path="$1"
  if [[ ! -f "${ROOT_DIR}/${path}" ]]; then
    echo "missing file: ${path}" >&2
    exit 1
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${ROOT_DIR}/${path}"; then
    echo "missing '${needle}' in ${path}" >&2
    exit 1
  fi
}

assert_file "${ANSIBLE_ROOT}/playbooks/checkmk-recovery-upgrade.yml"
assert_file "${ROLE_DIR}/defaults/main.yml"
assert_file "${ROLE_DIR}/tasks/main.yml"
assert_file "docs/CHECKMK-FMT2-RECOVERY-UPGRADE.md"
assert_file "docs/wiki/CheckMK-FMT2-Recovery-Upgrade.md"

assert_contains "${ANSIBLE_ROOT}/playbooks/checkmk-recovery-upgrade.yml" "checkmk_recovery"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_site: vernetzen"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_current_observed_version: 2.0.0p22.cre"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_observed_os_release: Rocky Linux 8.6"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_elasticsearch_endpoint: app-sfo200-elastic-9961.vernetzen.io"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_elasticsearch_port: 9200"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_allow_backup: false"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_allow_repo_disable: false"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_allow_rsyslog_elastic_disable: false"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_allow_cert_install: false"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_allow_os_update: false"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_allow_reboot: false"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_allow_discovery_apply: false"
assert_contains "${ROLE_DIR}/defaults/main.yml" "checkmk_recovery_allow_checkmk_upgrade: false"
assert_contains "${ROLE_DIR}/defaults/main.yml" "ripe-atlas-probe"

assert_contains "${ROLE_DIR}/tasks/main.yml" "omd status {{ checkmk_recovery_site }}"
assert_contains "${ROLE_DIR}/tasks/main.yml" "omd backup {{ checkmk_recovery_site }}"
assert_contains "${ROLE_DIR}/tasks/main.yml" "dnf update --assumeno"
assert_contains "${ROLE_DIR}/tasks/main.yml" "dnf update -y"
assert_contains "${ROLE_DIR}/tasks/main.yml" "checkmk_recovery_allow_os_update | bool"
assert_contains "${ROLE_DIR}/tasks/main.yml" "checkmk_recovery_allow_reboot | bool"
assert_contains "${ROLE_DIR}/tasks/main.yml" "checkmk_recovery_allow_discovery_apply | bool"
assert_contains "${ROLE_DIR}/tasks/main.yml" "checkmk_recovery_allow_rsyslog_elastic_disable | bool"
assert_contains "${ROLE_DIR}/tasks/main.yml" "checkmk_recovery_allow_cert_install | bool"
assert_contains "${ROLE_DIR}/tasks/main.yml" "checkmk_recovery_allow_checkmk_upgrade | bool"
assert_contains "${ROLE_DIR}/tasks/main.yml" "cmk -nv"
assert_contains "${ROLE_DIR}/tasks/main.yml" "cmk -II"
assert_contains "${ROLE_DIR}/tasks/main.yml" "omd update --conflict={{ checkmk_recovery_upgrade_conflict_mode }}"
assert_contains "${ROLE_DIR}/tasks/main.yml" "until: checkmk_recovery_post_reboot_omd_status.rc == 0"
assert_contains "${ROLE_DIR}/tasks/main.yml" "retries: 12"
assert_contains "${ROLE_DIR}/tasks/main.yml" "delay: 10"

assert_contains "docs/CHECKMK-FMT2-RECOVERY-UPGRADE.md" "dry-run by default"
assert_contains "docs/CHECKMK-FMT2-RECOVERY-UPGRADE.md" "Rocky Linux 8.6"
assert_contains "docs/CHECKMK-FMT2-RECOVERY-UPGRADE.md" "CheckMK 2.0.0p22"
assert_contains "docs/CHECKMK-FMT2-RECOVERY-UPGRADE.md" "ripe-atlas-probe"
assert_contains "docs/CHECKMK-FMT2-RECOVERY-UPGRADE.md" "app-sfo200-elastic-9961.vernetzen.io:9200"
assert_contains "docs/CHECKMK-FMT2-RECOVERY-UPGRADE.md" "internal CA"
assert_contains "docs/CHECKMK-FMT2-RECOVERY-UPGRADE.md" "Do not bulk-accept vanished services"
assert_contains "docs/wiki/CheckMK-FMT2-Recovery-Upgrade.md" "checkmk-recovery-upgrade.yml"
assert_contains "tests/shell/run-tests.sh" "test_checkmk_recovery_upgrade.sh"

echo "CheckMK FMT2 recovery and upgrade workflow checks passed."
