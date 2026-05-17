#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PROFILE_DIR="${ANSIBLE_ROOT}/profile-definitions"
PACKAGE_LIST_DIR="${ANSIBLE_ROOT}/profile-package-lists"
SERVICE_ATOMS="${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml"
DOC_FILE="${REPO_ROOT}/docs/CHANGE-CONTROL-STRATUM1-TIME-AUTHORITY.md"
WIKI_FILE="${REPO_ROOT}/docs/wiki/Stratum1-Time-Authority.md"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q "${pattern}" "${file}"
}

test -f "${PROFILE_DIR}/metal-time-authority-stratum1.yml"
test -f "${PROFILE_DIR}/metal-time-authority-stratum1.metadata.yml"
test -f "${PACKAGE_LIST_DIR}/stage5-metal-host-time-authority-stratum1.packages"

assert_file_contains "${PROFILE_DIR}/metal-time-authority-stratum1.yml" '^gentoo_profile_definition:'
assert_file_contains "${PROFILE_DIR}/metal-time-authority-stratum1.metadata.yml" '^gentoo_system_profile_metadata:'
assert_file_contains "${PROFILE_DIR}/metal-time-authority-stratum1.yml" 'u-blox-max-m8q-gpio-hat'
assert_file_contains "${PROFILE_DIR}/metal-time-authority-stratum1.yml" 'CONFIG_NTP_PPS'
assert_file_contains "${PROFILE_DIR}/metal-time-authority-stratum1.yml" 'CONFIG_PTP_1588_CLOCK'
assert_file_contains "${PROFILE_DIR}/metal-time-authority-stratum1.yml" 'ptp4l must remain disabled'

for package_atom in \
  '^net-misc/chrony$' \
  '^sci-geosciences/gpsd$' \
  '^sys-apps/pps-tools$' \
  '^net-misc/linuxptp$' \
  '^app-metrics/chrony_exporter$'; do
  assert_file_contains "${PACKAGE_LIST_DIR}/stage5-metal-host-time-authority-stratum1.packages" "${package_atom}"
done

assert_file_contains "${SERVICE_ATOMS}" 'metal-time-authority-stratum1:'
assert_file_contains "${SERVICE_ATOMS}" 'chrony-stratum1'
assert_file_contains "${SERVICE_ATOMS}" 'gnss-pps'
assert_file_contains "${SERVICE_ATOMS}" 'ptp-grandmaster-candidate'
assert_file_contains "${SERVICE_ATOMS}" 'udp/123'
assert_file_contains "${SERVICE_ATOMS}" 'udp/319'
assert_file_contains "${SERVICE_ATOMS}" 'udp/320'

test -f "${DOC_FILE}"
test -f "${WIKI_FILE}"
assert_file_contains "${DOC_FILE}" 'U-Blox MAX-M8Q'
assert_file_contains "${DOC_FILE}" 'PTP grandmaster mode is gated'
assert_file_contains "${DOC_FILE}" 'local stratum'
assert_file_contains "${WIKI_FILE}" 'metal-time-authority-stratum1'

printf 'PASS: %s\n' "$(basename "$0")"
