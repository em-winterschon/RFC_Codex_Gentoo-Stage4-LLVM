#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-minimal-vm.sh"

# shellcheck source=../../gentoo-virt-qemu/qemu-launch-minimal-vm.sh
source "${LAUNCH_SCRIPT}"

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

setup_vfio_ready_device() {
  local temp_root="$1"
  local dev="$2"
  local group_id="$3"
  local canonical_dev driver_root device_root group_root vfio_root

  canonical_dev="$(canonicalize_pci_bdf "${dev}")"
  driver_root="${temp_root}/sys/bus/pci/drivers/vfio-pci"
  device_root="${temp_root}/sys/bus/pci/devices/${canonical_dev}"
  group_root="${temp_root}/sys/kernel/iommu_groups/${group_id}"
  vfio_root="${temp_root}/dev/vfio"

  mkdir -p "${driver_root}" "${device_root}" "${group_root}" "${vfio_root}"
  ln -s "${driver_root}" "${device_root}/driver"
  ln -s "${group_root}" "${device_root}/iommu_group"
  : >"${vfio_root}/${group_id}"
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
  assert_contains "${rendered}" "file=${ISO_INST},media=cdrom"
}

test_build_qemu_cmd_skips_blank_passthrough_devices() {
  PCI_NETWK=''
  PCI_NVME0='44:55.6'
  PCI_NVME1=''
  ISO_INST='/tmp/test.iso'
  EFI_FIRM='/tmp/OVMF_CODE.fd'
  QEMU_BIN='/usr/bin/qemu-system-x86_64'

  build_qemu_cmd

  local rendered
  rendered="${QEMU_CMD[*]}"
  assert_contains "${rendered}" "vfio-pci,host=${PCI_NVME0}"
  [[ "${rendered}" != *"vfio-pci,host=11:22.3"* ]] || fail 'unexpected stale NIC passthrough argument'
  [[ "${rendered}" != *"vfio-pci,host=${PCI_NVME1}"* ]] || fail 'unexpected blank NVMe passthrough argument'
}

test_blank_env_overrides_defaults_in_fresh_process() {
  local output

  output="$(bash -lc 'PCI_NETWK= PCI_NVME1= source "$1"; printf "NET=%s NVME1=%s\n" "$PCI_NETWK" "$PCI_NVME1"' _ "${LAUNCH_SCRIPT}")"
  assert_contains "${output}" 'NET= NVME1='
}

test_validate_passthrough_devices_rejects_missing_iommu_group() {
  local temp_dir output
  temp_dir="$(mktemp -d)"

  SYSFS_ROOT="${temp_dir}/sys"
  VFIO_DEV_ROOT="${temp_dir}/dev/vfio"
  PCI_NETWK='02:00.0'
  PCI_NVME0=''
  PCI_NVME1=''
  mkdir -p "$(device_path "${PCI_NETWK}")" "${SYSFS_ROOT}/bus/pci/drivers/vfio-pci" "${VFIO_DEV_ROOT}"
  ln -s "${SYSFS_ROOT}/bus/pci/drivers/vfio-pci" "$(device_path "${PCI_NETWK}")/driver"

  if output="$(validate_passthrough_devices 2>&1)"; then
    fail 'expected validate_passthrough_devices to fail without an IOMMU group'
  fi

  assert_contains "${output}" 'has no IOMMU group'
  rm -rf "${temp_dir}"
}

test_main_dry_run_prints_command() {
  local temp_dir output
  temp_dir="$(mktemp -d)"

  BASE_DIR="${temp_dir}"
  ISO_ORIG="${temp_dir}/missing.iso"
  ISO_INST="${temp_dir}/gentoo.iso"
  SYSFS_ROOT="${temp_dir}/sys"
  VFIO_DEV_ROOT="${temp_dir}/dev/vfio"
  PCI_NETWK='02:00.0'
  PCI_NVME0='53:00.0'
  PCI_NVME1=''
  QEMU_LAUNCH_DRY_RUN=1
  : >"${ISO_INST}"
  setup_vfio_ready_device "${temp_dir}" "${PCI_NETWK}" '2'
  setup_vfio_ready_device "${temp_dir}" "${PCI_NVME0}" '53'

  output="$(main 2>&1)"

  assert_contains "${output}" 'Launching QEMU VM'
  assert_contains "${output}" 'qemu-system-x86_64'
  assert_contains "${output}" "vfio-pci,host=${PCI_NETWK}"
  assert_contains "${output}" "vfio-pci,host=${PCI_NVME0}"
  assert_contains "${output}" "file=${ISO_INST},media=cdrom"
  assert_contains "${output}" '[COMPLETE]'
  rm -rf "${temp_dir}"
}

test_prepare_iso_moves_original
test_prepare_iso_accepts_existing_installer_iso
test_build_qemu_cmd_uses_configured_passthrough_devices
test_build_qemu_cmd_skips_blank_passthrough_devices
test_blank_env_overrides_defaults_in_fresh_process
test_validate_passthrough_devices_rejects_missing_iommu_group
test_main_dry_run_prints_command

printf 'PASS: %s\n' "$(basename "$0")"
