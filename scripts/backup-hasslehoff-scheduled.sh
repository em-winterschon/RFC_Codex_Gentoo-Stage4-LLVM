#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HASSLEHOFF_SSH_TARGET="${HASSLEHOFF_SSH_TARGET:-root@hasslehoff}"
HASSLEHOFF_BACKUP_ROOT="${HASSLEHOFF_BACKUP_ROOT:-/root/operator-private/hasslehoff/backups}"
HASSLEHOFF_BACKUP_STAMP="${HASSLEHOFF_BACKUP_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
HASSLEHOFF_BACKUP_DRY_RUN="${HASSLEHOFF_BACKUP_DRY_RUN:-0}"
HASSLEHOFF_BACKUP_MIRROR_TARGET="${HASSLEHOFF_BACKUP_MIRROR_TARGET:-}"
HASSLEHOFF_BACKUP_MIRROR_VERIFY="${HASSLEHOFF_BACKUP_MIRROR_VERIFY:-0}"
HASSLEHOFF_BACKUP_RESTORE_VERIFY="${HASSLEHOFF_BACKUP_RESTORE_VERIFY:-0}"
HASSLEHOFF_BACKUP_PREFLIGHT_ONLY="${HASSLEHOFF_BACKUP_PREFLIGHT_ONLY:-0}"
HASSLEHOFF_BACKUP_RETENTION_DAYS="${HASSLEHOFF_BACKUP_RETENTION_DAYS:-0}"
HASSLEHOFF_BACKUP_RETENTION_APPLY="${HASSLEHOFF_BACKUP_RETENTION_APPLY:-0}"
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
  HASSLEHOFF_BACKUP_RESTORE_VERIFY=1
  HASSLEHOFF_BACKUP_PREFLIGHT_ONLY=1
  HASSLEHOFF_BACKUP_RETENTION_DAYS=14
  HASSLEHOFF_BACKUP_RETENTION_APPLY=1
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

reject_x12again_target() {
  local target="$1"
  local lowered
  lowered="$(printf '%s' "${target}" | tr '[:upper:]' '[:lower:]')"

  case "${lowered}" in
    *x12again*|*prinzessin*|*172.16.99.108*)
      log "refusing X12AGAIN-dependent mirror target: ${target}"
      exit 64
      ;;
  esac
}

preflight_mirror_target() {
  local target="$1"
  [[ -n "${target}" ]] || {
    log "HASSLEHOFF_BACKUP_PREFLIGHT_ONLY requires HASSLEHOFF_BACKUP_MIRROR_TARGET"
    exit 64
  }

  reject_x12again_target "${target}"

  if [[ "${target}" == *:* ]]; then
    local remote="${target%%:*}"
    local remote_base="${target#*:}"
    log "preflighting remote mirror target ${remote}:${remote_base%/}"
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${remote}" \
      "test -d '${remote_base%/}' && test -w '${remote_base%/}'"
  else
    log "preflighting local mirror target ${target%/}"
    [[ -d "${target%/}" && -w "${target%/}" ]] || {
      log "local mirror target is not a writable directory: ${target%/}"
      exit 73
    }
  fi
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

verify_mirror_readback() {
  local target="$1"
  [[ -n "${target}" ]] || return 0

  if [[ "${target}" == *:* ]]; then
    local remote="${target%%:*}"
    local remote_path="${target#*:}/${HASSLEHOFF_BACKUP_STAMP}"
    log "running remote restore/readback verification on ${remote}:${remote_path}"
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${remote}" \
      "cd '${remote_path}' && test -s manifest.json && grep -q 'rfc1918.hasslehoff.scheduled-backup.v1' manifest.json && sha256sum -c hasslehoff-config-backup-${HASSLEHOFF_BACKUP_STAMP}.tar.gz.sha256"
  else
    local mirror_path="${target%/}/${HASSLEHOFF_BACKUP_STAMP}"
    log "running local restore/readback verification at ${mirror_path}"
    (
      cd "${mirror_path}"
      test -s manifest.json
      grep -q 'rfc1918.hasslehoff.scheduled-backup.v1' manifest.json
      sha256sum -c "hasslehoff-config-backup-${HASSLEHOFF_BACKUP_STAMP}.tar.gz.sha256"
    )
  fi
}

sync_manifest_to_mirror() {
  local target="$1"
  [[ -n "${target}" ]] || return 0

  local remote_dest="${target%/}/${HASSLEHOFF_BACKUP_STAMP}/"
  log "syncing final manifest to ${remote_dest}"
  rsync -aH "${DEST}/manifest.json" "${remote_dest}manifest.json"
}

apply_retention() {
  local days="${HASSLEHOFF_BACKUP_RETENTION_DAYS}"
  [[ "${days}" =~ ^[0-9]+$ ]] || {
    log "HASSLEHOFF_BACKUP_RETENTION_DAYS must be numeric: ${days}"
    exit 64
  }
  [[ "${days}" -gt 0 ]] || return 0

  log "retention scan: root=${HASSLEHOFF_BACKUP_ROOT} days=${days} apply=${HASSLEHOFF_BACKUP_RETENTION_APPLY}"
  if [[ "${HASSLEHOFF_BACKUP_RETENTION_APPLY}" == "1" ]]; then
    find "${HASSLEHOFF_BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}" -print -exec rm -rf {} +
  else
    find "${HASSLEHOFF_BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}" -print || true
  fi
}

mirror_backup() {
  local target="$1"
  [[ -n "${target}" ]] || return 0

  reject_x12again_target "${target}"

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
  if [[ -n "${HASSLEHOFF_BACKUP_MIRROR_TARGET}" ]]; then
    reject_x12again_target "${HASSLEHOFF_BACKUP_MIRROR_TARGET}"
  fi

  if [[ "${HASSLEHOFF_BACKUP_PREFLIGHT_ONLY}" == "1" ]]; then
    preflight_mirror_target "${HASSLEHOFF_BACKUP_MIRROR_TARGET}"
    printf 'preflight_status=ok\n'
    printf 'mirror_target=%s\n' "${HASSLEHOFF_BACKUP_MIRROR_TARGET}"
    exit 0
  fi

  if [[ "${HASSLEHOFF_BACKUP_DRY_RUN}" == "1" ]]; then
    printf 'source=%s\n' "${HASSLEHOFF_SSH_TARGET}"
    printf 'dest=%s\n' "${DEST}"
    printf 'mirror_target=%s\n' "${HASSLEHOFF_BACKUP_MIRROR_TARGET:-<none>}"
    printf 'lockfile=%s\n' "${HASSLEHOFF_BACKUP_LOCKFILE}"
    printf 'notify=%s\n' "${HASSLEHOFF_BACKUP_NOTIFY}"
    printf 'restore_verify=%s\n' "${HASSLEHOFF_BACKUP_RESTORE_VERIFY}"
    printf 'retention_days=%s\n' "${HASSLEHOFF_BACKUP_RETENTION_DAYS}"
    printf 'retention_apply=%s\n' "${HASSLEHOFF_BACKUP_RETENTION_APPLY}"
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
    sync_manifest_to_mirror "${HASSLEHOFF_BACKUP_MIRROR_TARGET}"
    if [[ "${HASSLEHOFF_BACKUP_RESTORE_VERIFY}" == "1" ]]; then
      verify_mirror_readback "${HASSLEHOFF_BACKUP_MIRROR_TARGET}"
    fi
  fi
  apply_retention

  notify "Hasslehoff backup passed" "Hasslehoff backup ${HASSLEHOFF_BACKUP_STAMP} completed at ${DEST}."
  log "backup complete: ${DEST}"
}

trap 'notify "Hasslehoff backup failed" "Hasslehoff backup ${HASSLEHOFF_BACKUP_STAMP} failed; inspect controller logs."' ERR
main "$@"
