#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/validate-sun99-power-recovery.sh"
DOC="${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
WIKI="${REPO_ROOT}/docs/wiki/Sun99-Power-Recovery.md"

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

require_file "${SCRIPT}"
bash -n "${SCRIPT}"
require_grep 'SUN99_POWER_SKIP_LIVE' "${SCRIPT}"
require_grep 'This script must not mutate hosts' "${SCRIPT}"
require_grep 'chronyd' "${SCRIPT}"
require_grep 'openvpn.fmt2' "${SCRIPT}"
require_grep 'pdu-rfc99-corectrl-p08-099241' "${SCRIPT}"
require_grep 'CyberPower CP1500PFCRM2U' "${SCRIPT}"
require_grep '172.16.99.242' "${SCRIPT}"
require_grep '172.16.99.244' "${SCRIPT}"
require_grep '172.16.99.250' "${SCRIPT}"
require_grep 'apcupsd' "${SCRIPT}"

require_file "${DOC}"
require_grep 'Post-Incident Recovery Gate' "${DOC}"
require_grep 'CyberPower CP1500PFCRM2U' "${DOC}"
require_grep 'APC SRT1500RMXLA' "${DOC}"
require_grep 'ATS' "${DOC}"
require_grep 'Blackbox' "${DOC}"
require_grep 'NUT' "${DOC}"
require_grep 'apcupsd' "${DOC}"

require_file "${WIKI}"
require_grep 'Post-Incident Recovery Gate' "${WIKI}"
require_grep 'CyberPower CP1500PFCRM2U' "${WIKI}"
require_grep 'APC SRT1500RMXLA' "${WIKI}"
require_grep 'ATS' "${WIKI}"
require_grep 'Blackbox' "${WIKI}"

SUN99_POWER_SKIP_LIVE=1 bash "${SCRIPT}" > /tmp/sun99-power-recovery-test.out
grep -q 'summary: failures=0' /tmp/sun99-power-recovery-test.out || {
  cat /tmp/sun99-power-recovery-test.out >&2
  fail "repo-only power recovery validator did not pass"
}

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
