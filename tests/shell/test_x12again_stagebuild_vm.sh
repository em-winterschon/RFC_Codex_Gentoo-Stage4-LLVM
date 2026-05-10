#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WRAPPER="${REPO_ROOT}/gentoo-virt-qemu/x12again-stagebuild-vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}'"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

[[ -x "${WRAPPER}" ]] || fail "missing executable ${WRAPPER}"

output="$("${WRAPPER}" --print-env)"
assert_contains "${output}" "X12_STAGEBUILD_INSTANCE_NAME=x12again-stagebuild-k10"
assert_contains "${output}" "X12_STAGEBUILD_INSTANCE_DIR=/srv/vm-images/stagebuild-instances/x12again-stagebuild-k10"
assert_contains "${output}" "X12_STAGEBUILD_STAGING_DIR=/var/lib/netboot/staging/path-b/x12again-stagebuild-k10"
assert_contains "${output}" "STAGE3_HOST_DISTFILES_DIR=/srv/build-cache/distfiles"
assert_contains "${output}" "STAGE3_HOST_BINPKG_DIR=/srv/build-cache/binpkgs"
assert_contains "${output}" "STAGE3_GUEST_DISTFILES_DIR=/srv/build-cache/distfiles"
assert_contains "${output}" "STAGE3_GUEST_BINPKG_DIR=/srv/build-cache/binpkgs"
assert_contains "${output}" "QCOW_SIZE_GIB=512"
assert_contains "${output}" "QEMU_SMP=64"
assert_contains "${output}" "QEMU_MEMORY_MIB=262144"
assert_contains "${output}" "QEMU_ATTACH_HOST_DISKS=0"
assert_contains "${output}" "X12_STAGEBUILD_MAKEOPTS=-j56 -l64"
assert_contains "${output}" "X12_STAGEBUILD_EMERGE_DEFAULT_OPTS=--buildpkg=y"
assert_contains "${output}" "SSH_READY_PORT=2230"
assert_contains "${output}" "QEMU_SERIAL_TCP=127.0.0.1:4566,server=on,wait=off,telnet=on"

assert_file_contains "${WRAPPER}" "build-stage3-qcow.sh"
assert_file_contains "${WRAPPER}" "qemu-launch-stage3-vm.sh"
assert_file_contains "${WRAPPER}" "X12_STAGEBUILD_DRY_RUN"
assert_file_contains "${WRAPPER}" "QEMU_ATTACH_HOST_DISKS"
assert_file_contains "${WRAPPER}" "STAGE3_HOST_BINPKG_DIR"
assert_file_contains "${WRAPPER}" "LAUNCHER_LOG_ENABLE"
assert_file_contains "${WRAPPER}" "buildpkg -binpkg-request-signature"
assert_file_contains "${WRAPPER}" "MAKEOPTS="
assert_file_contains "${WRAPPER}" "EMERGE_DEFAULT_OPTS="
assert_file_contains "${WRAPPER}" "PKGDIR="
assert_file_contains "${WRAPPER}" "DISTDIR="

printf 'PASS: %s\n' "$(basename "$0")"
