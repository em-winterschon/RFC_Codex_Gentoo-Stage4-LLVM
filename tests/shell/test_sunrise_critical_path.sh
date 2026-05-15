#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/validate-sunrise-critical-path.sh"
DOC="${REPO_ROOT}/docs/SUNRISE-CRITICAL-PATH.md"
WIKI="${REPO_ROOT}/docs/wiki/Sunrise-Critical-Path.md"

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
require_grep 'SUNRISE_SKIP_LIVE' "${SCRIPT}"
require_grep 'openvpn.fmt2' "${SCRIPT}"
require_grep 'tun-fmt2' "${SCRIPT}"
require_grep 'backup-hasslehoff-config.sh' "${SCRIPT}"
require_grep 'msg-sun99-ntfysys.rfc1918.host' "${SCRIPT}"
require_grep 'This script must not mutate hosts' "${SCRIPT}"

require_file "${DOC}"
require_grep 'Daily Gate' "${DOC}"
require_grep 'M70 continuity' "${DOC}"
require_grep 'Hasslehoff backup' "${DOC}"
require_grep 'FMT2 transport' "${DOC}"
require_grep 'SLURM pilot' "${DOC}"
require_grep 'X12AGAIN reimage' "${DOC}"
require_grep 'SUNRISE_NOTIFY=1' "${DOC}"

require_file "${WIKI}"
require_grep 'Daily Gate' "${WIKI}"
require_grep 'M70 continuity' "${WIKI}"
require_grep 'Hasslehoff backup' "${WIKI}"
require_grep 'FMT2 transport' "${WIKI}"
require_grep 'SLURM pilot' "${WIKI}"
require_grep 'X12AGAIN reimage' "${WIKI}"

SUNRISE_SKIP_LIVE=1 bash "${SCRIPT}" > /tmp/sunrise-critical-path-test.out
grep -q 'summary: failures=0' /tmp/sunrise-critical-path-test.out || {
  cat /tmp/sunrise-critical-path-test.out >&2
  fail "repo-only sunrise validator did not pass"
}

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
