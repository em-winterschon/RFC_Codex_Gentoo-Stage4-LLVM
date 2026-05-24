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

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT
dry_run_output="${temp_dir}/hasslehoff-scheduled-backup-test.out"
x12again_output="${temp_dir}/hasslehoff-scheduled-backup-x12again.out"
preflight_output="${temp_dir}/hasslehoff-scheduled-backup-preflight.out"
preflight_dir="${temp_dir}/preflight"
mkdir -p "${preflight_dir}"

require_file "${SCRIPT}"
bash -n "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_TARGET' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_VERIFY' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_RESTORE_VERIFY' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_PREFLIGHT_ONLY' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_RETENTION_DAYS' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_RETENTION_APPLY' "${SCRIPT}"
require_grep 'HASSLEHOFF_BACKUP_LOCKFILE' "${SCRIPT}"
require_grep 'backup-hasslehoff-config.sh' "${SCRIPT}"
require_grep 'reject_x12again_target' "${SCRIPT}"
require_grep 'mkdir -p' "${SCRIPT}"
require_grep 'rsync -aH' "${SCRIPT}"
require_grep '--no-owner --no-group' "${SCRIPT}"
require_grep 'sha256sum -c' "${SCRIPT}"
require_grep 'manifest.json' "${SCRIPT}"
require_grep 'sync_manifest_to_mirror' "${SCRIPT}"
require_grep 'rfc1918.hasslehoff.scheduled-backup.v1' "${SCRIPT}"
require_grep 'write_manifest "captured"' "${SCRIPT}"
require_grep 'write_manifest "captured-and-mirrored"' "${SCRIPT}"
require_grep 'msg-sun99-ntfysys.rfc1918.host' "${SCRIPT}"

require_file "${DOC}"
require_grep 'backup-hasslehoff-scheduled.sh' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_TARGET' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_NOTIFY' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_VERIFY' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_RESTORE_VERIFY' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_PREFLIGHT_ONLY' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS' "${DOC}"
require_grep 'HASSLEHOFF_BACKUP_RETENTION_DAYS' "${DOC}"
require_grep 'kvm-sfo200-nasa-9918.vernetzen.io' "${DOC}"
require_grep '10.200.99.18' "${DOC}"
require_grep 'M70 NASA NFS relay' "${DOC}"
require_grep 'X12AGAIN must not mount NASA NFS' "${DOC}"
require_grep 'refuses X12AGAIN' "${DOC}"
require_grep 'admin-sun99-forge-099070' "${DOC}"
require_grep 'rsync-over-SSH' "${DOC}"
require_grep 'tcp/2049' "${DOC}"
require_grep '/srv/nfs/rfc1918/nasa/chunkers' "${DOC}"
require_grep 'ora-sas-mpaths/chunkers/rfc1918.nfs' "${DOC}"
require_grep '172.16.99.0/24' "${DOC}"
require_grep '192.168.132.0/24' "${DOC}"
require_grep 'all_squash' "${DOC}"
require_grep 'successful M70 NFSv3 mount' "${DOC}"
require_grep 'hasslehoff/config-bundles' "${DOC}"
require_grep 'forge/transfer-stage' "${DOC}"
require_grep 'UID/GID 8888' "${DOC}"
require_grep '--no-owner --no-group' "${DOC}"

require_file "${WIKI}"
require_grep 'backup-hasslehoff-scheduled.sh' "${WIKI}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_TARGET' "${WIKI}"
require_grep 'HASSLEHOFF_BACKUP_RESTORE_VERIFY' "${WIKI}"
require_grep 'HASSLEHOFF_BACKUP_MIRROR_RSYNC_OPTS' "${WIKI}"
require_grep 'HASSLEHOFF_BACKUP_RETENTION_DAYS' "${WIKI}"
require_grep 'kvm-sfo200-nasa-9918.vernetzen.io' "${WIKI}"
require_grep 'M70 NASA NFS relay' "${WIKI}"
require_grep 'X12AGAIN must not mount NASA NFS' "${WIKI}"
require_grep 'refuses X12AGAIN' "${WIKI}"
require_grep 'rsync-over-SSH' "${WIKI}"
require_grep '/srv/nfs/rfc1918/nasa/chunkers' "${WIKI}"
require_grep 'ora-sas-mpaths/chunkers/rfc1918.nfs' "${WIKI}"
require_grep 'successful M70 NFSv3 mount' "${WIKI}"
require_grep 'hasslehoff/config-bundles' "${WIKI}"
require_grep '--no-owner --no-group' "${WIKI}"

HASSLEHOFF_BACKUP_DRY_RUN=1 \
  HASSLEHOFF_BACKUP_STAMP=20260515T000000Z \
  HASSLEHOFF_BACKUP_MIRROR_TARGET=backup.example:/srv/hasslehoff \
  bash "${SCRIPT}" > "${dry_run_output}"

grep -q 'source=root@hasslehoff' "${dry_run_output}" || fail "dry-run missing source"
grep -q 'dest=.*/20260515T000000Z' "${dry_run_output}" || fail "dry-run missing destination"
grep -q 'mirror_target=backup.example:/srv/hasslehoff' "${dry_run_output}" || fail "dry-run missing mirror target"
grep -q 'mirror_rsync_opts=--no-owner --no-group' "${dry_run_output}" || fail "dry-run missing mirror rsync opts"
grep -q 'restore_verify=0' "${dry_run_output}" || fail "dry-run missing restore verify"
grep -q 'retention_days=0' "${dry_run_output}" || fail "dry-run missing retention days"

if HASSLEHOFF_BACKUP_DRY_RUN=1 \
  HASSLEHOFF_BACKUP_MIRROR_TARGET=root@x12again:/srv/backups \
  bash "${SCRIPT}" > "${x12again_output}" 2>&1; then
  fail "x12again mirror target was not rejected"
fi
grep -qi 'x12again' "${x12again_output}" || fail "x12again rejection did not mention target"

HASSLEHOFF_BACKUP_PREFLIGHT_ONLY=1 \
  HASSLEHOFF_BACKUP_MIRROR_TARGET="${preflight_dir}" \
  bash "${SCRIPT}" > "${preflight_output}"
grep -q 'preflight_status=ok' "${preflight_output}" || fail "preflight did not pass local writable target"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
