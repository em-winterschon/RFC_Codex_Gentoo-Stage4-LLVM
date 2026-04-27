#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-gentoo-rootfs-container.sh --root DIR --package-list FILE [options]

Build a Gentoo rootfs with emerge --root, optionally archive it, and optionally
import or commit it into a local container image.

Options:
  --root DIR               Target rootfs directory to populate.
  --package-list FILE      Flat package list file (one atom per line).
  --config-root DIR        Portage config root (default: /).
  --image-ref REF          Local image reference to create.
  --engine MODE            auto, buildah, podman-import, none (default: auto).
  --tarball PATH           Create a rootfs tarball at PATH.
  --source-url URL         OCI source label.
  --description TEXT       OCI description label.
  --default-cmd CMD        Default container command (default: /bin/bash).
  --dry-run                Print the resolved plan and exit.
  --help                   Show this message.
EOF
}

log() {
  printf '[build-gentoo-rootfs-container] %s\n' "$*"
}

die() {
  printf '[build-gentoo-rootfs-container] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

ROOT_DIR=
PACKAGE_LIST=
CONFIG_ROOT=/
IMAGE_REF=
ENGINE=auto
TARBALL=
SOURCE_URL=
DESCRIPTION=
DEFAULT_CMD=/bin/bash
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR=${2-}
      shift 2
      ;;
    --package-list)
      PACKAGE_LIST=${2-}
      shift 2
      ;;
    --config-root)
      CONFIG_ROOT=${2-}
      shift 2
      ;;
    --image-ref)
      IMAGE_REF=${2-}
      shift 2
      ;;
    --engine)
      ENGINE=${2-}
      shift 2
      ;;
    --tarball)
      TARBALL=${2-}
      shift 2
      ;;
    --source-url)
      SOURCE_URL=${2-}
      shift 2
      ;;
    --description)
      DESCRIPTION=${2-}
      shift 2
      ;;
    --default-cmd)
      DEFAULT_CMD=${2-}
      shift 2
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

[[ -n "${ROOT_DIR}" ]] || die "--root is required"
[[ -n "${PACKAGE_LIST}" ]] || die "--package-list is required"
[[ -f "${PACKAGE_LIST}" ]] || die "package list not found: ${PACKAGE_LIST}"
[[ "${ENGINE}" =~ ^(auto|buildah|podman-import|none)$ ]] || die "unsupported engine: ${ENGINE}"
if [[ "${ENGINE}" != "none" ]]; then
  [[ -n "${IMAGE_REF}" ]] || die "--image-ref is required unless --engine none is used"
fi

mapfile -t PACKAGE_ATOMS < <(grep -Ev '^[[:space:]]*($|#)' "${PACKAGE_LIST}")
[[ ${#PACKAGE_ATOMS[@]} -gt 0 ]] || die "package list is empty: ${PACKAGE_LIST}"

RESOLVED_ENGINE=${ENGINE}
if [[ "${RESOLVED_ENGINE}" == "auto" ]]; then
  if command -v buildah >/dev/null 2>&1; then
    RESOLVED_ENGINE=buildah
  elif command -v podman >/dev/null 2>&1; then
    RESOLVED_ENGINE=podman-import
  else
    die "no container engine available; install buildah or podman"
  fi
fi

if [[ "${DRY_RUN}" == true ]]; then
  printf 'root=%s\n' "${ROOT_DIR}"
  printf 'config-root=%s\n' "${CONFIG_ROOT}"
  printf 'package-list=%s\n' "${PACKAGE_LIST}"
  printf 'package-count=%s\n' "${#PACKAGE_ATOMS[@]}"
  printf 'engine=%s\n' "${RESOLVED_ENGINE}"
  printf 'image-ref=%s\n' "${IMAGE_REF}"
  printf 'tarball=%s\n' "${TARBALL}"
  exit 0
fi

require_cmd emerge
require_cmd install

mkdir -p "${ROOT_DIR}"
install -d -m 0755 \
  "${ROOT_DIR}/etc" \
  "${ROOT_DIR}/proc" \
  "${ROOT_DIR}/sys" \
  "${ROOT_DIR}/dev" \
  "${ROOT_DIR}/run" \
  "${ROOT_DIR}/tmp" \
  "${ROOT_DIR}/var/tmp"
chmod 1777 "${ROOT_DIR}/tmp" "${ROOT_DIR}/var/tmp"

log "building rootfs in ${ROOT_DIR}"
emerge \
  --verbose \
  --oneshot \
  --emptytree \
  --root="${ROOT_DIR}" \
  --config-root="${CONFIG_ROOT}" \
  "${PACKAGE_ATOMS[@]}"

if [[ -n "${TARBALL}" ]]; then
  require_cmd tar
  require_cmd zstd
  mkdir -p "$(dirname "${TARBALL}")"
  log "creating rootfs tarball ${TARBALL}"
  tar \
    --xattrs \
    --acls \
    --numeric-owner \
    -C "${ROOT_DIR}" \
    -I 'zstd -2 --rsyncable --auto-threads=physical --exclude-compressed' \
    -cf "${TARBALL}" .
fi

case "${RESOLVED_ENGINE}" in
  none)
    ;;
  buildah)
    require_cmd buildah
    log "committing rootfs into ${IMAGE_REF} with buildah"
    container_id="$(buildah from scratch)"
    cleanup_buildah() {
      buildah rm "${container_id}" >/dev/null 2>&1 || true
    }
    trap cleanup_buildah EXIT
    buildah add "${container_id}" "${ROOT_DIR}" /
    buildah config --cmd "[\"${DEFAULT_CMD}\"]" "${container_id}"
    [[ -n "${SOURCE_URL}" ]] && buildah config --label "org.opencontainers.image.source=${SOURCE_URL}" "${container_id}"
    [[ -n "${DESCRIPTION}" ]] && buildah config --label "org.opencontainers.image.description=${DESCRIPTION}" "${container_id}"
    buildah commit "${container_id}" "${IMAGE_REF}" >/dev/null
    trap - EXIT
    cleanup_buildah
    ;;
  podman-import)
    require_cmd podman
    require_cmd tar
    log "importing rootfs into ${IMAGE_REF} with podman"
    import_args=()
    [[ -n "${SOURCE_URL}" ]] && import_args+=(--change "LABEL org.opencontainers.image.source=${SOURCE_URL}")
    [[ -n "${DESCRIPTION}" ]] && import_args+=(--change "LABEL org.opencontainers.image.description=${DESCRIPTION}")
    import_args+=(--change "CMD [\"${DEFAULT_CMD}\"]")
    tar -C "${ROOT_DIR}" -cf - . | podman import "${import_args[@]}" - "${IMAGE_REF}" >/dev/null
    ;;
esac

log "completed rootfs build"
