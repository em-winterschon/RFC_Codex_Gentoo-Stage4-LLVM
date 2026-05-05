#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/backup-hasslehoff-config.sh"
DOC="${REPO_ROOT}/docs/HASSLEHOFF-BACKUP.md"
WIKI="${REPO_ROOT}/docs/wiki/Hasslehoff-Backup.md"

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
require_grep 'root@hasslehoff' "${SCRIPT}"
require_grep '/root/operator-private/hasslehoff/backups' "${SCRIPT}"
require_grep '/etc/pve' "${SCRIPT}"
require_grep '/etc/network/interfaces' "${SCRIPT}"
require_grep 'pvesh get /nodes/hasslehoff/qemu' "${SCRIPT}"
require_grep 'sha256sum' "${SCRIPT}"
require_grep 'basename "\${BACKUP_BUNDLE}"' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_DRY_RUN' "${SCRIPT}"

require_file "${DOC}"
require_grep 'Emergency Gateway Ethernet WAN Link' "${DOC}"
require_grep '/dev/ttyUSB2' "${DOC}"

require_file "${WIKI}"
require_grep 'Emergency Gateway Ethernet WAN Link' "${WIKI}"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
