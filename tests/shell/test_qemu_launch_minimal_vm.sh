#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../gentoo-virt-qemu/qemu-launch-minimal-vm.sh
source "${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-minimal-vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_exists() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

test_prepare_iso_moves_original() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  BASE_DIR="${temp_dir}"
  ISO_ORIG="${temp_dir}/orig.iso"
  ISO_INST="${temp_dir}/dest.iso"
  : >"${ISO_ORIG}"

  prepare_iso

  assert_file_exists "${ISO_INST}"
  assert_not_exists "${ISO_ORIG}"
  rm -rf "${temp_dir}"
}

test_prepare_iso_accepts_existing_installer_iso() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  BASE_DIR="${temp_dir}"
  ISO_ORIG="${temp_dir}/missing.iso"
  ISO_INST="${temp_dir}/gentoo.iso"
  : >"${ISO_INST}"

  prepare_iso

  assert_file_exists "${ISO_INST}"
  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_uses_configured_passthrough_devices() {
  PCI_NETWK="11:22.3"
  PCI_NVME0="44:55.6"
  PCI_NVME1="77:88.9"
  ISO_INST="/tmp/test.iso"
  EFI_FIRM="/tmp/OVMF_CODE.fd"
  QEMU_BIN="/usr/bin/qemu-system-x86_64"

  build_qemu_cmd

  local rendered
  rendered="${QEMU_CMD[*]}"
  assert_contains "${rendered}" "vfio-pci,host=${PCI_NETWK}"
  assert_contains "${rendered}" "vfio-pci,host=${PCI_NVME0}"
  assert_contains "${rendered}" "vfio-pci,host=${PCI_NVME1}"
  assert_contains "${rendered}" "file=${ISO_INST},medium=cdrom"
}

test_main_dry_run_prints_command() {
  local temp_dir output
  temp_dir="$(mktemp -d)"

  BASE_DIR="${temp_dir}"
  ISO_ORIG="${temp_dir}/missing.iso"
  ISO_INST="${temp_dir}/gentoo.iso"
  : >"${ISO_INST}"
  QEMU_LAUNCH_DRY_RUN=1

  output="$(main 2>&1)"

  assert_contains "${output}" "Launching QEMU VM"
  assert_contains "${output}" "qemu-system-x86_64"
  assert_contains "${output}" "vfio-pci,host=${PCI_NETWK}"
  assert_contains "${output}" "[COMPLETE]"
  rm -rf "${temp_dir}"
}

test_prepare_iso_moves_original
test_prepare_iso_accepts_existing_installer_iso
test_build_qemu_cmd_uses_configured_passthrough_devices
test_main_dry_run_prints_command

printf 'PASS: %s\n' "$(basename "$0")"
