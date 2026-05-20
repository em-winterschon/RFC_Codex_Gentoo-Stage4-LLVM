#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/r630-boot-rocky10-kolla-installer.sh"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -F -q -- "${pattern}" "${file}"
}

test -f "${SCRIPT}"
bash -n "${SCRIPT}"

assert_file_contains "${SCRIPT}" 'REBOOT_AFTER_STAGE="${REBOOT_AFTER_STAGE:-0}"'
assert_file_contains "${SCRIPT}" 'inst.ks=${KICKSTART_URL}'
assert_file_contains "${SCRIPT}" 'inst.repo=${ROCKY_REPO_URL}'
assert_file_contains "${SCRIPT}" 'console=ttyS0,115200n8'
assert_file_contains "${SCRIPT}" 'grubby --add-kernel'
assert_file_contains "${SCRIPT}" 'if ! grubby --add-kernel'
assert_file_contains "${SCRIPT}" '/etc/grub.d/40_custom'
assert_file_contains "${SCRIPT}" 'grub2-mkconfig'
assert_file_contains "${SCRIPT}" 'grub2-reboot'
assert_file_contains "${SCRIPT}" 'if [[ "${REBOOT_AFTER_STAGE}" == "1" ]]'
assert_file_contains "${SCRIPT}" 'systemctl reboot'
assert_file_contains "${RUN_TESTS}" 'test_r630_boot_rocky10_kolla_installer.sh'

printf 'PASS: %s\n' "$(basename "$0")"
