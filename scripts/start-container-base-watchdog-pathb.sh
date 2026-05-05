#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_ID="${STAGE5_BINPKG_REPO_ID:-stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic}"
LAUNCH_SCRIPT="${CONTAINER_BASE_LAUNCH_SCRIPT:-/root/run-container-base-build-pathb.sh}"
BUILD_LOG="${CONTAINER_BASE_BUILD_LOG:-/root/container-base-rerun.log}"
WATCH_PATTERN="${CONTAINER_BASE_WATCH_PATTERN:-build-gentoo-rootfs-container.sh --root /var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc-rootfs}"
PKGDIR="${CONTAINER_PKGDIR:-/var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc-binpkgs}"
SYNC_REMOTE="${BINPKG_SYNC_REMOTE:-root@10.9.8.90}"
SYNC_ROOT="${BINPKG_SYNC_ROOT:-/srv/stage5-binpkgs}"
INTERVAL="${CONTAINER_BASE_WATCH_INTERVAL:-300}"
MAX_RESTARTS="${CONTAINER_BASE_MAX_RESTARTS:-4}"
WATCH_LOG="${CONTAINER_BASE_WATCH_LOG:-/root/container-base-watchdog.log}"
RUNNER_LOG="${CONTAINER_BASE_WATCH_RUNNER_LOG:-/root/container-base-watchdog.runner.log}"

cmd=(
  "${SCRIPT_DIR}/watch-container-base-build.sh"
  --launch-script "${LAUNCH_SCRIPT}"
  --build-log "${BUILD_LOG}"
  --watch-pattern "${WATCH_PATTERN}"
  --pkgdir "${PKGDIR}"
  --repo-id "${REPO_ID}"
  --sync-remote "${SYNC_REMOTE}"
  --sync-root "${SYNC_ROOT}"
  --interval "${INTERVAL}"
  --max-restarts "${MAX_RESTARTS}"
  --watch-log "${WATCH_LOG}"
)

setsid -f "${cmd[@]}" >>"${RUNNER_LOG}" 2>&1
