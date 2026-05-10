#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${BUILD_SCRIPT:-${SCRIPT_DIR}/build-stage3-qcow.sh}"
LAUNCH_SCRIPT="${LAUNCH_SCRIPT:-${SCRIPT_DIR}/qemu-launch-stage3-vm.sh}"

X12_STAGEBUILD_MODE="${X12_STAGEBUILD_MODE:-print-env}"
X12_STAGEBUILD_DRY_RUN="${X12_STAGEBUILD_DRY_RUN:-0}"
X12_STAGEBUILD_INSTANCE_NAME="${X12_STAGEBUILD_INSTANCE_NAME:-x12again-stagebuild-k10}"
X12_STAGEBUILD_ROOT="${X12_STAGEBUILD_ROOT:-/srv/vm-images/stagebuild}"
X12_STAGEBUILD_BASE_DIR="${X12_STAGEBUILD_BASE_DIR:-/srv/vm-images/stagebuild-base}"
X12_STAGEBUILD_INSTANCE_DIR="${X12_STAGEBUILD_INSTANCE_DIR:-/srv/vm-images/stagebuild-instances/${X12_STAGEBUILD_INSTANCE_NAME}}"
X12_STAGEBUILD_CACHE_DIR="${X12_STAGEBUILD_CACHE_DIR:-/srv/build-cache}"
X12_STAGEBUILD_STAGING_DIR="${X12_STAGEBUILD_STAGING_DIR:-/var/lib/netboot/staging/path-b/${X12_STAGEBUILD_INSTANCE_NAME}}"
X12_STAGEBUILD_DISTFILES_DIR="${X12_STAGEBUILD_DISTFILES_DIR:-${X12_STAGEBUILD_CACHE_DIR}/distfiles}"
X12_STAGEBUILD_BINPKG_DIR="${X12_STAGEBUILD_BINPKG_DIR:-${X12_STAGEBUILD_CACHE_DIR}/binpkgs}"
X12_STAGEBUILD_STAGE3_CACHE_DIR="${X12_STAGEBUILD_STAGE3_CACHE_DIR:-${X12_STAGEBUILD_CACHE_DIR}/stage3}"
X12_STAGEBUILD_QCOW_SIZE_GIB="${X12_STAGEBUILD_QCOW_SIZE_GIB:-512}"
X12_STAGEBUILD_QEMU_SMP="${X12_STAGEBUILD_QEMU_SMP:-64}"
X12_STAGEBUILD_QEMU_MEMORY_MIB="${X12_STAGEBUILD_QEMU_MEMORY_MIB:-262144}"
X12_STAGEBUILD_MAKEOPTS="${X12_STAGEBUILD_MAKEOPTS:--j56 -l64}"
X12_STAGEBUILD_EMERGE_DEFAULT_OPTS="${X12_STAGEBUILD_EMERGE_DEFAULT_OPTS:---buildpkg=y --usepkg=y --with-bdeps=y --complete-graph=y --autounmask=y --autounmask-backtrack=y --autounmask-continue=y --autounmask-unrestricted-atoms=y --autounmask-use=y --autounmask-write=y --binpkg-respect-use=y --jobs=8 --load-average=64}"
X12_STAGEBUILD_SSH_PORT="${X12_STAGEBUILD_SSH_PORT:-2230}"
X12_STAGEBUILD_SERIAL_PORT="${X12_STAGEBUILD_SERIAL_PORT:-4566}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--print-env|--build|--launch|--full|--help]

Modes:
  --print-env  Print the resolved disposable builder VM environment.
  --build      Build the disposable builder QCOW image.
  --launch     Launch the disposable builder VM.
  --full       Build and launch the disposable builder VM.

Set X12_STAGEBUILD_DRY_RUN=1 to dry-run delegated build and launch commands.
EOF
}

log() {
  printf '[x12again-stagebuild-vm] %s\n' "$*"
}

fail() {
  printf '[x12again-stagebuild-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while (($#)); do
    case "$1" in
    --print-env)
      X12_STAGEBUILD_MODE='print-env'
      ;;
    --build)
      X12_STAGEBUILD_MODE='build'
      ;;
    --launch)
      X12_STAGEBUILD_MODE='launch'
      ;;
    --full)
      X12_STAGEBUILD_MODE='full'
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unsupported argument: $1"
      ;;
    esac
    shift
  done
}

export_builder_environment() {
  export INSTANCE_NAME="${X12_STAGEBUILD_INSTANCE_NAME}"
  export STAGE3_TARGET="${STAGE3_TARGET:-amd64-llvm-openrc}"
  export STAGE3_PROFILE_PRESET="${STAGE3_PROFILE_PRESET:-base}"
  export STAGE3_IMAGE_DIR="${X12_STAGEBUILD_INSTANCE_DIR}"
  export STAGE3_CACHE_DIR="${X12_STAGEBUILD_STAGE3_CACHE_DIR}"
  export STAGE3_IMAGE_OUTPUT_DIR="${X12_STAGEBUILD_INSTANCE_DIR}/images"
  export STAGE3_BUILD_DIR="${X12_STAGEBUILD_INSTANCE_DIR}/build/${X12_STAGEBUILD_INSTANCE_NAME}"
  export QCOW_IMAGE="${STAGE3_IMAGE_OUTPUT_DIR}/${X12_STAGEBUILD_INSTANCE_NAME}.qcow2"
  export QCOW_SIZE_GIB="${X12_STAGEBUILD_QCOW_SIZE_GIB}"
  export STAGE3_HOST_DISTFILES_DIR="${STAGE3_HOST_DISTFILES_DIR:-${X12_STAGEBUILD_DISTFILES_DIR}}"
  export STAGE3_HOST_BINPKG_DIR="${STAGE3_HOST_BINPKG_DIR:-${X12_STAGEBUILD_BINPKG_DIR}}"
  export STAGE3_GUEST_DISTFILES_DIR="${STAGE3_GUEST_DISTFILES_DIR:-/srv/build-cache/distfiles}"
  export STAGE3_GUEST_BINPKG_DIR="${STAGE3_GUEST_BINPKG_DIR:-/srv/build-cache/binpkgs}"
  export VM_HOSTNAME="${VM_HOSTNAME:-${X12_STAGEBUILD_INSTANCE_NAME}}"
  export QEMU_STAGE3_BUILD_DRY_RUN="${QEMU_STAGE3_BUILD_DRY_RUN:-${X12_STAGEBUILD_DRY_RUN}}"
  export QEMU_LAUNCH_DRY_RUN="${QEMU_LAUNCH_DRY_RUN:-${X12_STAGEBUILD_DRY_RUN}}"
  export QEMU_SMP="${QEMU_SMP:-${X12_STAGEBUILD_QEMU_SMP}}"
  export QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB:-${X12_STAGEBUILD_QEMU_MEMORY_MIB}}"
  export QEMU_BOOT_SOURCE="${QEMU_BOOT_SOURCE:-qcow}"
  export QEMU_ATTACH_HOST_DISKS="${QEMU_ATTACH_HOST_DISKS:-0}"
  export QEMU_NETWORK_MODE="${QEMU_NETWORK_MODE:-user}"
  export QEMU_NETDEV_BACKEND="${QEMU_NETDEV_BACKEND:-user,hostfwd=tcp:127.0.0.1:${X12_STAGEBUILD_SSH_PORT}-:22}"
  export SSH_READY_HOST="${SSH_READY_HOST:-127.0.0.1}"
  export SSH_READY_PORT="${SSH_READY_PORT:-${X12_STAGEBUILD_SSH_PORT}}"
  export QEMU_SERIAL_MODE="${QEMU_SERIAL_MODE:-tcp}"
  export QEMU_SERIAL_TCP="${QEMU_SERIAL_TCP:-127.0.0.1:${X12_STAGEBUILD_SERIAL_PORT},server=on,wait=off,telnet=on}"
  export QEMU_DISPLAY_MODE="${QEMU_DISPLAY_MODE:-none}"
  export WAIT_FOR_SSH="${WAIT_FOR_SSH:-1}"
  export LAUNCHER_LOG_ENABLE="${LAUNCHER_LOG_ENABLE:-0}"
  export STAGE3_MAKE_CONF_APPEND="${STAGE3_MAKE_CONF_APPEND:-FEATURES=\"buildpkg -binpkg-request-signature -network-sandbox\"
MAKEOPTS=\"${X12_STAGEBUILD_MAKEOPTS}\"
EMERGE_DEFAULT_OPTS=\"${X12_STAGEBUILD_EMERGE_DEFAULT_OPTS}\"
PKGDIR=\"${STAGE3_GUEST_BINPKG_DIR}\"
DISTDIR=\"${STAGE3_GUEST_DISTFILES_DIR}\"
PORTAGE_TMPDIR=\"/var/tmp/portage\"}"
  export STAGE3_EXTRA_PACKAGES="${STAGE3_EXTRA_PACKAGES:-sys-fs/dosfstools sys-apps/gptfdisk sys-block/parted sys-fs/zfs sys-fs/zfs-kmod app-portage/gentoolkit app-portage/eix net-misc/rsync app-misc/tmux}"
}

print_environment() {
  cat <<EOF
X12_STAGEBUILD_INSTANCE_NAME=${X12_STAGEBUILD_INSTANCE_NAME}
X12_STAGEBUILD_ROOT=${X12_STAGEBUILD_ROOT}
X12_STAGEBUILD_BASE_DIR=${X12_STAGEBUILD_BASE_DIR}
X12_STAGEBUILD_INSTANCE_DIR=${X12_STAGEBUILD_INSTANCE_DIR}
X12_STAGEBUILD_CACHE_DIR=${X12_STAGEBUILD_CACHE_DIR}
X12_STAGEBUILD_STAGING_DIR=${X12_STAGEBUILD_STAGING_DIR}
X12_STAGEBUILD_DISTFILES_DIR=${X12_STAGEBUILD_DISTFILES_DIR}
X12_STAGEBUILD_BINPKG_DIR=${X12_STAGEBUILD_BINPKG_DIR}
X12_STAGEBUILD_STAGE3_CACHE_DIR=${X12_STAGEBUILD_STAGE3_CACHE_DIR}
STAGE3_HOST_DISTFILES_DIR=${STAGE3_HOST_DISTFILES_DIR}
STAGE3_HOST_BINPKG_DIR=${STAGE3_HOST_BINPKG_DIR}
STAGE3_GUEST_DISTFILES_DIR=${STAGE3_GUEST_DISTFILES_DIR}
STAGE3_GUEST_BINPKG_DIR=${STAGE3_GUEST_BINPKG_DIR}
QCOW_IMAGE=${QCOW_IMAGE}
QCOW_SIZE_GIB=${QCOW_SIZE_GIB}
QEMU_SMP=${QEMU_SMP}
QEMU_MEMORY_MIB=${QEMU_MEMORY_MIB}
QEMU_ATTACH_HOST_DISKS=${QEMU_ATTACH_HOST_DISKS}
X12_STAGEBUILD_MAKEOPTS=${X12_STAGEBUILD_MAKEOPTS}
X12_STAGEBUILD_EMERGE_DEFAULT_OPTS=${X12_STAGEBUILD_EMERGE_DEFAULT_OPTS}
SSH_READY_PORT=${SSH_READY_PORT}
QEMU_SERIAL_TCP=${QEMU_SERIAL_TCP}
EOF
}

ensure_builder_paths() {
  mkdir -p \
    "${X12_STAGEBUILD_BASE_DIR}" \
    "${X12_STAGEBUILD_INSTANCE_DIR}" \
    "${X12_STAGEBUILD_DISTFILES_DIR}" \
    "${X12_STAGEBUILD_BINPKG_DIR}" \
    "${X12_STAGEBUILD_STAGE3_CACHE_DIR}" \
    "${X12_STAGEBUILD_STAGING_DIR}"
}

run_build() {
  ensure_builder_paths
  log "Building disposable builder QCOW: ${QCOW_IMAGE}"
  "${BUILD_SCRIPT}"
}

run_launch() {
  ensure_builder_paths
  log "Launching disposable builder VM: ${QCOW_IMAGE}"
  "${LAUNCH_SCRIPT}"
}

main() {
  parse_args "$@"
  export_builder_environment

  case "${X12_STAGEBUILD_MODE}" in
  print-env)
    print_environment
    ;;
  build)
    run_build
    ;;
  launch)
    run_launch
    ;;
  full)
    run_build
    run_launch
    ;;
  *)
    fail "Unsupported X12_STAGEBUILD_MODE: ${X12_STAGEBUILD_MODE}"
    ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
