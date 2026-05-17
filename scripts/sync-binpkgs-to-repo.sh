#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: sync-binpkgs-to-repo.sh --pkgdir DIR --repo-id ID (--remote HOST | --local-root DIR) [options]

Sync a local Portage PKGDIR to a Stage4/Stage5 binpkg repository.

Options:
  --pkgdir DIR          Local binpkg cache directory.
  --repo-id ID          Unique repository ID under the remote root.
  --remote HOST         SSH target, such as root@10.66.40.20.
  --remote-root DIR     Remote repository root (default: /srv/stage5-binpkgs).
  --local-root DIR      Local repository root, such as a mounted NFS path.
  --index-command CMD   Remote index command (default: /usr/sbin/stage5-binpkg-index).
  --dry-run             Print the resolved plan and exit.
  --help                Show this message.
EOF
}

die() {
  printf '[sync-binpkgs-to-repo] ERROR: %s\n' "$*" >&2
  exit 1
}

PKGDIR=
REPO_ID=
REMOTE=
REMOTE_ROOT=/srv/stage5-binpkgs
LOCAL_ROOT=
INDEX_COMMAND=/usr/sbin/stage5-binpkg-index
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
  --local-root)
    LOCAL_ROOT=${2-}
    shift 2
    ;;
  --index-command)
    INDEX_COMMAND=${2-}
    shift 2
    ;;
  --dry-run)
    DRY_RUN=true
    shift
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

[[ -n "${PKGDIR}" ]] || die "--pkgdir is required"
[[ -n "${REPO_ID}" ]] || die "--repo-id is required"
[[ -d "${PKGDIR}" ]] || die "pkgdir not found: ${PKGDIR}"
[[ "${REPO_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || die "repo-id contains unsafe characters: ${REPO_ID}"
if [[ -z "${REMOTE}" && -z "${LOCAL_ROOT}" ]]; then
  die "one of --remote or --local-root is required"
fi
if [[ -n "${REMOTE}" && -n "${LOCAL_ROOT}" ]]; then
  die "use only one destination: --remote or --local-root"
fi

REMOTE_REPO="${REMOTE_ROOT%/}/${REPO_ID}"
LOCAL_REPO=
if [[ -n "${LOCAL_ROOT}" ]]; then
  LOCAL_REPO="${LOCAL_ROOT%/}/${REPO_ID}"
fi

if [[ "${DRY_RUN}" == true ]]; then
  printf 'pkgdir=%s\n' "${PKGDIR}"
  printf 'repo-id=%s\n' "${REPO_ID}"
  if [[ -n "${REMOTE}" ]]; then
    printf 'remote=%s\n' "${REMOTE}"
    printf 'remote-root=%s\n' "${REMOTE_ROOT}"
    printf 'remote-repo=%s\n' "${REMOTE_REPO}"
  else
    printf 'local-root=%s\n' "${LOCAL_ROOT}"
    printf 'local-repo=%s\n' "${LOCAL_REPO}"
  fi
  printf 'index-command=%s\n' "${INDEX_COMMAND}"
  exit 0
fi

if [[ -n "${REMOTE}" ]]; then
  ssh "${REMOTE}" "install -d -m 0755 '${REMOTE_REPO}'"
  rsync -a "${PKGDIR%/}/" "${REMOTE}:${REMOTE_REPO}/"
  ssh "${REMOTE}" "if command -v '${INDEX_COMMAND}' >/dev/null 2>&1; then '${INDEX_COMMAND}' '${REMOTE_REPO}'; elif command -v emaint >/dev/null 2>&1; then PKGDIR='${REMOTE_REPO}' emaint binhost --fix; fi"
else
  install -d -m 0755 "${LOCAL_REPO}"
  rsync -a "${PKGDIR%/}/" "${LOCAL_REPO}/"
  if command -v "${INDEX_COMMAND}" > /dev/null 2>&1; then
    "${INDEX_COMMAND}" "${LOCAL_REPO}"
  elif command -v emaint > /dev/null 2>&1; then
    PKGDIR="${LOCAL_REPO}" emaint binhost --fix
  fi
fi
