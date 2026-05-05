#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: watch-sync-binpkgs-to-repo.sh --pkgdir PATH --repo-id ID --remote HOST [options]

Continuously publish a local or SSH-remote Portage PKGDIR to a Stage4/Stage5
binpkg repository host. Remote PKGDIR sources are staged locally first because
rsync cannot copy remote-to-remote directly.

Options:
  --pkgdir PATH          Local DIR or SSH path, such as root@host:/path/binpkgs.
  --repo-id ID           Unique repository ID under the remote root.
  --remote HOST          Destination SSH target, such as root@repo-host.
  --remote-root DIR      Remote repository root (default: /srv/stage5-binpkgs).
  --staging-dir DIR      Local staging dir for remote source syncs.
  --index-command CMD    Remote index command (default: /usr/sbin/stage5-binpkg-index).
  --interval SECONDS     Watch interval (default: 300).
  --watch-remote HOST    SSH host used to test whether a build is still active.
  --watch-pid PID        Process ID to watch. May be local or remote.
  --watch-pattern TEXT   pgrep -f pattern for the active build process.
  --once                 Sync once and exit.
  --dry-run              Print the resolved plan and exit.
  --help                 Show this message.
EOF
}

die() {
  printf '[watch-sync-binpkgs-to-repo] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[%s] [watch-sync-binpkgs-to-repo] %s\n' "$(date -Is)" "$*"
}

PKGDIR=
REPO_ID=
REMOTE=
REMOTE_ROOT=/srv/stage5-binpkgs
STAGING_DIR=
INDEX_COMMAND=/usr/sbin/stage5-binpkg-index
INTERVAL=300
WATCH_REMOTE=
WATCH_PID=
WATCH_PATTERN=
ONCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pkgdir)
      PKGDIR=${2-}
      shift 2
      ;;
    --repo-id)
      REPO_ID=${2-}
      shift 2
      ;;
    --remote)
      REMOTE=${2-}
      shift 2
      ;;
    --remote-root)
      REMOTE_ROOT=${2-}
      shift 2
      ;;
    --staging-dir)
      STAGING_DIR=${2-}
      shift 2
      ;;
    --index-command)
      INDEX_COMMAND=${2-}
      shift 2
      ;;
    --interval)
      INTERVAL=${2-}
      shift 2
      ;;
    --watch-remote)
      WATCH_REMOTE=${2-}
      shift 2
      ;;
    --watch-pid)
      WATCH_PID=${2-}
      shift 2
      ;;
    --watch-pattern)
      WATCH_PATTERN=${2-}
      shift 2
      ;;
    --once)
      ONCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "${PKGDIR}" ]] || die "--pkgdir is required"
[[ -n "${REPO_ID}" ]] || die "--repo-id is required"
[[ -n "${REMOTE}" ]] || die "--remote is required"
[[ "${REPO_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || die "repo-id contains unsafe characters: ${REPO_ID}"
[[ "${INTERVAL}" =~ ^[0-9]+$ ]] || die "--interval must be an integer"

if [[ -n "${WATCH_PID}" && -n "${WATCH_PATTERN}" ]]; then
  die "--watch-pid and --watch-pattern are mutually exclusive"
fi
if [[ -n "${WATCH_PID}" ]]; then
  [[ "${WATCH_PID}" =~ ^[0-9]+$ ]] || die "--watch-pid must be an integer"
fi
if [[ -n "${WATCH_REMOTE}" && -z "${WATCH_PID}" && -z "${WATCH_PATTERN}" ]]; then
  die "--watch-remote requires --watch-pid or --watch-pattern"
fi

REMOTE_SOURCE=false
if [[ "${PKGDIR}" == *:* ]]; then
  REMOTE_SOURCE=true
fi

if [[ "${REMOTE_SOURCE}" == true && -z "${STAGING_DIR}" ]]; then
  STAGING_DIR="/var/tmp/stage5-binpkg-sync/${REPO_ID}"
fi

if [[ "${DRY_RUN}" == true ]]; then
  printf 'pkgdir=%s\n' "${PKGDIR}"
  printf 'repo-id=%s\n' "${REPO_ID}"
  printf 'remote=%s\n' "${REMOTE}"
  printf 'remote-root=%s\n' "${REMOTE_ROOT}"
  printf 'remote-source=%s\n' "${REMOTE_SOURCE}"
  printf 'staging-dir=%s\n' "${STAGING_DIR}"
  printf 'index-command=%s\n' "${INDEX_COMMAND}"
  printf 'interval=%s\n' "${INTERVAL}"
  printf 'watch-remote=%s\n' "${WATCH_REMOTE}"
  printf 'watch-pid=%s\n' "${WATCH_PID}"
  printf 'watch-pattern=%s\n' "${WATCH_PATTERN}"
  printf 'once=%s\n' "${ONCE}"
  exit 0
fi

resolve_sync_pkgdir() {
  if [[ "${REMOTE_SOURCE}" != true ]]; then
    [[ -d "${PKGDIR}" ]] || die "pkgdir not found: ${PKGDIR}"
    printf '%s\n' "${PKGDIR}"
    return 0
  fi

  install -d -m 0755 "${STAGING_DIR}"
  rsync -a "${PKGDIR%/}/" "${STAGING_DIR}/"
  printf '%s\n' "${STAGING_DIR}"
}

sync_once() {
  local sync_pkgdir
  log "sync start repo=${REPO_ID}"
  sync_pkgdir="$(resolve_sync_pkgdir)"
  "${SCRIPT_DIR}/sync-binpkgs-to-repo.sh" \
    --pkgdir "${sync_pkgdir}" \
    --repo-id "${REPO_ID}" \
    --remote "${REMOTE}" \
    --remote-root "${REMOTE_ROOT}" \
    --index-command "${INDEX_COMMAND}"
  log "sync done repo=${REPO_ID}"
}

build_is_running() {
  local quoted_pattern
  if [[ -n "${WATCH_PID}" ]]; then
    if [[ -n "${WATCH_REMOTE}" ]]; then
      ssh -n -o BatchMode=yes -o ConnectTimeout=10 "${WATCH_REMOTE}" \
        "kill -0 ${WATCH_PID} >/dev/null 2>&1"
    else
      kill -0 "${WATCH_PID}" >/dev/null 2>&1
    fi
    return $?
  fi

  [[ -n "${WATCH_PATTERN}" ]] || return 0
  quoted_pattern="$(printf '%q' "${WATCH_PATTERN}")"
  if [[ -n "${WATCH_REMOTE}" ]]; then
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 "${WATCH_REMOTE}" \
      "pgrep -af -- ${quoted_pattern} | grep -F -v 'pgrep -af --' | grep -q ."
  else
    pgrep -af -- "${WATCH_PATTERN}" | grep -F -v 'pgrep -af --' | grep -q .
  fi
}

sync_once

if [[ "${ONCE}" == true ]]; then
  exit 0
fi

while build_is_running; do
  sleep "${INTERVAL}"
  sync_once || log "sync failed; will retry"
done

sync_once || log "final sync failed"
log "watched process is no longer running; exiting"
