#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/telemetry_nut"
M70_PROFILE="${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2

  [[ -f "${file}" ]] || fail "missing file ${file}"
  if grep -Fq "${pattern}" "${file}"; then
    fail "expected ${file} to not contain ${pattern}"
  fi
}

test -d "${ROLE_DIR}" || fail "missing telemetry_nut role"
test -f "${ROLE_DIR}/tasks/main.yml" || fail "missing telemetry_nut tasks"
test -f "${ROLE_DIR}/defaults/main.yml" || fail "missing telemetry_nut defaults"

for template in \
  nut.conf.j2 \
  ups.conf.j2 \
  upsd.conf.j2 \
  upsd.users.j2 \
  export-nut-textfile.sh.j2 \
  nut-textfile-collector.initd.j2 \
  nut-textfile-collector.confd.j2; do
  test -f "${ROLE_DIR}/templates/${template}" || fail "missing telemetry_nut template ${template}"
done

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'telemetry_nut'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'telemetry_nut'
assert_file_contains "${REPO_ROOT}/tests/shell/run-tests.sh" 'test_telemetry_nut_monitoring.sh'
assert_file_contains "${M70_PROFILE}" 'nut_monitoring:'
assert_file_contains "${M70_PROFILE}" 'device_name: cyberpower_cp1500'
assert_file_contains "${M70_PROFILE}" 'vendorid: "0764"'
assert_file_contains "${M70_PROFILE}" 'productid: "0601"'
assert_file_contains "${M70_PROFILE}" 'enable_shutdown_policy: false'
assert_file_contains "${M70_PROFILE}" 'node_exporter_textfile:'

assert_file_contains "${ROLE_DIR}/templates/ups.conf.j2" 'driver = {{ resolved_nut_monitoring.driver }}'
assert_file_contains "${ROLE_DIR}/templates/ups.conf.j2" 'vendorid = "{{ resolved_nut_monitoring.vendorid }}"'
assert_file_contains "${ROLE_DIR}/templates/upsd.conf.j2" 'LISTEN 127.0.0.1 3493'
assert_file_contains "${ROLE_DIR}/templates/upsd.users.j2" '[{{ resolved_nut_monitoring.monitor_username }}]'
assert_file_not_contains "${ROLE_DIR}/templates/upsd.users.j2" 'actions ='
assert_file_not_contains "${ROLE_DIR}/templates/upsd.users.j2" 'instcmds ='
assert_file_contains "${ROLE_DIR}/templates/export-nut-textfile.sh.j2" 'rfc1918_nut_ups_up'
assert_file_contains "${ROLE_DIR}/templates/export-nut-textfile.sh.j2" 'rfc1918_nut_ups_battery_charge_percent'
assert_file_contains "${ROLE_DIR}/templates/export-nut-textfile.sh.j2" 'rfc1918_nut_ups_status_on_battery'
assert_file_contains "${ROLE_DIR}/templates/export-nut-textfile.sh.j2" 'chmod 0644 "${tmpfile}"'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "['upsdrv', 'upsd', 'nut-textfile-collector']"
assert_file_not_contains "${ROLE_DIR}/tasks/main.yml" 'upsmon'
assert_file_not_contains "${ROLE_DIR}/templates/nut.conf.j2" 'MODE=standalone'
assert_file_not_contains "${ROLE_DIR}/templates/nut.conf.j2" 'MODE=netserver'
assert_file_not_contains "${ROLE_DIR}/templates/nut-textfile-collector.initd.j2" 'upsmon'
assert_file_not_contains "${ROLE_DIR}/templates/export-nut-textfile.sh.j2" 'SHUTDOWNCMD'

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
