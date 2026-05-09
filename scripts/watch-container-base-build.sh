#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat << 'EOF'
Usage: watch-container-base-build.sh --launch-script FILE --build-log FILE [options]

Watch a detached base-container build. If the build exits before the rootfs is
completed, sync any accumulated binpkgs and relaunch a bounded number of times.

Options:
  --launch-script FILE      Script used to launch the build.
  --build-log FILE          Build log written by the launch script.
  --watch-pattern TEXT      pgrep -f pattern for the active build process.
                            Defaults to build-gentoo-rootfs-container.sh.
  --pkgdir DIR              Local Portage PKGDIR to sync.
  --repo-id ID              Stage4/Stage5 binpkg repository ID.
  --sync-remote HOST        SSH destination for binpkg sync.
  --sync-root DIR           Remote repository root (default: /srv/stage5-binpkgs).
  --interval SECONDS        Watch interval (default: 300).
  --max-restarts N          Maximum failed-build restarts (default: 2).
  --watch-log FILE          Watchdog log (default: /root/container-base-watchdog.log).
  --help                    Show this message.
EOF
}

die() {
  printf '[watch-container-base-build] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[%s] [watch-container-base-build] %s\n' "$(date -Is)" "$*" | tee -a "${WATCH_LOG}"
}

LAUNCH_SCRIPT=
BUILD_LOG=
WATCH_PATTERN=build-gentoo-rootfs-container.sh
PKGDIR=
REPO_ID=
SYNC_REMOTE=
SYNC_ROOT=/srv/stage5-binpkgs
INTERVAL=300
MAX_RESTARTS=2
WATCH_LOG=/root/container-base-watchdog.log

while [[ $# -gt 0 ]]; do
  case "$1" in
  --launch-script)
    LAUNCH_SCRIPT=${2-}
    shift 2
    ;;
  --build-log)
    BUILD_LOG=${2-}
    shift 2
    ;;
  --watch-pattern)
    WATCH_PATTERN=${2-}
    shift 2
    ;;
  --pkgdir)
    PKGDIR=${2-}
    shift 2
    ;;
  --repo-id)
    REPO_ID=${2-}
    shift 2
    ;;
  --sync-remote)
    SYNC_REMOTE=${2-}
    shift 2
    ;;
  --sync-root)
    SYNC_ROOT=${2-}
    shift 2
    ;;
  --interval)
    INTERVAL=${2-}
    shift 2
    ;;
  --max-restarts)
    MAX_RESTARTS=${2-}
    shift 2
    ;;
  --watch-log)
    WATCH_LOG=${2-}
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    die "unknown argument: $1"
    ;;
  esac
done

[[ -n "${LAUNCH_SCRIPT}" ]] || die "--launch-script is required"
[[ -f "${LAUNCH_SCRIPT}" ]] || die "launch script not found: ${LAUNCH_SCRIPT}"
[[ -n "${BUILD_LOG}" ]] || die "--build-log is required"
[[ "${INTERVAL}" =~ ^[0-9]+$ ]] || die "--interval must be an integer"
[[ "${MAX_RESTARTS}" =~ ^[0-9]+$ ]] || die "--max-restarts must be an integer"
if [[ -n "${SYNC_REMOTE}" || -n "${REPO_ID}" || -n "${PKGDIR}" ]]; then
  [[ -n "${SYNC_REMOTE}" ]] || die "--sync-remote is required when sync options are used"
  [[ -n "${REPO_ID}" ]] || die "--repo-id is required when sync options are used"
  [[ -n "${PKGDIR}" ]] || die "--pkgdir is required when sync options are used"
fi

touch "${WATCH_LOG}"

build_is_running() {
  pgrep -af -- "${WATCH_PATTERN}" |
    awk -v self="$$" '
      $1 == self { next }
      /watch-container-base-build/ { next }
      /pgrep -af/ { next }
      { found=1 }
      END { exit !found }
    '
}

build_completed() {
  [[ -f "${BUILD_LOG}" ]] && grep -q 'completed rootfs build' "${BUILD_LOG}"
}

sync_binpkgs() {
  [[ -n "${SYNC_REMOTE}" ]] || return 0
  [[ -d "${PKGDIR}" ]] || return 0
  log "syncing binpkgs to ${SYNC_REMOTE}:${SYNC_ROOT%/}/${REPO_ID}"
  "${SCRIPT_DIR}/sync-binpkgs-to-repo.sh" \
    --pkgdir "${PKGDIR}" \
    --repo-id "${REPO_ID}" \
    --remote "${SYNC_REMOTE}" \
    --remote-root "${SYNC_ROOT}"
}

snapshot_status() {
  if [[ -f "${BUILD_LOG}" ]]; then
    grep -E '>>> Jobs:|Failed to emerge|failed|completed rootfs build|sys-apps/coreutils' "${BUILD_LOG}" |
      tail -n 12 |
      sed 's/^/[watch-container-base-build] build-log: /' |
      tee -a "${WATCH_LOG}" > /dev/null || true
  fi
}

relaunch_build() {
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  if [[ -f "${BUILD_LOG}" ]]; then
    cp -f "${BUILD_LOG}" "${BUILD_LOG%.log}.${stamp}.log"
  fi
  log "relaunching build with ${LAUNCH_SCRIPT}"
  setsid -f bash -c "exec '${LAUNCH_SCRIPT}' > '${BUILD_LOG}' 2>&1"
}

restarts=0
log "watchdog started interval=${INTERVAL}s max_restarts=${MAX_RESTARTS} pattern=${WATCH_PATTERN}"

while true; do
  if build_is_running; then
    snapshot_status
    sleep "${INTERVAL}"
    continue
  fi

  snapshot_status
  sync_binpkgs || log "binpkg sync failed; continuing watchdog flow"

  if build_completed; then
    log "build completed; watchdog exiting"
    exit 0
  fi

  if ((restarts >= MAX_RESTARTS)); then
    log "build is stopped and restart budget is exhausted"
    exit 1
  fi

  restarts=$((restarts + 1))
  log "build stopped before completion; restart ${restarts}/${MAX_RESTARTS}"
  relaunch_build
  sleep "${INTERVAL}"
done
