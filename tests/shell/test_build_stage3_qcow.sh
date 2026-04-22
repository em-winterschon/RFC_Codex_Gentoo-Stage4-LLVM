#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/build-stage3-qcow.sh"

# shellcheck source=../../gentoo-virt-qemu/build-stage3-qcow.sh
source "${BUILD_SCRIPT}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  [[ "${actual}" == "${expected}" ]] || fail "expected '${expected}', got '${actual}'"
}

reset_builder_state() {
  INSTANCE_NAME='gentoo-stage4-testvm'
  STAGE3_TARGET='amd64-llvm-openrc'
  STAGE3_MIRROR_ROOT='https://distfiles.gentoo.org/releases'
  STAGE3_IMAGE_DIR='/tmp/stage3'
  STAGE3_CACHE_DIR="${STAGE3_IMAGE_DIR}/cache"
  STAGE3_IMAGE_OUTPUT_DIR="${STAGE3_IMAGE_DIR}/images"
  STAGE3_BUILD_DIR="${STAGE3_IMAGE_DIR}/build/${INSTANCE_NAME}"
  TARGET_ROOT_MNT="${STAGE3_BUILD_DIR}/rootfs"
  TARGET_EFI_MNT="${TARGET_ROOT_MNT}/boot/efi"
  WORK_BOOTSTRAP_SCRIPT="${STAGE3_BUILD_DIR}/bootstrap-stage3-vm.sh"
  QCOW_IMAGE="${STAGE3_IMAGE_OUTPUT_DIR}/${INSTANCE_NAME}.qcow2"
  QEMU_STAGE3_BUILD_DRY_RUN='1'
  STAGE3_VERIFY_CHECKSUM='1'
  SSH_AUTHORIZED_KEY='ssh-ed25519 AAAATestKey codex@test'
  SSH_AUTHORIZED_KEY_FILE=''
  STAGE3_ROOT_PASSWORD_HASH=''
  PORTAGE_SYNC_COMMAND='emerge-webrsync'
  STAGE3_RELEASE_ARCH=''
  STAGE3_CURRENT_DIR=''
  STAGE3_LATEST_TXT=''
  STAGE3_GRUB_TARGET=''
  STAGE3_HOST_ARCH=''
  STAGE3_LLVM_TARGETS=''
  STAGE3_STAGE_TARBALL_NAME=''
  STAGE3_STAGE_TARBALL_URL=''
  STAGE3_STAGE_SHA256_URL=''
  STAGE3_STAGE_TARBALL_PATH=''
  STAGE3_STAGE_SHA256_PATH=''
  STAGE3_STAGE_SHA256=''
}

test_resolve_stage3_target_maps_supported_enums() {
  reset_builder_state
  STAGE3_TARGET='amd64-llvm-openrc'
  resolve_stage3_target
  assert_equals "${STAGE3_CURRENT_DIR}" 'current-stage3-amd64-llvm-openrc'
  assert_equals "${STAGE3_GRUB_TARGET}" 'x86_64-efi'

  reset_builder_state
  STAGE3_TARGET='arm64-llvm-openrc'
  resolve_stage3_target
  assert_equals "${STAGE3_CURRENT_DIR}" 'current-stage3-arm64-llvm-openrc'
  assert_equals "${STAGE3_HOST_ARCH}" 'aarch64'

  reset_builder_state
  STAGE3_TARGET='power9le-openrc'
  resolve_stage3_target
  assert_equals "${STAGE3_CURRENT_DIR}" 'current-stage3-power9le-openrc'
  assert_equals "${STAGE3_RELEASE_ARCH}" 'ppc'
}

test_resolve_stage3_target_rejects_invalid_enum() {
  local output status

  reset_builder_state
  STAGE3_TARGET='amd64-openrc-cloudbanana'

  set +e
  output="$(resolve_stage3_target 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '1'
  assert_contains "${output}" 'Unsupported STAGE3_TARGET'
}

test_main_dry_run_prints_stage3_build_plan() {
  local temp_dir output status bootstrap
  temp_dir="$(mktemp -d)"

  reset_builder_state
  STAGE3_IMAGE_DIR="${temp_dir}"
  STAGE3_CACHE_DIR="${STAGE3_IMAGE_DIR}/cache"
  STAGE3_IMAGE_OUTPUT_DIR="${STAGE3_IMAGE_DIR}/images"
  STAGE3_BUILD_DIR="${STAGE3_IMAGE_DIR}/build/${INSTANCE_NAME}"
  TARGET_ROOT_MNT="${STAGE3_BUILD_DIR}/rootfs"
  TARGET_EFI_MNT="${TARGET_ROOT_MNT}/boot/efi"
  WORK_BOOTSTRAP_SCRIPT="${STAGE3_BUILD_DIR}/bootstrap-stage3-vm.sh"
  QCOW_IMAGE="${STAGE3_IMAGE_OUTPUT_DIR}/${INSTANCE_NAME}.qcow2"
  HOST_RESOLV_CONF="${temp_dir}/resolv.conf"
  printf 'nameserver 1.1.1.1\n' >"${HOST_RESOLV_CONF}"

  fetch_text() {
    cat <<'EOF'
stage3-amd64-llvm-openrc-20260420T120000Z.tar.xz 12345
EOF
  }

  set +e
  output="$(main 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '0'
  assert_contains "${output}" 'current-stage3-amd64-llvm-openrc'
  assert_contains "${output}" 'qemu-img create -f qcow2'
  assert_contains "${output}" 'qemu-nbd --connect'
  assert_contains "${output}" '[COMPLETE]'
  bootstrap="$(cat "${WORK_BOOTSTRAP_SCRIPT}")"
  assert_contains "${bootstrap}" 'grub-install --target=x86_64-efi'
  assert_contains "${bootstrap}" 'CC="clang"'
  rm -rf "${temp_dir}"
}

test_resolve_stage3_target_maps_supported_enums
test_resolve_stage3_target_rejects_invalid_enum
test_main_dry_run_prints_stage3_build_plan

printf 'PASS: %s\n' "$(basename "$0")"
