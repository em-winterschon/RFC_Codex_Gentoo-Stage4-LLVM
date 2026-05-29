#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/idrac-ensure-sol-baseline.sh"
FWMAINT_ISO_SCRIPT="${REPO_ROOT}/scripts/build-rocky-r630-fwmaint-iso.sh"
BMC_DOC="${REPO_ROOT}/docs/BMC-MANAGEMENT.md"
R630_DOC="${REPO_ROOT}/docs/FMT2-R630-HCI-STAGED-REBUILD.md"
E2ET_DOC="${REPO_ROOT}/docs/HOST-E2ET-ACCEPTANCE.md"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

test -f "${SCRIPT}"
bash -n "${SCRIPT}"
test -f "${FWMAINT_ISO_SCRIPT}"
bash -n "${FWMAINT_ISO_SCRIPT}"

assert_file_contains "${SCRIPT}" 'iDRAC.IPMISOL.Enable'
assert_file_contains "${SCRIPT}" 'iDRAC.IPMISol.BaudRate'
assert_file_contains "${SCRIPT}" 'iDRAC.Users.${IDRAC_SOL_USER_ID}.SolEnable'
assert_file_contains "${SCRIPT}" 'BIOS.SerialCommSettings.SerialComm'
assert_file_contains "${SCRIPT}" 'BIOS.SerialCommSettings.RedirAfterBoot'
assert_file_contains "${SCRIPT}" 'IDRAC_SOL_APPLY_BIOS'

assert_file_contains "${BMC_DOC}" 'Serial-over-LAN Baseline'
assert_file_contains "${BMC_DOC}" 'iDRAC.IPMISOL.Enable=Enabled'
assert_file_contains "${BMC_DOC}" 'BIOS.SerialCommSettings.RedirAfterBoot=Enabled'
assert_file_contains "${R630_DOC}" 'All three R630 iDRACs also have SOL enabled'
assert_file_contains "${R630_DOC}" 'BIOS.SerialCommSettings.SerialComm=OnConRedirCom1'
assert_file_contains "${E2ET_DOC}" 'Out-of-Band Gate'
assert_file_contains "${E2ET_DOC}" 'Serial-over-LAN is enabled by default'

assert_file_contains "${FWMAINT_ISO_SCRIPT}" 'hostonly_cmdline="no"'
assert_file_contains "${FWMAINT_ISO_SCRIPT}" 'netroot=iscsi:${ISCSI_PORTAL}::3260:0:${ISCSI_BOOT_TARGET}'
if grep -q 'rd.iscsi.firmware=1' "${FWMAINT_ISO_SCRIPT}"; then
  printf 'ERROR: firmware-maintenance ISO builder must not embed rd.iscsi.firmware=1\n' >&2
  exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
