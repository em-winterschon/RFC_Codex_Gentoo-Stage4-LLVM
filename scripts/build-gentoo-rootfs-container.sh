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
  --use-file FILE          Flat USE override file (one flag token per line).
  --package-use-file FILE  package.use style overrides to install into config-root.
  --host-package-mask-file FILE
                           package.mask style overrides to install into the build host.
  --overlay-dir DIR        Optional Portage overlay repo root to expose in config-root.
  --config-root DIR        Portage config root (default: /).
  --sysroot DIR            Portage sysroot for DEPEND handling (default: /).
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

sanitize_emerge_features() {
  local raw sanitized
  raw="${FEATURES:-}"
  if [[ -z "${raw}" ]]; then
    printf '%s' ""
    return 0
  fi

  sanitized="$(
    printf '%s\n' "${raw}" \
      | tr ' ' '\n' \
      | grep -Ev '^(distcc|ccache)$' \
      | awk 'NF' \
      | paste -sd' ' -
  )"
  printf '%s' "${sanitized}"
}

ROOT_DIR=
PACKAGE_LIST=
USE_FILE=
PACKAGE_USE_FILE=
HOST_PACKAGE_MASK_FILE=
OVERLAY_DIR=
OVERLAY_REPO_NAME=
STAGED_OVERLAY_DIR=
CONFIG_ROOT=/
SYSROOT=/
IMAGE_REF=
ENGINE=auto
TARBALL=
SOURCE_URL=
DESCRIPTION=
DEFAULT_CMD=/bin/bash
DRY_RUN=false
SANITIZED_FEATURES=
USE_OVERRIDE_FLAGS=()

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
    --use-file)
      USE_FILE=${2-}
      shift 2
      ;;
    --package-use-file)
      PACKAGE_USE_FILE=${2-}
      shift 2
      ;;
    --host-package-mask-file)
      HOST_PACKAGE_MASK_FILE=${2-}
      shift 2
      ;;
    --overlay-dir)
      OVERLAY_DIR=${2-}
      shift 2
      ;;
    --config-root)
      CONFIG_ROOT=${2-}
      shift 2
      ;;
    --sysroot)
      SYSROOT=${2-}
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
if [[ -n "${USE_FILE}" ]]; then
  [[ -f "${USE_FILE}" ]] || die "use override file not found: ${USE_FILE}"
fi
if [[ -n "${PACKAGE_USE_FILE}" ]]; then
  [[ -f "${PACKAGE_USE_FILE}" ]] || die "package.use override file not found: ${PACKAGE_USE_FILE}"
  [[ "${CONFIG_ROOT}" != "/" ]] || die "--package-use-file requires an explicit non-/ --config-root"
fi
if [[ -n "${HOST_PACKAGE_MASK_FILE}" ]]; then
  [[ -f "${HOST_PACKAGE_MASK_FILE}" ]] || die "host package.mask file not found: ${HOST_PACKAGE_MASK_FILE}"
fi
if [[ -n "${OVERLAY_DIR}" ]]; then
  [[ -d "${OVERLAY_DIR}" ]] || die "overlay dir not found: ${OVERLAY_DIR}"
  [[ -f "${OVERLAY_DIR}/profiles/repo_name" ]] || die "overlay dir missing profiles/repo_name: ${OVERLAY_DIR}"
  [[ "${CONFIG_ROOT}" != "/" ]] || die "--overlay-dir requires an explicit non-/ --config-root"
  OVERLAY_REPO_NAME="$(<"${OVERLAY_DIR}/profiles/repo_name")"
  [[ -n "${OVERLAY_REPO_NAME}" ]] || die "overlay repo_name is empty: ${OVERLAY_DIR}"
  STAGED_OVERLAY_DIR="/var/tmp/build-gentoo-rootfs-container/overlays/${OVERLAY_REPO_NAME}"
fi
[[ "${ENGINE}" =~ ^(auto|buildah|podman-import|none)$ ]] || die "unsupported engine: ${ENGINE}"
if [[ "${ENGINE}" != "none" ]]; then
  [[ -n "${IMAGE_REF}" ]] || die "--image-ref is required unless --engine none is used"
fi

mapfile -t PACKAGE_ATOMS < <(grep -Ev '^[[:space:]]*($|#)' "${PACKAGE_LIST}")
[[ ${#PACKAGE_ATOMS[@]} -gt 0 ]] || die "package list is empty: ${PACKAGE_LIST}"
if [[ -n "${USE_FILE}" ]]; then
  mapfile -t USE_OVERRIDE_FLAGS < <(grep -Ev '^[[:space:]]*($|#)' "${USE_FILE}")
fi
SANITIZED_FEATURES="$(sanitize_emerge_features)"

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
  printf 'sysroot=%s\n' "${SYSROOT}"
  printf 'package-list=%s\n' "${PACKAGE_LIST}"
  printf 'use-file=%s\n' "${USE_FILE}"
  printf 'package-use-file=%s\n' "${PACKAGE_USE_FILE}"
  printf 'host-package-mask-file=%s\n' "${HOST_PACKAGE_MASK_FILE}"
  printf 'overlay-dir=%s\n' "${OVERLAY_DIR}"
  printf 'overlay-repo-name=%s\n' "${OVERLAY_REPO_NAME}"
  printf 'staged-overlay-dir=%s\n' "${STAGED_OVERLAY_DIR}"
  printf 'package-count=%s\n' "${#PACKAGE_ATOMS[@]}"
  printf 'use-overrides=%s\n' "${USE_OVERRIDE_FLAGS[*]:-}"
  printf 'engine=%s\n' "${RESOLVED_ENGINE}"
  printf 'image-ref=%s\n' "${IMAGE_REF}"
  printf 'tarball=%s\n' "${TARBALL}"
  printf 'sanitized-features=%s\n' "${SANITIZED_FEATURES}"
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

if [[ -n "${PACKAGE_USE_FILE}" ]]; then
  install -d -m 0755 "${CONFIG_ROOT}/etc/portage/package.use"
  install -m 0644 "${PACKAGE_USE_FILE}" \
    "${CONFIG_ROOT}/etc/portage/package.use/99-build-gentoo-rootfs-container"
fi
if [[ -n "${HOST_PACKAGE_MASK_FILE}" ]]; then
  install -d -m 0755 /etc/portage/package.mask
  install -m 0644 "${HOST_PACKAGE_MASK_FILE}" \
    /etc/portage/package.mask/99-build-gentoo-rootfs-container
fi
if [[ -n "${OVERLAY_DIR}" ]]; then
  install -d -m 0755 \
    /etc/portage/repos.conf \
    /var/db/repos \
    "$(dirname "${STAGED_OVERLAY_DIR}")" \
    "${CONFIG_ROOT}/etc/portage/repos.conf" \
    "${CONFIG_ROOT}/var/db/repos"
  rm -rf "${STAGED_OVERLAY_DIR}"
  cp -a "${OVERLAY_DIR}" "${STAGED_OVERLAY_DIR}"
  find "${STAGED_OVERLAY_DIR}" -type d -exec chmod 755 {} +
  find "${STAGED_OVERLAY_DIR}" -type f -exec chmod 644 {} +
  ln -snf "${STAGED_OVERLAY_DIR}" "/var/db/repos/${OVERLAY_REPO_NAME}"
  ln -snf "${STAGED_OVERLAY_DIR}" "${CONFIG_ROOT}/var/db/repos/${OVERLAY_REPO_NAME}"
  cat > "/etc/portage/repos.conf/zz-build-gentoo-rootfs-container-${OVERLAY_REPO_NAME}.conf" <<EOF
[${OVERLAY_REPO_NAME}]
location = ${STAGED_OVERLAY_DIR}
masters = gentoo
auto-sync = no
priority = 9999
EOF
  cat > "${CONFIG_ROOT}/etc/portage/repos.conf/zz-build-gentoo-rootfs-container-${OVERLAY_REPO_NAME}.conf" <<EOF
[${OVERLAY_REPO_NAME}]
location = ${STAGED_OVERLAY_DIR}
masters = gentoo
auto-sync = no
priority = 9999
EOF
fi

log "building rootfs in ${ROOT_DIR}"
emerge_env=(
  "CCACHE_DISABLE=1"
  "DISTCC_DISABLE=1"
)
if [[ -n "${SANITIZED_FEATURES}" ]]; then
  emerge_env+=("FEATURES=${SANITIZED_FEATURES}")
fi
if [[ ${#USE_OVERRIDE_FLAGS[@]} -gt 0 ]]; then
  current_use="${USE:-}"
  current_use="${current_use:+${current_use} }${USE_OVERRIDE_FLAGS[*]}"
  emerge_env+=("USE=${current_use}")
fi

env "${emerge_env[@]}" \
  emerge \
    --verbose \
    --oneshot \
    --emptytree \
    --root="${ROOT_DIR}" \
    --config-root="${CONFIG_ROOT}" \
    --sysroot="${SYSROOT}" \
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
