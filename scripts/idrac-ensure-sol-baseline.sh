#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'USAGE'
Ensure Dell iDRAC Serial-over-LAN stays enabled.

Required environment:
  IDRAC_HOST              iDRAC host or IP

Authentication environment, choose one:
  IDRAC_PASSWORD          iDRAC password
  IDRAC_PASSWORD_FILE     file containing the iDRAC password

Optional environment:
  IDRAC_USER              iDRAC SSH user, default: root
  IDRAC_SOL_USER_ID       iDRAC local user ID to enable SOL for, default: 2
  IDRAC_SOL_BAUD          SOL baud rate, default: 115200
  IDRAC_SOL_MIN_PRIV      SOL minimum privilege, default: 3
  IDRAC_SOL_APPLY_BIOS    set to 1 to stage BIOS serial-redirection settings

This script intentionally uses the iDRAC SSH RACADM shell. It does not print
passwords and should be invoked from a vault-backed wrapper.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_var() {
  local name=$1
  if [[ -z "${!name:-}" ]]; then
    printf 'ERROR: %s is required\n' "${name}" >&2
    usage >&2
    exit 2
  fi
}

require_cmd() {
  local cmd=$1
  if ! command -v "${cmd}" > /dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "${cmd}" >&2
    exit 2
  fi
}

require_var IDRAC_HOST
require_cmd ssh
require_cmd sshpass

IDRAC_USER="${IDRAC_USER:-root}"
IDRAC_SOL_USER_ID="${IDRAC_SOL_USER_ID:-2}"
IDRAC_SOL_BAUD="${IDRAC_SOL_BAUD:-115200}"
IDRAC_SOL_MIN_PRIV="${IDRAC_SOL_MIN_PRIV:-3}"
IDRAC_SOL_APPLY_BIOS="${IDRAC_SOL_APPLY_BIOS:-0}"

if [[ -n "${IDRAC_PASSWORD_FILE:-}" ]]; then
  IDRAC_PASSWORD="$(< "${IDRAC_PASSWORD_FILE}")"
fi
require_var IDRAC_PASSWORD

ssh_racadm() {
  local command=$1
  SSHPASS="${IDRAC_PASSWORD}" sshpass -e ssh \
    -n \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=20 \
    "${IDRAC_USER}@${IDRAC_HOST}" \
    "${command}" 2> /dev/null
}

get_value() {
  local object=$1
  local key=$2
  ssh_racadm "racadm get ${object}" | awk -F= -v key="${key}" '$1 == key { print $2 }'
}

set_value() {
  local object=$1
  local value=$2
  ssh_racadm "racadm set ${object} ${value}" > /dev/null
}

assert_value() {
  local object=$1
  local key=$2
  local expected=$3
  local actual
  actual="$(get_value "${object}" "${key}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'ERROR: %s expected %s but found %s\n' "${object}" "${expected}" "${actual:-<empty>}" >&2
    return 1
  fi
  printf '%s=%s\n' "${object}" "${actual}"
}

set_value iDRAC.IPMILan.Enable Enabled || true
set_value iDRAC.IPMISOL.Enable Enabled
set_value iDRAC.IPMISol.BaudRate "${IDRAC_SOL_BAUD}"
set_value iDRAC.IPMISol.MinPrivilege "${IDRAC_SOL_MIN_PRIV}"
set_value "iDRAC.Users.${IDRAC_SOL_USER_ID}.SolEnable" 1

assert_value iDRAC.IPMILan.Enable Enable Enabled
assert_value iDRAC.IPMISOL.Enable Enable Enabled
assert_value iDRAC.IPMISol.BaudRate BaudRate "${IDRAC_SOL_BAUD}"
assert_value "iDRAC.Users.${IDRAC_SOL_USER_ID}.SolEnable" SolEnable Enabled

bios_checks=(
  'BIOS.SerialCommSettings.SerialComm:SerialComm:OnConRedirCom1'
  'BIOS.SerialCommSettings.SerialPortAddress:SerialPortAddress:Serial1Com2Serial2Com1'
  'BIOS.SerialCommSettings.ExtSerialConnector:ExtSerialConnector:Serial1'
  'BIOS.SerialCommSettings.FailSafeBaud:FailSafeBaud:115200'
  'BIOS.SerialCommSettings.ConTermType:ConTermType:Vt100Vt220'
  'BIOS.SerialCommSettings.RedirAfterBoot:RedirAfterBoot:Enabled'
)

missing_bios=0
for check in "${bios_checks[@]}"; do
  IFS=: read -r object key expected <<< "${check}"
  actual="$(get_value "${object}" "${key}")"
  if [[ "${actual}" == "${expected}" ]]; then
    printf '%s=%s\n' "${object}" "${actual}"
    continue
  fi
  missing_bios=1
  printf 'WARN: %s expected %s but found %s\n' "${object}" "${expected}" "${actual:-<empty>}" >&2
done

if [[ "${missing_bios}" -eq 0 ]]; then
  exit 0
fi

if [[ "${IDRAC_SOL_APPLY_BIOS}" != "1" ]]; then
  printf 'ERROR: BIOS serial redirection differs from SOL baseline; rerun with IDRAC_SOL_APPLY_BIOS=1 during an approved maintenance window.\n' >&2
  exit 1
fi

set_value BIOS.SerialCommSettings.SerialComm OnConRedirCom1
set_value BIOS.SerialCommSettings.SerialPortAddress Serial1Com2Serial2Com1
set_value BIOS.SerialCommSettings.ExtSerialConnector Serial1 || true
set_value BIOS.SerialCommSettings.FailSafeBaud 115200
set_value BIOS.SerialCommSettings.ConTermType Vt100Vt220
set_value BIOS.SerialCommSettings.RedirAfterBoot Enabled

if ssh_racadm 'racadm jobqueue create BIOS.Setup.1-1' > /dev/null; then
  printf 'BIOS serial-redirection settings staged; reboot required for application.\n'
else
  printf 'WARN: BIOS settings were requested, but jobqueue creation did not report success. Check iDRAC pending jobs before reboot.\n' >&2
fi
