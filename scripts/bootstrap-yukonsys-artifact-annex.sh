#!/usr/bin/env bash
set -euo pipefail

ANNEX_DESCRIPTION="forge-artifact-plane"
BACKEND="SHA256E"
DRY_RUN=0
GPG_KEY=""
NUMCOPIES=2
REMOTE_ENCRYPTION="hybrid"
REMOTE_MAC="HMACSHA256"
REMOTE_NAME="nasa-nfs-artifact-annex"
REMOTE_PATH="/mnt/nasa/forge/git-annex/YukonSYS-Artifact-Annex"
REPO_PATH="/opt/org-repos/yukon.systems/YukonSYS-Artifact-Annex"

usage() {
  cat << 'USAGE'
Usage: bootstrap-yukonsys-artifact-annex.sh [options]

Options:
  --repo PATH                 Local Git-Annex repository path.
  --remote-path PATH          Directory special remote path.
  --remote-name NAME          Special remote name.
  --gpg-key KEYID             GPG key id/fingerprint for encrypted remote.
  --backend NAME              Git-Annex backend. Default: SHA256E.
  --remote-encryption MODE    Remote encryption mode. Default: hybrid.
  --remote-mac NAME           Remote filename MAC. Default: HMACSHA256.
  --numcopies N               Required copy count. Default: 2.
  --dry-run                   Print commands without executing them.
  -h, --help                  Show this help.
USAGE
}

die() {
  printf '[bootstrap-yukonsys-artifact-annex] ERROR: %s\n' "$*" >&2
  exit 1
}

quote_args() {
  local arg
  for arg in "$@"; do
    printf ' %q' "${arg}"
  done
  printf '\n'
}

run() {
  printf '+'
  quote_args "$@"
  if [[ "${DRY_RUN}" == 0 ]]; then
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo)
    REPO_PATH="${2:?missing --repo value}"
    shift 2
    ;;
  --remote-path)
    REMOTE_PATH="${2:?missing --remote-path value}"
    shift 2
    ;;
  --remote-name)
    REMOTE_NAME="${2:?missing --remote-name value}"
    shift 2
    ;;
  --gpg-key)
    GPG_KEY="${2:?missing --gpg-key value}"
    shift 2
    ;;
  --backend)
    BACKEND="${2:?missing --backend value}"
    shift 2
    ;;
  --remote-encryption)
    REMOTE_ENCRYPTION="${2:?missing --remote-encryption value}"
    shift 2
    ;;
  --remote-mac)
    REMOTE_MAC="${2:?missing --remote-mac value}"
    shift 2
    ;;
  --numcopies)
    NUMCOPIES="${2:?missing --numcopies value}"
    shift 2
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument: $1"
    ;;
  esac
done

case "${BACKEND}" in
SHA256E) ;;
SHA1 | SHA1E | MD5 | MD5E | WORM | URL)
  die "forbidden Git-Annex backend: ${BACKEND}"
  ;;
*)
  die "unsupported YukonSYS artifact-plane backend: ${BACKEND}; use SHA256E"
  ;;
esac

case "${REMOTE_ENCRYPTION}" in
hybrid | pubkey | sharedpubkey | none) ;;
shared)
  die "remote encryption=shared stores a shared cipher in git; use hybrid"
  ;;
*)
  die "unsupported remote encryption mode: ${REMOTE_ENCRYPTION}"
  ;;
esac

if [[ "${REMOTE_ENCRYPTION}" != "none" && -z "${GPG_KEY}" ]]; then
  die "--gpg-key is required when remote encryption is ${REMOTE_ENCRYPTION}"
fi

if [[ "${NUMCOPIES}" -lt 2 ]]; then
  die "--numcopies must be at least 2"
fi

if [[ "${DRY_RUN}" == 0 ]]; then
  command -v git > /dev/null 2>&1 || die "git is required"
  command -v git-annex > /dev/null 2>&1 || command -v git-annex-shell > /dev/null 2>&1 || true
  git annex version > /dev/null 2>&1 || die "git-annex is required"
fi

run mkdir -p "${REPO_PATH}"
run mkdir -p "${REMOTE_PATH}"
run mkdir -p \
  "${REPO_PATH}/artifacts/netboot" \
  "${REPO_PATH}/artifacts/kernels" \
  "${REPO_PATH}/artifacts/doca" \
  "${REPO_PATH}/artifacts/binpkgs" \
  "${REPO_PATH}/artifacts/vm-images" \
  "${REPO_PATH}/artifacts/inference-models" \
  "${REPO_PATH}/artifacts/validation-runs" \
  "${REPO_PATH}/manifests" \
  "${REPO_PATH}/provenance"

run cd "${REPO_PATH}"

if [[ "${DRY_RUN}" == 0 ]]; then
  cd "${REPO_PATH}"
fi

if [[ "${DRY_RUN}" == 1 ]]; then
  printf '+ git init # if %s is not already a git repository\n' "${REPO_PATH}"
elif [[ ! -d .git ]]; then
  run git init
fi

printf '+ git annex init "%s"\n' "${ANNEX_DESCRIPTION}"
if [[ "${DRY_RUN}" == 0 ]]; then
  git annex init "${ANNEX_DESCRIPTION}"
fi

run git config annex.backend "${BACKEND}"
run git config annex.numcopies "${NUMCOPIES}"

if [[ "${DRY_RUN}" == 1 ]]; then
  printf '+ ensure .gitattributes contains "* annex.backend=%s"\n' "${BACKEND}"
else
  touch .gitattributes
  if ! grep -Fq -- "* annex.backend=${BACKEND}" .gitattributes; then
    printf '* annex.backend=%s\n' "${BACKEND}" >> .gitattributes
  fi
fi

remote_args=(
  git annex initremote "${REMOTE_NAME}"
  type=directory
  "directory=${REMOTE_PATH}"
  "encryption=${REMOTE_ENCRYPTION}"
)

if [[ "${REMOTE_ENCRYPTION}" != "none" ]]; then
  remote_args+=("keyid=${GPG_KEY}" "mac=${REMOTE_MAC}")
fi

run "${remote_args[@]}"

printf '[bootstrap-yukonsys-artifact-annex] repo=%s remote=%s backend=%s numcopies=%s encryption=%s mac=%s\n' \
  "${REPO_PATH}" "${REMOTE_NAME}" "${BACKEND}" "${NUMCOPIES}" "${REMOTE_ENCRYPTION}" "${REMOTE_MAC}"
