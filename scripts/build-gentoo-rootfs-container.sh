#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: build-gentoo-rootfs-container.sh --root DIR --package-list FILE [options]

Build a Gentoo rootfs with emerge --root, optionally archive it, and optionally
import or commit it into a local container image.

Options:
  --root DIR               Target rootfs directory to populate.
  --package-list FILE      Flat package list file (one atom per line).
  --bootstrap-package-list FILE
                           Flat package list to emerge before the main graph.
                           Used for compiler/runtime sysroot prerequisites.
  --bootstrap-runtime-seed MODE
                           Seed compiler runtime libraries before the main graph.
                           Modes: none, auto (default: none).
  --stage3-target TARGET   Extract the latest Gentoo stage3 before package layering.
                           Supported: amd64-llvm-openrc, arm64-llvm-openrc,
                           power9le-openrc.
  --stage3-tarball FILE    Extract this local stage3 tarball instead of resolving
                           latest-stage3 metadata.
  --stage3-cache-dir DIR   Stage3 download cache directory.
  --stage3-mirror-root URL Gentoo releases mirror root.
  --stage3-verify-checksum MODE
                           Verify downloaded stage3 tarballs. Modes: true, false.
  --main-emptytree MODE    Whether main package layering uses --emptytree.
                           Modes: auto, true, false. Auto is false for stage3.
  --reset-rootfs           Remove existing rootfs contents before building.
  --pkgdir DIR             Local binpkg cache directory (default: sibling binpkgs/).
  --binpkg-repo-id ID      Unique Stage4/Stage5 binpkg repository ID.
  --binpkg-sync-remote HOST
                           Optional rsync/ssh destination host for binpkg sync.
  --binpkg-sync-root DIR   Remote repository root (default: /srv/stage5-binpkgs).
  --profile-parent PARENT  Profile parent for generated config-root profile.
                           May be repeated. Defaults to merged-usr Stage4 parents.
  --use-file FILE          Flat USE override file (one flag token per line).
  --package-use-file FILE  package.use style overrides to install into config-root.
  --host-package-use-file FILE
                           package.use style overrides to install into the build host.
  --host-package-mask-file FILE
                           package.mask style overrides to install into the build host.
  --rootfs-links-file FILE
                           Symlink manifest to materialize inside the rootfs before emerge.
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
      | grep -Ev '^-?(distcc|ccache)$' \
      | awk 'NF' \
      | paste -sd' ' -
  )"
  printf '%s' "${sanitized}"
}

ROOT_DIR=
PACKAGE_LIST=
BOOTSTRAP_PACKAGE_LIST=
BOOTSTRAP_RUNTIME_SEED=none
STAGE3_TARGET=
STAGE3_MIRROR_ROOT=https://distfiles.gentoo.org/releases
STAGE3_CACHE_DIR=
STAGE3_TARBALL=
STAGE3_VERIFY_CHECKSUM=true
STAGE3_RELEASE_ARCH=
STAGE3_CURRENT_DIR=
STAGE3_LATEST_TXT=
STAGE3_LATEST_URL=
STAGE3_TARBALL_NAME=
STAGE3_TARBALL_URL=
STAGE3_SHA256_URL=
STAGE3_SHA256_PATH=
MAIN_EMPTYTREE=auto
RESET_ROOTFS=false
PKGDIR=
BINPKG_REPO_ID=
BINPKG_SYNC_REMOTE=
BINPKG_SYNC_ROOT=/srv/stage5-binpkgs
PROFILE_OVERLAY_NAME=local-container-image-profile
PROFILE_NAME=stage4-container-image
USE_FILE=
PACKAGE_USE_FILE=
HOST_PACKAGE_USE_FILE=
HOST_PACKAGE_MASK_FILE=
ROOTFS_LINKS_FILE=
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
BUILDAH_CONTAINER_ID=
USE_OVERRIDE_FLAGS=()
PROFILE_PARENTS=()
HOST_PACKAGE_USE_DEST=/etc/portage/package.use/99-build-gentoo-rootfs-container-host
HOST_PACKAGE_MASK_DEST=/etc/portage/package.mask/99-build-gentoo-rootfs-container

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
    --bootstrap-package-list)
      BOOTSTRAP_PACKAGE_LIST=${2-}
      shift 2
      ;;
    --bootstrap-runtime-seed)
      BOOTSTRAP_RUNTIME_SEED=${2-}
      shift 2
      ;;
    --stage3-target)
      STAGE3_TARGET=${2-}
      shift 2
      ;;
    --stage3-tarball)
      STAGE3_TARBALL=${2-}
      shift 2
      ;;
    --stage3-cache-dir)
      STAGE3_CACHE_DIR=${2-}
      shift 2
      ;;
    --stage3-mirror-root)
      STAGE3_MIRROR_ROOT=${2-}
      shift 2
      ;;
    --stage3-verify-checksum)
      STAGE3_VERIFY_CHECKSUM=${2-}
      shift 2
      ;;
    --main-emptytree)
      MAIN_EMPTYTREE=${2-}
      shift 2
      ;;
    --reset-rootfs)
      RESET_ROOTFS=true
      shift
      ;;
    --pkgdir)
      PKGDIR=${2-}
      shift 2
      ;;
    --binpkg-repo-id)
      BINPKG_REPO_ID=${2-}
      shift 2
      ;;
    --binpkg-sync-remote)
      BINPKG_SYNC_REMOTE=${2-}
      shift 2
      ;;
    --binpkg-sync-root)
      BINPKG_SYNC_ROOT=${2-}
      shift 2
      ;;
    --profile-parent)
      PROFILE_PARENTS+=("${2-}")
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
    --host-package-use-file)
      HOST_PACKAGE_USE_FILE=${2-}
      shift 2
      ;;
    --host-package-mask-file)
      HOST_PACKAGE_MASK_FILE=${2-}
      shift 2
      ;;
    --rootfs-links-file)
      ROOTFS_LINKS_FILE=${2-}
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
if [[ -n "${BOOTSTRAP_PACKAGE_LIST}" ]]; then
  [[ -f "${BOOTSTRAP_PACKAGE_LIST}" ]] || die "bootstrap package list not found: ${BOOTSTRAP_PACKAGE_LIST}"
fi
if [[ -z "${PKGDIR}" ]]; then
  PKGDIR="$(dirname "${ROOT_DIR%/}")/binpkgs"
fi
if [[ -z "${STAGE3_CACHE_DIR}" ]]; then
  STAGE3_CACHE_DIR="$(dirname "${ROOT_DIR%/}")/stage3-cache"
fi
if [[ -n "${BINPKG_SYNC_REMOTE}" && -z "${BINPKG_REPO_ID}" ]]; then
  die "--binpkg-sync-remote requires --binpkg-repo-id"
fi
if [[ -n "${USE_FILE}" ]]; then
  [[ -f "${USE_FILE}" ]] || die "use override file not found: ${USE_FILE}"
fi
if [[ -n "${PACKAGE_USE_FILE}" ]]; then
  [[ -f "${PACKAGE_USE_FILE}" ]] || die "package.use override file not found: ${PACKAGE_USE_FILE}"
  [[ "${CONFIG_ROOT}" != "/" ]] || die "--package-use-file requires an explicit non-/ --config-root"
fi
if [[ -n "${HOST_PACKAGE_USE_FILE}" ]]; then
  [[ -f "${HOST_PACKAGE_USE_FILE}" ]] || die "host package.use file not found: ${HOST_PACKAGE_USE_FILE}"
fi
if [[ -n "${HOST_PACKAGE_MASK_FILE}" ]]; then
  [[ -f "${HOST_PACKAGE_MASK_FILE}" ]] || die "host package.mask file not found: ${HOST_PACKAGE_MASK_FILE}"
fi
if [[ -n "${ROOTFS_LINKS_FILE}" ]]; then
  [[ -f "${ROOTFS_LINKS_FILE}" ]] || die "rootfs link manifest not found: ${ROOTFS_LINKS_FILE}"
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
[[ "${BOOTSTRAP_RUNTIME_SEED}" =~ ^(none|auto)$ ]] || die "unsupported bootstrap runtime seed mode: ${BOOTSTRAP_RUNTIME_SEED}"
[[ "${STAGE3_VERIFY_CHECKSUM}" =~ ^(true|false)$ ]] || die "unsupported stage3 checksum mode: ${STAGE3_VERIFY_CHECKSUM}"
[[ "${MAIN_EMPTYTREE}" =~ ^(auto|true|false)$ ]] || die "unsupported main emptytree mode: ${MAIN_EMPTYTREE}"
if [[ -n "${STAGE3_TARBALL}" ]]; then
  [[ -f "${STAGE3_TARBALL}" ]] || die "stage3 tarball not found: ${STAGE3_TARBALL}"
fi
if [[ "${ENGINE}" != "none" ]]; then
  [[ -n "${IMAGE_REF}" ]] || die "--image-ref is required unless --engine none is used"
fi

mapfile -t PACKAGE_ATOMS < <(grep -Ev '^[[:space:]]*($|#)' "${PACKAGE_LIST}")
[[ ${#PACKAGE_ATOMS[@]} -gt 0 ]] || die "package list is empty: ${PACKAGE_LIST}"
BOOTSTRAP_PACKAGE_ATOMS=()
if [[ -n "${BOOTSTRAP_PACKAGE_LIST}" ]]; then
  mapfile -t BOOTSTRAP_PACKAGE_ATOMS < <(grep -Ev '^[[:space:]]*($|#)' "${BOOTSTRAP_PACKAGE_LIST}")
fi
if [[ -n "${USE_FILE}" ]]; then
  mapfile -t USE_OVERRIDE_FLAGS < <(grep -Ev '^[[:space:]]*($|#)' "${USE_FILE}")
fi
supported_stage3_targets() {
  printf '%s\n' 'amd64-llvm-openrc arm64-llvm-openrc power9le-openrc'
}

resolve_stage3_target() {
  case "${STAGE3_TARGET}" in
    amd64-llvm-openrc)
      STAGE3_RELEASE_ARCH=amd64
      STAGE3_CURRENT_DIR=current-stage3-amd64-llvm-openrc
      STAGE3_LATEST_TXT=latest-stage3-amd64-llvm-openrc.txt
      ;;
    arm64-llvm-openrc)
      STAGE3_RELEASE_ARCH=arm64
      STAGE3_CURRENT_DIR=current-stage3-arm64-llvm-openrc
      STAGE3_LATEST_TXT=latest-stage3-arm64-llvm-openrc.txt
      ;;
    power9le-openrc)
      STAGE3_RELEASE_ARCH=ppc
      STAGE3_CURRENT_DIR=current-stage3-power9le-openrc
      STAGE3_LATEST_TXT=latest-stage3-power9le-openrc.txt
      ;;
    *)
      die "unsupported stage3 target: ${STAGE3_TARGET} (supported: $(supported_stage3_targets))"
      ;;
  esac

  STAGE3_LATEST_URL="${STAGE3_MIRROR_ROOT}/${STAGE3_RELEASE_ARCH}/autobuilds/${STAGE3_CURRENT_DIR}/${STAGE3_LATEST_TXT}"
}

if [[ -n "${STAGE3_TARGET}" ]]; then
  resolve_stage3_target
fi
if [[ "${MAIN_EMPTYTREE}" == auto ]]; then
  if [[ -n "${STAGE3_TARGET}" || -n "${STAGE3_TARBALL}" ]]; then
    MAIN_EMPTYTREE=false
  else
    MAIN_EMPTYTREE=true
  fi
fi

if [[ ${#PROFILE_PARENTS[@]} -eq 0 && -z "${STAGE3_TARGET}" && -z "${STAGE3_TARBALL}" ]]; then
  PROFILE_PARENTS=(
    gentoo:default/linux/amd64/23.0/llvm
    gentoo:default/linux/amd64/23.0/no-multilib/hardened
  )
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
  printf 'bootstrap-package-list=%s\n' "${BOOTSTRAP_PACKAGE_LIST}"
  printf 'bootstrap-runtime-seed=%s\n' "${BOOTSTRAP_RUNTIME_SEED}"
  printf 'stage3-target=%s\n' "${STAGE3_TARGET}"
  printf 'stage3-release-arch=%s\n' "${STAGE3_RELEASE_ARCH}"
  printf 'stage3-current-dir=%s\n' "${STAGE3_CURRENT_DIR}"
  printf 'stage3-latest-url=%s\n' "${STAGE3_LATEST_URL}"
  printf 'stage3-tarball=%s\n' "${STAGE3_TARBALL}"
  printf 'stage3-cache-dir=%s\n' "${STAGE3_CACHE_DIR}"
  printf 'stage3-verify-checksum=%s\n' "${STAGE3_VERIFY_CHECKSUM}"
  printf 'main-emptytree=%s\n' "${MAIN_EMPTYTREE}"
  printf 'reset-rootfs=%s\n' "${RESET_ROOTFS}"
  printf 'pkgdir=%s\n' "${PKGDIR}"
  printf 'binpkg-repo-id=%s\n' "${BINPKG_REPO_ID}"
  printf 'binpkg-sync-remote=%s\n' "${BINPKG_SYNC_REMOTE}"
  printf 'binpkg-sync-root=%s\n' "${BINPKG_SYNC_ROOT}"
  printf 'profile-parents=%s\n' "${PROFILE_PARENTS[*]}"
  printf 'use-file=%s\n' "${USE_FILE}"
  printf 'package-use-file=%s\n' "${PACKAGE_USE_FILE}"
  printf 'host-package-use-file=%s\n' "${HOST_PACKAGE_USE_FILE}"
  printf 'host-package-mask-file=%s\n' "${HOST_PACKAGE_MASK_FILE}"
  printf 'rootfs-links-file=%s\n' "${ROOTFS_LINKS_FILE}"
  printf 'overlay-dir=%s\n' "${OVERLAY_DIR}"
  printf 'overlay-repo-name=%s\n' "${OVERLAY_REPO_NAME}"
  printf 'staged-overlay-dir=%s\n' "${STAGED_OVERLAY_DIR}"
  printf 'package-count=%s\n' "${#PACKAGE_ATOMS[@]}"
  printf 'bootstrap-package-count=%s\n' "${#BOOTSTRAP_PACKAGE_ATOMS[@]}"
  printf 'use-overrides=%s\n' "${USE_OVERRIDE_FLAGS[*]:-}"
  printf 'engine=%s\n' "${RESOLVED_ENGINE}"
  printf 'image-ref=%s\n' "${IMAGE_REF}"
  printf 'tarball=%s\n' "${TARBALL}"
  printf 'sanitized-features=%s\n' "${SANITIZED_FEATURES}"
  exit 0
fi

require_cmd emerge
require_cmd install

find_fetch_tool() {
  if command -v curl >/dev/null 2>&1; then
    printf 'curl'
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    printf 'wget'
    return 0
  fi
  die "missing required command: curl or wget"
}

download_file() {
  local url=$1
  local destination=$2
  local fetch_tool
  fetch_tool="$(find_fetch_tool)"
  case "${fetch_tool}" in
    curl)
      curl -fL --retry 5 --retry-delay 2 -o "${destination}" "${url}"
      ;;
    wget)
      wget -O "${destination}" "${url}"
      ;;
  esac
}

download_stdout() {
  local url=$1
  local fetch_tool
  fetch_tool="$(find_fetch_tool)"
  case "${fetch_tool}" in
    curl)
      curl -fsSL --retry 5 --retry-delay 2 "${url}"
      ;;
    wget)
      wget -qO- "${url}"
      ;;
  esac
}

reset_rootfs_contents() {
  [[ "${ROOT_DIR}" != "/" ]] || die "--reset-rootfs cannot target /"
  [[ -n "${ROOT_DIR}" ]] || die "--reset-rootfs requires --root"
  if [[ -d "${ROOT_DIR}" ]]; then
    log "resetting rootfs contents in ${ROOT_DIR}"
    find "${ROOT_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
}

resolve_latest_stage3_tarball() {
  local info_text
  [[ -n "${STAGE3_TARGET}" ]] || return 0
  install -d -m 0755 "${STAGE3_CACHE_DIR}"
  log "resolving latest stage3 metadata from ${STAGE3_LATEST_URL}"
  info_text="$(download_stdout "${STAGE3_LATEST_URL}")"
  STAGE3_TARBALL_NAME="$(printf '%s\n' "${info_text}" | grep -Eo 'stage3-[^[:space:]]+\.tar\.xz' | head -n1 || true)"
  [[ -n "${STAGE3_TARBALL_NAME}" ]] || die "unable to parse stage3 tarball from ${STAGE3_LATEST_URL}"
  STAGE3_TARBALL_URL="${STAGE3_MIRROR_ROOT}/${STAGE3_RELEASE_ARCH}/autobuilds/${STAGE3_CURRENT_DIR}/${STAGE3_TARBALL_NAME}"
  STAGE3_SHA256_URL="${STAGE3_TARBALL_URL}.sha256"
  STAGE3_TARBALL="${STAGE3_CACHE_DIR}/${STAGE3_TARBALL_NAME}"
  STAGE3_SHA256_PATH="${STAGE3_TARBALL}.sha256"
}

verify_stage3_tarball() {
  local tarball_name sha256
  [[ "${STAGE3_VERIFY_CHECKSUM}" == true ]] || return 0
  [[ -n "${STAGE3_SHA256_URL}" ]] || return 0
  require_cmd sha256sum

  tarball_name="$(basename "${STAGE3_TARBALL}")"
  log "downloading stage3 checksum ${STAGE3_SHA256_URL}"
  download_file "${STAGE3_SHA256_URL}" "${STAGE3_SHA256_PATH}"
  sha256="$(grep -E "^[A-Fa-f0-9]{64}[[:space:]]+${tarball_name}$" "${STAGE3_SHA256_PATH}" | awk '{print $1}' | head -n1 || true)"
  [[ -n "${sha256}" ]] || die "unable to parse SHA256 for ${tarball_name} from ${STAGE3_SHA256_PATH}"
  (cd "$(dirname "${STAGE3_TARBALL}")" && printf '%s  %s\n' "${sha256}" "${tarball_name}" | sha256sum -c -)
}

prepare_stage3_tarball() {
  if [[ -z "${STAGE3_TARGET}" && -z "${STAGE3_TARBALL}" ]]; then
    return 0
  fi
  if [[ -z "${STAGE3_TARBALL}" ]]; then
    resolve_latest_stage3_tarball
  fi
  [[ -f "${STAGE3_TARBALL}" ]] || {
    [[ -n "${STAGE3_TARBALL_URL}" ]] || die "stage3 tarball path does not exist and no URL was resolved: ${STAGE3_TARBALL}"
    log "downloading stage3 tarball ${STAGE3_TARBALL_URL}"
    download_file "${STAGE3_TARBALL_URL}" "${STAGE3_TARBALL}"
  }
  verify_stage3_tarball
}

rootfs_has_stage3() {
  [[ -f "${ROOT_DIR}/etc/gentoo-release" ]]
}

extract_stage3_rootfs() {
  [[ -n "${STAGE3_TARGET}" || -n "${STAGE3_TARBALL}" ]] || return 0
  require_cmd tar
  if rootfs_has_stage3; then
    log "existing Gentoo rootfs detected in ${ROOT_DIR}; skipping stage3 extraction"
    return 0
  fi
  if find "${ROOT_DIR}" -mindepth 1 -maxdepth 1 | grep -q .; then
    die "rootfs is not empty and does not look like a Gentoo stage3: ${ROOT_DIR}; use --reset-rootfs"
  fi
  log "extracting stage3 tarball ${STAGE3_TARBALL} into ${ROOT_DIR}"
  tar xpf "${STAGE3_TARBALL}" --xattrs-include='*.*' --numeric-owner -C "${ROOT_DIR}"
}

cleanup_rootfs_builder() {
  if [[ -n "${BUILDAH_CONTAINER_ID}" ]]; then
    buildah rm "${BUILDAH_CONTAINER_ID}" >/dev/null 2>&1 || true
  fi
  rm -f "${HOST_PACKAGE_USE_DEST}" "${HOST_PACKAGE_MASK_DEST}"
  if [[ "${CONFIG_ROOT}" != "/" ]]; then
    rm -f "/var/db/repos/${PROFILE_OVERLAY_NAME}"
  fi
  if [[ -n "${OVERLAY_REPO_NAME}" ]]; then
    rm -f \
      "/etc/portage/repos.conf/zz-build-gentoo-rootfs-container-${OVERLAY_REPO_NAME}.conf" \
      "${CONFIG_ROOT}/etc/portage/repos.conf/zz-build-gentoo-rootfs-container-${OVERLAY_REPO_NAME}.conf"
    rm -rf \
      "/var/db/repos/${OVERLAY_REPO_NAME}" \
      "${CONFIG_ROOT}/var/db/repos/${OVERLAY_REPO_NAME}"
  fi
  if [[ -n "${STAGED_OVERLAY_DIR}" ]]; then
    rm -rf "${STAGED_OVERLAY_DIR}"
  fi
}

sync_binpkg_cache() {
  [[ -n "${BINPKG_SYNC_REMOTE}" ]] || return 0
  [[ -d "${PKGDIR}" ]] || return 0
  "${SCRIPT_DIR}/sync-binpkgs-to-repo.sh" \
    --pkgdir "${PKGDIR}" \
    --repo-id "${BINPKG_REPO_ID}" \
    --remote "${BINPKG_SYNC_REMOTE}" \
    --remote-root "${BINPKG_SYNC_ROOT}"
}

on_rootfs_builder_exit() {
  local status=$?
  if ! sync_binpkg_cache; then
    log "binpkg sync failed; preserving original exit status ${status}"
  fi
  cleanup_rootfs_builder
  exit "${status}"
}
trap on_rootfs_builder_exit EXIT

if [[ "${RESET_ROOTFS}" == true ]]; then
  reset_rootfs_contents
fi

mkdir -p "${ROOT_DIR}"
install -d -m 0755 "${PKGDIR}"

prepare_stage3_tarball
extract_stage3_rootfs

install -d -m 0755 \
  "${ROOT_DIR}/etc" \
  "${ROOT_DIR}/proc" \
  "${ROOT_DIR}/sys" \
  "${ROOT_DIR}/dev" \
  "${ROOT_DIR}/run" \
  "${ROOT_DIR}/tmp" \
  "${ROOT_DIR}/var/tmp"
chmod 1777 "${ROOT_DIR}/tmp" "${ROOT_DIR}/var/tmp"

if [[ -n "${ROOTFS_LINKS_FILE}" ]]; then
  while read -r link_path link_target _; do
    [[ -n "${link_path}" ]] || continue
    [[ "${link_path}" =~ ^# ]] && continue
    [[ -n "${link_target}" ]] || die "rootfs link manifest line is missing a target: ${link_path}"
    [[ "${link_path}" == /* ]] || die "rootfs link path must be absolute: ${link_path}"
    link_target="${link_target#/}"
    link_dest="${ROOT_DIR}${link_path}"
    install -d -m 0755 "$(dirname "${link_dest}")"
    install -d -m 0755 "${ROOT_DIR}/$(dirname "${link_target}")" "${ROOT_DIR}/${link_target}"
    if [[ -e "${link_dest}" && ! -L "${link_dest}" ]]; then
      rmdir "${link_dest}" 2>/dev/null || die "rootfs link destination exists and is not replaceable: ${link_dest}"
    fi
    ln -snf "${link_target}" "${link_dest}"
  done < "${ROOTFS_LINKS_FILE}"
fi

if [[ "${CONFIG_ROOT}" != "/" ]]; then
  install -d -m 0755 \
    "${CONFIG_ROOT}/etc/portage" \
    "${CONFIG_ROOT}/etc/portage/gnupg" \
    "${CONFIG_ROOT}/etc/portage/repos.conf" \
    "${CONFIG_ROOT}/var/db/repos"
  chmod 0700 "${CONFIG_ROOT}/etc/portage/gnupg"
  if [[ -f /etc/portage/gnupg/pubring.kbx && ! -f "${CONFIG_ROOT}/etc/portage/gnupg/pubring.kbx" ]]; then
    cp -a /etc/portage/gnupg/. "${CONFIG_ROOT}/etc/portage/gnupg/"
    chmod 0700 "${CONFIG_ROOT}/etc/portage/gnupg"
  fi
  ln -snf /var/db/repos/gentoo "${CONFIG_ROOT}/var/db/repos/gentoo"
fi

if [[ "${CONFIG_ROOT}" != "/" && ${#PROFILE_PARENTS[@]} -gt 0 ]]; then
  install -d -m 0755 \
    "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/metadata" \
    "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/profiles/${PROFILE_NAME}"
  printf '%s\n' "${PROFILE_OVERLAY_NAME}" > "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/profiles/repo_name"
  printf 'repo-name = %s\nmasters = gentoo\nthin-manifests = true\n' "${PROFILE_OVERLAY_NAME}" \
    > "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/metadata/layout.conf"
  printf 'amd64 %s stable\n' "${PROFILE_NAME}" \
    > "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/profiles/profiles.desc"
  printf '8\n' > "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/profiles/${PROFILE_NAME}/eapi"
  : > "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/profiles/${PROFILE_NAME}/parent"
  for profile_parent in "${PROFILE_PARENTS[@]}"; do
    if [[ "${profile_parent}" == *:* ]]; then
      profile_repo="${profile_parent%%:*}"
      profile_path="${profile_parent#*:}"
      printf '../../../%s/profiles/%s\n' "${profile_repo}" "${profile_path}" \
        >> "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/profiles/${PROFILE_NAME}/parent"
    else
      printf '%s\n' "${profile_parent}" \
        >> "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}/profiles/${PROFILE_NAME}/parent"
    fi
  done
  cat > "${CONFIG_ROOT}/etc/portage/repos.conf/${PROFILE_OVERLAY_NAME}.conf" <<EOF
[${PROFILE_OVERLAY_NAME}]
location = /var/db/repos/${PROFILE_OVERLAY_NAME}
masters = gentoo
auto-sync = no
EOF
  ln -snf "../../var/db/repos/${PROFILE_OVERLAY_NAME}/profiles/${PROFILE_NAME}" \
    "${CONFIG_ROOT}/etc/portage/make.profile"
  install -d -m 0755 /var/db/repos
  ln -snf "${CONFIG_ROOT}/var/db/repos/${PROFILE_OVERLAY_NAME}" \
    "/var/db/repos/${PROFILE_OVERLAY_NAME}"
fi

if [[ -n "${PACKAGE_USE_FILE}" ]]; then
  install -d -m 0755 "${CONFIG_ROOT}/etc/portage/package.use"
  install -m 0644 "${PACKAGE_USE_FILE}" \
    "${CONFIG_ROOT}/etc/portage/package.use/99-build-gentoo-rootfs-container"
fi
if [[ -n "${HOST_PACKAGE_USE_FILE}" ]]; then
  install -d -m 0755 /etc/portage/package.use
  install -m 0644 "${HOST_PACKAGE_USE_FILE}" \
    "${HOST_PACKAGE_USE_DEST}"
fi
if [[ -n "${HOST_PACKAGE_MASK_FILE}" ]]; then
  install -d -m 0755 /etc/portage/package.mask
  install -m 0644 "${HOST_PACKAGE_MASK_FILE}" \
    "${HOST_PACKAGE_MASK_DEST}"
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
  "BINPKG_COMPRESS=${BINPKG_COMPRESS:-zstd}"
  "BINPKG_COMPRESS_FLAGS=${BINPKG_COMPRESS_FLAGS:--2}"
  "DISTCC_DISABLE=1"
  "PKGDIR=${PKGDIR}"
  "PORTAGE_BINPKG_FORMAT=${PORTAGE_BINPKG_FORMAT:-tar}"
)
sanitized_features="-distcc -ccache"
if [[ -n "${SANITIZED_FEATURES}" ]]; then
  sanitized_features="${sanitized_features} ${SANITIZED_FEATURES}"
fi
if [[ " ${sanitized_features} " != *" buildpkg "* ]]; then
  sanitized_features="${sanitized_features:+${sanitized_features} }buildpkg"
fi
if [[ "${BOOTSTRAP_RUNTIME_SEED}" != "none" && " ${sanitized_features} " != *" -collision-protect "* ]]; then
  sanitized_features="${sanitized_features:+${sanitized_features} }-collision-protect"
fi
emerge_env+=("FEATURES=${sanitized_features}")
if [[ ${#USE_OVERRIDE_FLAGS[@]} -gt 0 ]]; then
  current_use="${USE:-}"
  current_use="${current_use:+${current_use} }${USE_OVERRIDE_FLAGS[*]}"
  emerge_env+=("USE=${current_use}")
fi

rootfs_emerge() {
  local phase=$1
  local emptytree=$2
  local extra_env_name=$3
  local emerge_emptytree_args=()
  shift
  shift
  shift
  local -n extra_env_ref="${extra_env_name}"
  if [[ "${emptytree}" == true ]]; then
    emerge_emptytree_args=(--emptytree)
  fi
  log "emerging ${phase} package set: $*"
  env "${emerge_env[@]}" "${extra_env_ref[@]}" \
    emerge \
    --binpkg-respect-use=y \
    --buildpkg=y \
    --complete-graph=y \
    --usepkg=y \
    --verbose \
    --with-bdeps=y \
    --oneshot \
    "${emerge_emptytree_args[@]}" \
    --root="${ROOT_DIR}" \
    --config-root="${CONFIG_ROOT}" \
    --sysroot="${SYSROOT}" \
    "$@"
}

check_clang_sysroot_abi() {
  local lang=$1
  local compiler=$2
  local suffix=$3
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN
  printf 'int main(void) { return 0; }\n' > "${tmpdir}/test.${suffix}"
  if ! ${compiler} --sysroot="${ROOT_DIR}" "${tmpdir}/test.${suffix}" -o "${tmpdir}/test" >/tmp/build-gentoo-rootfs-container-${lang}-abi.log 2>&1; then
    sed 's/^/[build-gentoo-rootfs-container] ABI check: /' "/tmp/build-gentoo-rootfs-container-${lang}-abi.log" >&2 || true
    die "clang ${lang} ABI check failed for sysroot ${ROOT_DIR}"
  fi
  rm -rf "${tmpdir}"
  trap - RETURN
  log "clang ${lang} ABI check passed for sysroot ${ROOT_DIR}"
}

normalize_existing_path() {
  local input_path=$1
  local input_dir input_base
  input_dir="$(dirname "${input_path}")"
  input_base="$(basename "${input_path}")"
  printf '%s/%s' "$(cd "${input_dir}" && pwd -P)" "${input_base}"
}

seed_runtime_path() {
  local source_path=$1
  local current_path target_path destination_path copied=0
  current_path="$(normalize_existing_path "${source_path}")"

  while :; do
    [[ ${copied} -lt 16 ]] || die "runtime seed symlink loop suspected at ${source_path}"
    [[ -e "${current_path}" || -L "${current_path}" ]] || die "runtime seed path not found: ${current_path}"

    destination_path="${ROOT_DIR}${current_path}"
    install -d -m 0755 "$(dirname "${destination_path}")"
    rm -f "${destination_path}"
    cp -a "${current_path}" "${destination_path}"
    log "seeded runtime path ${current_path} -> ${destination_path}"
    copied=$((copied + 1))

    if [[ ! -L "${current_path}" ]]; then
      break
    fi

    target_path="$(readlink "${current_path}")"
    if [[ "${target_path}" != /* ]]; then
      target_path="$(dirname "${current_path}")/${target_path}"
    fi
    current_path="$(normalize_existing_path "${target_path}")"
  done
}

seed_clang_runtime_libraries() {
  local runtime_spec compiler_name library_name library_path
  [[ "${ROOT_DIR}" != "/" ]] || die "--bootstrap-runtime-seed cannot target /"
  require_cmd clang
  require_cmd clang++

  log "seeding host Clang runtime libraries into ${ROOT_DIR}"
  for runtime_spec in \
    "clang:libunwind.so" \
    "clang++:libc++.so" \
    "clang++:libc++_shared.so" \
    "clang++:libc++abi.so"
  do
    compiler_name="${runtime_spec%%:*}"
    library_name="${runtime_spec#*:}"
    library_path="$("${compiler_name}" --print-file-name="${library_name}")"
    [[ "${library_path}" == /* && ( -e "${library_path}" || -L "${library_path}" ) ]] \
      || die "${compiler_name} could not resolve ${library_name}: ${library_path}"
    seed_runtime_path "${library_path}"
  done
}

if [[ "${BOOTSTRAP_RUNTIME_SEED}" == "auto" ]]; then
  seed_clang_runtime_libraries
  check_clang_sysroot_abi c clang c
  check_clang_sysroot_abi cxx clang++ cc
fi

if [[ ${#BOOTSTRAP_PACKAGE_ATOMS[@]} -gt 0 ]]; then
  log "bootstrapping compiler/runtime sysroot prerequisites with libgcc/libstdc++ fallback"
  bootstrap_extra_env=(
    "CC=clang --unwindlib=libgcc"
    "CXX=clang++ --stdlib=libstdc++ --unwindlib=libgcc"
  )
  rootfs_emerge "bootstrap" \
    false \
    bootstrap_extra_env \
    "${BOOTSTRAP_PACKAGE_ATOMS[@]}"
  check_clang_sysroot_abi c clang c
  check_clang_sysroot_abi cxx clang++ cc
fi

main_extra_env=()
rootfs_emerge "main" "${MAIN_EMPTYTREE}" main_extra_env "${PACKAGE_ATOMS[@]}"

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
    BUILDAH_CONTAINER_ID="$(buildah from scratch)"
    buildah add "${BUILDAH_CONTAINER_ID}" "${ROOT_DIR}" /
    buildah config --cmd "[\"${DEFAULT_CMD}\"]" "${BUILDAH_CONTAINER_ID}"
    [[ -n "${SOURCE_URL}" ]] && buildah config --label "org.opencontainers.image.source=${SOURCE_URL}" "${BUILDAH_CONTAINER_ID}"
    [[ -n "${DESCRIPTION}" ]] && buildah config --label "org.opencontainers.image.description=${DESCRIPTION}" "${BUILDAH_CONTAINER_ID}"
    buildah commit "${BUILDAH_CONTAINER_ID}" "${IMAGE_REF}" >/dev/null
    buildah rm "${BUILDAH_CONTAINER_ID}" >/dev/null
    BUILDAH_CONTAINER_ID=
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
