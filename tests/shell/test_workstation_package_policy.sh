#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PROFILE_FILE="${ANSIBLE_ROOT}/profile-definitions/vm-workstation-nscde.yml"
METADATA_FILE="${ANSIBLE_ROOT}/profile-definitions/vm-workstation-nscde.metadata.yml"
PACKAGE_LIST="${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-workstation-nscde.packages"
REVIEW_DIR="${REPO_ROOT}/docs/workstation-package-capture/stage4-lox-workstation-review-2026-05-06"
FORMER_POLICY_DIR="${REPO_ROOT}/docs/workstation-package-capture/former-portage-policy"
GPU_ADVISORY="${FORMER_POLICY_DIR}/gpu-universal-xorg-advisory.atoms"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_grep() {
  local pattern=$1
  local file=$2
  grep -Eq -- "${pattern}" "${file}" || fail "missing pattern '${pattern}' in ${file}"
}

reject_grep() {
  local pattern=$1
  local file=$2
  if grep -Eq -- "${pattern}" "${file}"; then
    fail "unexpected pattern '${pattern}' in ${file}"
  fi
}

require_file "${PROFILE_FILE}"
require_file "${METADATA_FILE}"
require_file "${PACKAGE_LIST}"
require_file "${REVIEW_DIR}/stage5-workstation-review-candidates.atoms"
require_file "${REVIEW_DIR}/wayland-plasma-rejects.atoms"
require_file "${FORMER_POLICY_DIR}/README.md"
require_file "${GPU_ADVISORY}"

require_grep 'stage4-lox__stage5-workstation-nscde__<arch>__gpu-universal-xorg' "${METADATA_FILE}"
require_grep 'stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg' "${PROFILE_FILE}"
require_grep 'USE="\$\{USE\}.*-wayland' "${PROFILE_FILE}"
require_grep 'VIDEO_CARDS="\$\{VIDEO_CARDS\}.*intel.*amdgpu.*radeonsi.*nvidia' "${PROFILE_FILE}"
require_grep 'media-libs/mesa .* -wayland' "${PROFILE_FILE}"
require_grep 'media-libs/libva .* -wayland' "${PROFILE_FILE}"
require_grep 'media-libs/vulkan-loader .* -wayland' "${PROFILE_FILE}"
require_grep 'gui-libs/gtk .* -wayland' "${PROFILE_FILE}"
require_grep 'app-emulation/qemu .* -wayland' "${PROFILE_FILE}"
require_grep 'patch_files:' "${PROFILE_FILE}"
require_grep 'dev-libs/intel-metrics-library/01-disable-upstream-release-lto.patch' "${PROFILE_FILE}"
require_grep 'add_definitions \(-flto\)' "${PROFILE_FILE}"
require_grep 'dev-qt/qtwayland' "${PROFILE_FILE}"
require_grep 'x11-base/xwayland' "${PROFILE_FILE}"
require_grep 'x11-misc/sddm' "${PROFILE_FILE}"

for atom in \
  dev-libs/intel-compute-runtime \
  dev-libs/rocm-opencl-runtime \
  dev-util/clinfo \
  dev-util/vulkan-tools \
  media-libs/amdgpu-pro-vulkan \
  media-libs/mesa \
  media-libs/vulkan-loader \
  media-video/amdgpu-pro-amf \
  sys-kernel/linux-firmware \
  x11-drivers/xf86-video-amdgpu \
  x11-drivers/xf86-video-intel \
  x11-drivers/nvidia-drivers; do
  require_grep "^=?${atom}([[:space:]]|$|=|-[0-9])" "${PACKAGE_LIST}"
done

require_grep '^dev-libs/amdgpu-pro-opencl$' "${GPU_ADVISORY}"
reject_grep '^dev-libs/amdgpu-pro-opencl$' "${PACKAGE_LIST}"

require_grep '^kde-plasma/plasma-meta$' "${REVIEW_DIR}/wayland-plasma-rejects.atoms"
require_grep '^x11-misc/sddm$' "${REVIEW_DIR}/wayland-plasma-rejects.atoms"
reject_grep '^(kde-plasma/|x11-misc/sddm$|x11-base/xwayland$|dev-qt/qtwayland$)' "${REVIEW_DIR}/stage5-workstation-review-candidates.atoms"
reject_grep 'private-keys-v1|pubring\.kbx|trustdb\.gpg|openpgp-revocs' "${FORMER_POLICY_DIR}/README.md"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
