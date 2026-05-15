#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/backup-hasslehoff-scheduled.sh"
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
require_grep 'HASSLEHOFF_BACKUP_MIRROR_TARGET' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_VERIFY' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_LOCKFILE' "${SCRIPT}"
require_grep 'backup-hasslehoff-config.sh' "${SCRIPT}"
require_grep 'mkdir -p' "${SCRIPT}"
require_grep 'rsync -aH' "${SCRIPT}"
require_grep 'sha256sum -c' "${SCRIPT}"
require_grep 'rfc1918.hasslehoff.scheduled-backup.v1' "${SCRIPT}"
require_grep 'write_manifest "captured"' "${SCRIPT}"
require_grep 'write_manifest "captured-and-mirrored"' "${SCRIPT}"
require_grep 'msg-sun99-ntfysys.rfc1918.host' "${SCRIPT}"

require_file "${DOC}"
require_grep 'backup-hasslehoff-scheduled.sh' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_TARGET' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_NOTIFY' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_VERIFY' "${DOC}"
require_grep 'kvm-sfo200-nasa-9918.vernetzen.io' "${DOC}"
require_grep '10.200.99.18' "${DOC}"
require_grep 'rsync-over-SSH' "${DOC}"
require_grep 'tcp/2049' "${DOC}"

require_file "${WIKI}"
require_grep 'backup-hasslehoff-scheduled.sh' "${WIKI}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_TARGET' "${WIKI}"
require_grep 'kvm-sfo200-nasa-9918.vernetzen.io' "${WIKI}"
require_grep 'rsync-over-SSH' "${WIKI}"

HASSLEHOFF_BACKUP_DRY_RUN=1 \
  HASSLEHOFF_BACKUP_STAMP=20260515T000000Z \
  HASSLEHOFF_BACKUP_MIRROR_TARGET=backup.example:/srv/hasslehoff \
  bash "${SCRIPT}" > /tmp/hasslehoff-scheduled-backup-test.out

grep -q 'source=root@hasslehoff' /tmp/hasslehoff-scheduled-backup-test.out || fail "dry-run missing source"
grep -q 'dest=.*/20260515T000000Z' /tmp/hasslehoff-scheduled-backup-test.out || fail "dry-run missing destination"
grep -q 'mirror_target=backup.example:/srv/hasslehoff' /tmp/hasslehoff-scheduled-backup-test.out || fail "dry-run missing mirror target"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
