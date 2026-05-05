#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: publish-container-ghcr.sh --local-image IMAGE --image-name NAME [options]

Options:
  --local-image IMAGE      Existing local Podman image reference to publish
  --image-name NAME        Target image name under the namespace
  --tag TAG                Target tag (default: latest)
  --namespace NAME         GHCR namespace/owner (default: inferred from git remote)
  --registry HOST          Registry host (default: ghcr.io)
  --user USER              Registry username (default: GHCR_USER or namespace)
  --token-file PATH        File containing the registry token
  --source-url URL         OCI source URL hint for operator output
  --description TEXT       OCI description hint for operator output
  --print-target           Print resolved target and exit
  --dry-run                Render actions without invoking podman
  -h, --help               Show this help

Environment:
  GHCR_USER
  GHCR_TOKEN
  GHCR_TOKEN_FILE
EOF
}

log() {
  printf '[publish-container-ghcr] %s\n' "$*"
}

fail() {
  printf '[publish-container-ghcr] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" > /dev/null 2>&1 || fail "Required command not found: $1"
}

infer_namespace_from_git() {
  local origin owner
  origin="$(git config --get remote.origin.url 2> /dev/null || true)"
  case "${origin}" in
    git@github.com:*)
      owner="${origin#git@github.com:}"
      owner="${owner%%/*}"
      ;;
    https://github.com/*)
      owner="${origin#https://github.com/}"
      owner="${owner%%/*}"
      ;;
    *)
      owner=''
      ;;
  esac
  printf '%s' "${owner}"
}

LOCAL_IMAGE=''
IMAGE_NAME=''
IMAGE_TAG='latest'
GHCR_NAMESPACE="${GHCR_NAMESPACE:-}"
GHCR_REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
GHCR_USER="${GHCR_USER:-}"
GHCR_TOKEN="${GHCR_TOKEN:-}"
GHCR_TOKEN_FILE="${GHCR_TOKEN_FILE:-}"
OCI_SOURCE_URL=''
OCI_DESCRIPTION=''
PRINT_TARGET='0'
DRY_RUN='0'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-image)
      LOCAL_IMAGE="${2:-}"
      shift 2
      ;;
    --image-name)
      IMAGE_NAME="${2:-}"
      shift 2
      ;;
    --tag)
      IMAGE_TAG="${2:-}"
      shift 2
      ;;
    --namespace)
      GHCR_NAMESPACE="${2:-}"
      shift 2
      ;;
    --registry)
      GHCR_REGISTRY="${2:-}"
      shift 2
      ;;
    --user)
      GHCR_USER="${2:-}"
      shift 2
      ;;
    --token-file)
      GHCR_TOKEN_FILE="${2:-}"
      shift 2
      ;;
    --source-url)
      OCI_SOURCE_URL="${2:-}"
      shift 2
      ;;
    --description)
      OCI_DESCRIPTION="${2:-}"
      shift 2
      ;;
    --print-target)
      PRINT_TARGET='1'
      shift
      ;;
    --dry-run)
      DRY_RUN='1'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${LOCAL_IMAGE}" ]] || fail '--local-image is required'
[[ -n "${IMAGE_NAME}" ]] || fail '--image-name is required'

if [[ -z "${GHCR_NAMESPACE}" ]]; then
  GHCR_NAMESPACE="$(infer_namespace_from_git)"
fi
[[ -n "${GHCR_NAMESPACE}" ]] || fail 'Could not infer GHCR namespace; use --namespace'

if [[ -z "${GHCR_USER}" ]]; then
  GHCR_USER="${GHCR_NAMESPACE}"
fi

TARGET_REF="${GHCR_REGISTRY}/${GHCR_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

if [[ "${PRINT_TARGET}" == '1' ]]; then
  printf '%s\n' "${TARGET_REF}"
  exit 0
fi

if [[ -z "${GHCR_TOKEN}" && -n "${GHCR_TOKEN_FILE}" ]]; then
  [[ -f "${GHCR_TOKEN_FILE}" ]] || fail "Token file not found: ${GHCR_TOKEN_FILE}"
  GHCR_TOKEN="$(<"${GHCR_TOKEN_FILE}")"
fi

if [[ "${DRY_RUN}" == '1' ]]; then
  log "local-image=${LOCAL_IMAGE}"
  log "target-ref=${TARGET_REF}"
  [[ -n "${OCI_SOURCE_URL}" ]] && log "source-url=${OCI_SOURCE_URL}"
  [[ -n "${OCI_DESCRIPTION}" ]] && log "description=${OCI_DESCRIPTION}"
  exit 0
fi

require_cmd podman
podman image exists "${LOCAL_IMAGE}" || fail "Local image not found: ${LOCAL_IMAGE}"
[[ -n "${GHCR_TOKEN}" ]] || fail 'GHCR token is required via GHCR_TOKEN or --token-file'

log "Logging into ${GHCR_REGISTRY} as ${GHCR_USER}"
printf '%s' "${GHCR_TOKEN}" | podman login "${GHCR_REGISTRY}" -u "${GHCR_USER}" --password-stdin > /dev/null

log "Tagging ${LOCAL_IMAGE} as ${TARGET_REF}"
podman tag "${LOCAL_IMAGE}" "${TARGET_REF}"

digest_file="$(mktemp)"
trap 'rm -f "${digest_file}"' EXIT

log "Pushing ${TARGET_REF}"
podman push --digestfile "${digest_file}" "${TARGET_REF}"

log "Published ${TARGET_REF}"
if [[ -s "${digest_file}" ]]; then
  log "Digest: $(<"${digest_file}")"
fi
[[ -n "${OCI_SOURCE_URL}" ]] && log "Source URL: ${OCI_SOURCE_URL}"
[[ -n "${OCI_DESCRIPTION}" ]] && log "Description: ${OCI_DESCRIPTION}"
