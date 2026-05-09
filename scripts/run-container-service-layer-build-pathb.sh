#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: run-container-service-layer-build-pathb.sh --service NAME [--dry-run]

Supported service layers:
  nginx
  haproxy
  rsyslog_collector

Environment overrides:
  CONTAINER_STAGE3_TARBALL
  CONTAINER_STAGE3_TARGET
  CONTAINER_STAGE3_CACHE_DIR
  CONTAINER_SERVICE_ROOT
  BINPKG_SYNC_REMOTE
  BINPKG_SYNC_ROOT
  EMERGE_JOBS
  EMERGE_LOAD_AVERAGE
EOF
}

fail() {
  printf '[run-container-service-layer-build-pathb] ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /root/RFC_Codex_Gentoo-Stage4-LLVM/scripts/build-gentoo-rootfs-container.sh ]]; then
  SCRIPT_DIR=/root/RFC_Codex_Gentoo-Stage4-LLVM/scripts
fi
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVICE=''
DRY_RUN='0'

while [[ $# -gt 0 ]]; do
  case "$1" in
  --service)
    SERVICE="${2:-}"
    shift 2
    ;;
  --dry-run)
    DRY_RUN='1'
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    fail "Unknown argument: $1"
    ;;
  esac
done

[[ -n "${SERVICE}" ]] || fail '--service is required'

SERVICE_MAIN_ENV=()
SERVICE_BOOTSTRAP_PACKAGE_LIST=''

case "${SERVICE}" in
nginx)
  IMAGE_NAME='gentoo-stage5-nginx'
  PACKAGE_LIST='container-image-definitions/gentoo-stage5-nginx.packages'
  DESCRIPTION='Gentoo Stage5 nginx service container'
  ;;
haproxy)
  IMAGE_NAME='gentoo-stage5-haproxy'
  PACKAGE_LIST='container-image-definitions/gentoo-stage5-haproxy.packages'
  DESCRIPTION='Gentoo Stage5 HAProxy service container'
  SERVICE_MAIN_ENV=(
    'CC=gcc'
    'CXX=g++'
    'CPP=cpp'
    'AR=gcc-ar'
    'NM=gcc-nm'
    'RANLIB=gcc-ranlib'
    'LDFLAGS=-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=bfd'
  )
  ;;
rsyslog_collector)
  IMAGE_NAME='gentoo-stage5-rsyslog-collector'
  PACKAGE_LIST='container-image-definitions/gentoo-stage5-rsyslog-collector.packages'
  SERVICE_BOOTSTRAP_PACKAGE_LIST='container-image-definitions/gentoo-stage5-rsyslog-collector.bootstrap.packages'
  DESCRIPTION='Gentoo Stage5 rsyslog collector service container'
  ;;
*)
  fail "Unsupported service layer: ${SERVICE}"
  ;;
esac

cd "${REPO_ROOT}"
[[ -f "${PACKAGE_LIST}" ]] || fail "Package list not found: ${PACKAGE_LIST}"
if [[ -n "${SERVICE_BOOTSTRAP_PACKAGE_LIST}" ]]; then
  [[ -f "${SERVICE_BOOTSTRAP_PACKAGE_LIST}" ]] || fail "Bootstrap package list not found: ${SERVICE_BOOTSTRAP_PACKAGE_LIST}"
fi

REPO_ID="${STAGE5_BINPKG_REPO_ID:-stage3-llvm_clang_openrc__stage5-service_container-${SERVICE}__amd64__x86_64_v2_generic}"
REPO_URL="${STAGE5_BINPKG_REPO_URL:-http://10.9.8.90:8088/${REPO_ID}}"
SERVICE_ROOT="${CONTAINER_SERVICE_ROOT:-/var/lib/container-services-ephemeral/images}"
ROOTFS_DIR="${CONTAINER_ROOTFS_DIR:-${SERVICE_ROOT}/${IMAGE_NAME}-rootfs}"
PKGDIR="${CONTAINER_PKGDIR:-${SERVICE_ROOT}/${IMAGE_NAME}-binpkgs}"
TARBALL="${CONTAINER_TARBALL:-${SERVICE_ROOT}/${IMAGE_NAME}.tar.zst}"
IMAGE_REF="${CONTAINER_IMAGE_REF:-localhost/${IMAGE_NAME}:latest}"
SERVICE_PACKAGE_USE_FILE="container-image-definitions/${IMAGE_NAME}.package.use"
STAGE3_TARGET="${CONTAINER_STAGE3_TARGET:-amd64-llvm-openrc}"
STAGE3_CACHE_DIR="${CONTAINER_STAGE3_CACHE_DIR:-/var/lib/container-services-ephemeral/stage3-cache}"
STAGE3_TARBALL="${CONTAINER_STAGE3_TARBALL:-}"
BINPKG_SYNC_REMOTE="${BINPKG_SYNC_REMOTE:-root@10.9.8.90}"
BINPKG_SYNC_ROOT="${BINPKG_SYNC_ROOT:-/srv/stage5-binpkgs}"
EMERGE_JOBS="${EMERGE_JOBS:-20}"
EMERGE_LOAD_AVERAGE="${EMERGE_LOAD_AVERAGE:-60}"

if [[ "${SERVICE}" == 'rsyslog_collector' ]]; then
  SERVICE_MAIN_ENV=(
    "PKG_CONFIG_SYSROOT_DIR=${ROOTFS_DIR}"
    "PKG_CONFIG_LIBDIR=${ROOTFS_DIR}/usr/lib64/pkgconfig:${ROOTFS_DIR}/usr/lib/pkgconfig:${ROOTFS_DIR}/usr/share/pkgconfig"
    "PKG_CONFIG_PATH=${ROOTFS_DIR}/usr/lib64/pkgconfig:${ROOTFS_DIR}/usr/lib/pkgconfig:${ROOTFS_DIR}/usr/share/pkgconfig"
  )
fi

if [[ "${DRY_RUN}" == '1' ]]; then
  printf 'service=%s\n' "${SERVICE}"
  printf 'package-list=%s\n' "${PACKAGE_LIST}"
  if [[ -n "${SERVICE_BOOTSTRAP_PACKAGE_LIST}" ]]; then
    printf 'bootstrap-package-list=%s\n' "${SERVICE_BOOTSTRAP_PACKAGE_LIST}"
  fi
  printf 'image-ref=%s\n' "${IMAGE_REF}"
  if [[ -f "${SERVICE_PACKAGE_USE_FILE}" ]]; then
    printf 'package-use-file=%s\n' "${SERVICE_PACKAGE_USE_FILE}"
  fi
  for env_entry in "${SERVICE_MAIN_ENV[@]}"; do
    printf 'main-env=%s\n' "${env_entry}"
  done
  printf 'rootfs=%s\n' "${ROOTFS_DIR}"
  printf 'tarball=%s\n' "${TARBALL}"
  printf 'pkgdir=%s\n' "${PKGDIR}"
  printf 'binpkg-repo-id=%s\n' "${REPO_ID}"
  printf 'binpkg-repo-url=%s\n' "${REPO_URL}"
  if [[ -n "${STAGE3_TARBALL}" ]]; then
    printf 'stage3-tarball=%s\n' "${STAGE3_TARBALL}"
  else
    printf 'stage3-target=%s\n' "${STAGE3_TARGET}"
    printf 'stage3-cache-dir=%s\n' "${STAGE3_CACHE_DIR}"
  fi
  exit 0
fi

export MAKEOPTS="${MAKEOPTS:--j64}"
export BINHOST="${BINHOST:-${REPO_URL}}"
export PORTAGE_BINHOST="${PORTAGE_BINHOST:-${REPO_URL}}"
export EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS:---jobs=${EMERGE_JOBS} --load-average=${EMERGE_LOAD_AVERAGE} --getbinpkg=y --buildpkg=y --usepkg=y --binpkg-changed-deps=n --with-bdeps=y --complete-graph=y --autounmask=y --autounmask-backtrack=y --autounmask-continue=y --autounmask-unrestricted-atoms=y --autounmask-use=y --autounmask-write=y --binpkg-respect-use=y}"
export FEATURES="${FEATURES:-buildpkg parallel-install merge-sync -distcc -ccache}"
export PORTAGE_BINPKG_FORMAT="${PORTAGE_BINPKG_FORMAT:-tar}"
export BINPKG_COMPRESS="${BINPKG_COMPRESS:-zstd}"
export BINPKG_COMPRESS_FLAGS="${BINPKG_COMPRESS_FLAGS:--2}"
export RES_OPTIONS="${RES_OPTIONS:-attempts:2 timeout:2}"

stage3_source_args=()
if [[ -n "${STAGE3_TARBALL}" ]]; then
  stage3_source_args=(--stage3-tarball "${STAGE3_TARBALL}")
else
  stage3_source_args=(--stage3-target "${STAGE3_TARGET}" --stage3-cache-dir "${STAGE3_CACHE_DIR}")
fi

package_use_args=(--package-use-file container-image-definitions/gentoo-stage3-llvm-clang-openrc.package.use)
if [[ -f "${SERVICE_PACKAGE_USE_FILE}" ]]; then
  package_use_args=(--package-use-file "${SERVICE_PACKAGE_USE_FILE}")
fi

builder_common_args=(
  --root "${ROOTFS_DIR}"
  --pkgdir "${PKGDIR}"
  --binpkg-repo-id "${REPO_ID}"
  --binpkg-sync-remote "${BINPKG_SYNC_REMOTE}"
  --binpkg-sync-root "${BINPKG_SYNC_ROOT}"
  --use-file container-image-definitions/gentoo-stage3-llvm-clang-openrc.use
  "${package_use_args[@]}"
  --config-root "${ROOTFS_DIR}"
  --sysroot "${ROOTFS_DIR}"
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM
  --description "${DESCRIPTION}"
)

if [[ -n "${SERVICE_BOOTSTRAP_PACKAGE_LIST}" ]]; then
  bash "${SCRIPT_DIR}/build-gentoo-rootfs-container.sh" \
    "${builder_common_args[@]}" \
    "${stage3_source_args[@]}" \
    --reset-rootfs \
    --package-list "${SERVICE_BOOTSTRAP_PACKAGE_LIST}" \
    --engine none \
    --main-emptytree false

  exec env "${SERVICE_MAIN_ENV[@]}" bash "${SCRIPT_DIR}/build-gentoo-rootfs-container.sh" \
    "${builder_common_args[@]}" \
    --main-emptytree false \
    --package-list "${PACKAGE_LIST}" \
    --image-ref "${IMAGE_REF}" \
    --tarball "${TARBALL}"
fi

exec env "${SERVICE_MAIN_ENV[@]}" bash "${SCRIPT_DIR}/build-gentoo-rootfs-container.sh" \
  "${builder_common_args[@]}" \
  "${stage3_source_args[@]}" \
  --reset-rootfs \
  --package-list "${PACKAGE_LIST}" \
  --image-ref "${IMAGE_REF}" \
  --tarball "${TARBALL}"
