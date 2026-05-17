#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HASSLEHOFF_SSH_TARGET="${HASSLEHOFF_SSH_TARGET:-root@hasslehoff}"
HASSLEHOFF_BACKUP_ROOT="${HASSLEHOFF_BACKUP_ROOT:-/root/operator-private/hasslehoff/backups}"
HASSLEHOFF_BACKUP_STAMP="${HASSLEHOFF_BACKUP_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
HASSLEHOFF_BACKUP_DRY_RUN="${HASSLEHOFF_BACKUP_DRY_RUN:-0}"
HASSLEHOFF_BACKUP_MIRROR_TARGET="${HASSLEHOFF_BACKUP_MIRROR_TARGET:-}"
HASSLEHOFF_BACKUP_MIRROR_VERIFY="${HASSLEHOFF_BACKUP_MIRROR_VERIFY:-0}"
HASSLEHOFF_BACKUP_LOCKFILE="${HASSLEHOFF_BACKUP_LOCKFILE:-/tmp/hasslehoff-scheduled-backup.lock}"
HASSLEHOFF_BACKUP_NOTIFY="${HASSLEHOFF_BACKUP_NOTIFY:-0}"
HASSLEHOFF_BACKUP_NTFY_URL="${HASSLEHOFF_BACKUP_NTFY_URL:-http://msg-sun99-ntfysys.rfc1918.host}"
HASSLEHOFF_BACKUP_NTFY_TOPIC="${HASSLEHOFF_BACKUP_NTFY_TOPIC:-forge-obs}"

DEST="${HASSLEHOFF_BACKUP_ROOT}/${HASSLEHOFF_BACKUP_STAMP}"

usage() {
  cat << 'USAGE'
Usage: backup-hasslehoff-scheduled.sh

Runs the Hasslehoff config/state backup and optionally mirrors the timestamped
result to an off-host target. This wrapper is safe for cron/anacron/OpenRC
scheduling because it uses a lockfile and does not delete remote data.

Environment:
  HASSLEHOFF_SSH_TARGET=root@hasslehoff
  HASSLEHOFF_BACKUP_ROOT=/root/operator-private/hasslehoff/backups
  HASSLEHOFF_BACKUP_STAMP=YYYYMMDDTHHMMSSZ
  HASSLEHOFF_BACKUP_DRY_RUN=1
  HASSLEHOFF_BACKUP_MIRROR_TARGET=user@host:/path/to/backups
  HASSLEHOFF_BACKUP_MIRROR_VERIFY=1
  HASSLEHOFF_BACKUP_NOTIFY=1
  HASSLEHOFF_BACKUP_NTFY_URL=http://msg-sun99-ntfysys.rfc1918.host
  HASSLEHOFF_BACKUP_NTFY_TOPIC=forge-obs
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '[hasslehoff-scheduled-backup] %s\n' "$*" >&2
}

notify() {
  local title="$1"
  local body="$2"

  [[ "${HASSLEHOFF_BACKUP_NOTIFY}" == "1" ]] || return 0

  curl -fsS \
    -H "Title: ${title}" \
    -H "Tags: backup,hasslehoff" \
    --data-binary "${body}" \
    "${HASSLEHOFF_BACKUP_NTFY_URL%/}/${HASSLEHOFF_BACKUP_NTFY_TOPIC}" > /dev/null || true
}

write_manifest() {
  local status="$1"
  local tarball
  local sha_file
  tarball="$(find "${DEST}" -maxdepth 1 -type f -name 'hasslehoff-config-backup-*.tar.gz' -print -quit)"
  sha_file="$(find "${DEST}" -maxdepth 1 -type f -name 'hasslehoff-config-backup-*.tar.gz.sha256' -print -quit)"

  python3 - "$DEST/manifest.json" "$status" "$HASSLEHOFF_SSH_TARGET" "$DEST" "$HASSLEHOFF_BACKUP_MIRROR_TARGET" "$tarball" "$sha_file" << 'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
payload = {
    "schema": "rfc1918.hasslehoff.scheduled-backup.v1",
    "status": sys.argv[2],
    "source": sys.argv[3],
    "destination": sys.argv[4],
    "mirror_target": sys.argv[5] or None,
    "tarball": pathlib.Path(sys.argv[6]).name if sys.argv[6] else None,
    "sha256_file": pathlib.Path(sys.argv[7]).name if sys.argv[7] else None,
}
manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

mirror_backup() {
  local target="$1"
  [[ -n "${target}" ]] || return 0

  local remote_dest="${target%/}/${HASSLEHOFF_BACKUP_STAMP}/"
  if [[ "${target}" == *:* ]]; then
    local remote="${target%%:*}"
    local remote_base="${target#*:}"
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${remote}" \
      "mkdir -p '${remote_base%/}/${HASSLEHOFF_BACKUP_STAMP}'"
  else
    install -d -m 0700 "${remote_dest}"
  fi

  log "mirroring ${DEST}/ to ${remote_dest}"
  rsync -aH --info=stats1 "${DEST}/" "${remote_dest}"

  if [[ "${HASSLEHOFF_BACKUP_MIRROR_VERIFY}" == "1" && "${target}" == *:* ]]; then
    local remote_path="${target#*:}/${HASSLEHOFF_BACKUP_STAMP}"
    log "verifying remote SHA256 on ${remote}:${remote_path}"
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${remote}" \
      "cd '${remote_path}' && sha256sum -c hasslehoff-config-backup-${HASSLEHOFF_BACKUP_STAMP}.tar.gz.sha256"
  elif [[ "${HASSLEHOFF_BACKUP_MIRROR_VERIFY}" == "1" ]]; then
    log "verifying local mirror SHA256 at ${remote_dest}"
    (cd "${remote_dest}" && sha256sum -c "hasslehoff-config-backup-${HASSLEHOFF_BACKUP_STAMP}.tar.gz.sha256")
  fi
}

main() {
  if [[ "${HASSLEHOFF_BACKUP_DRY_RUN}" == "1" ]]; then
    printf 'source=%s\n' "${HASSLEHOFF_SSH_TARGET}"
    printf 'dest=%s\n' "${DEST}"
    printf 'mirror_target=%s\n' "${HASSLEHOFF_BACKUP_MIRROR_TARGET:-<none>}"
    printf 'lockfile=%s\n' "${HASSLEHOFF_BACKUP_LOCKFILE}"
    printf 'notify=%s\n' "${HASSLEHOFF_BACKUP_NOTIFY}"
    exit 0
  fi

  exec 9> "${HASSLEHOFF_BACKUP_LOCKFILE}"
  if ! flock -n 9; then
    log "another Hasslehoff backup is already running: ${HASSLEHOFF_BACKUP_LOCKFILE}"
    exit 75
  fi

  log "starting Hasslehoff config backup ${HASSLEHOFF_BACKUP_STAMP}"
  HASSLEHOFF_SSH_TARGET="${HASSLEHOFF_SSH_TARGET}" \
    HASSLEHOFF_BACKUP_ROOT="${HASSLEHOFF_BACKUP_ROOT}" \
    HASSLEHOFF_BACKUP_STAMP="${HASSLEHOFF_BACKUP_STAMP}" \
    bash "${REPO_ROOT}/scripts/backup-hasslehoff-config.sh"

  write_manifest "captured"
  if [[ -n "${HASSLEHOFF_BACKUP_MIRROR_TARGET}" ]]; then
    mirror_backup "${HASSLEHOFF_BACKUP_MIRROR_TARGET}"
    write_manifest "captured-and-mirrored"
  fi

  notify "Hasslehoff backup passed" "Hasslehoff backup ${HASSLEHOFF_BACKUP_STAMP} completed at ${DEST}."
  log "backup complete: ${DEST}"
}

trap 'notify "Hasslehoff backup failed" "Hasslehoff backup ${HASSLEHOFF_BACKUP_STAMP} failed; inspect controller logs."' ERR
main "$@"
