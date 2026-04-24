#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../gentoo-virt-qemu/qemu-pci-remap.sh
source "${REPO_ROOT}/gentoo-virt-qemu/qemu-pci-remap.sh"

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
  local expected="$1"
  local actual="$2"

  [[ "${expected}" == "${actual}" ]] || fail "expected '${expected}', got '${actual}'"
}

test_current_driver_returns_empty_for_unbound_device() (
  local temp_dir dev driver_name

  temp_dir="$(mktemp -d)"
  dev='0000:53:00.0'
  SYSFS_ROOT="${temp_dir}/sys"
  mkdir -p "$(device_path "${dev}")"

  driver_name="$(current_driver "${dev}")"
  [[ -z "${driver_name}" ]] || fail 'expected empty driver name for unbound device'
  rm -rf "${temp_dir}"
)

test_bind_refuses_missing_iommu_group_without_unsafe_mode() (
  local temp_dir dev output

  temp_dir="$(mktemp -d)"
  dev='0000:53:00.0'
  SYSFS_ROOT="${temp_dir}/sys"
  mkdir -p "$(device_path "${dev}")" "${SYSFS_ROOT}/module/vfio/parameters" "${SYSFS_ROOT}/bus/pci"
  : > "${SYSFS_ROOT}/bus/pci/drivers_probe"
  printf 'N' > "${SYSFS_ROOT}/module/vfio/parameters/enable_unsafe_noiommu_mode"

  if output="$(bind_device_to_vfio "${dev}" 2>&1)"; then
    fail 'expected bind_device_to_vfio to fail without an IOMMU group'
  fi

  assert_contains "${output}" 'has no IOMMU group'
  rm -rf "${temp_dir}"
)

test_bind_device_uses_driver_override_and_probe() (
  local temp_dir dev device_root rendered
  local -a recorded_writes=()

  temp_dir="$(mktemp -d)"
  dev='0000:53:00.0'
  SYSFS_ROOT="${temp_dir}/sys"
  device_root="$(device_path "${dev}")"

  mkdir -p \
    "${device_root}" \
    "${SYSFS_ROOT}/bus/pci/drivers/nvme" \
    "${SYSFS_ROOT}/bus/pci/drivers/vfio-pci" \
    "${SYSFS_ROOT}/kernel/iommu_groups/7" \
    "${SYSFS_ROOT}/module/vfio/parameters" \
    "${SYSFS_ROOT}/bus/pci"
  : > "${SYSFS_ROOT}/bus/pci/drivers_probe"
  printf 'N' > "${SYSFS_ROOT}/module/vfio/parameters/enable_unsafe_noiommu_mode"
  ln -s "${SYSFS_ROOT}/bus/pci/drivers/nvme" "${device_root}/driver"
  ln -s "${SYSFS_ROOT}/kernel/iommu_groups/7" "${device_root}/iommu_group"

  write_sysfs() {
    local value="$1"
    local path="$2"

    recorded_writes+=("${value}|${path}")

    if [[ "${path}" == "${device_root}/driver/unbind" ]]; then
      rm -f "${device_root}/driver"
      return 0
    fi

    mkdir -p "$(dirname "${path}")"
    printf '%s' "${value}" > "${path}"

    if [[ "${path}" == "${SYSFS_ROOT}/bus/pci/drivers_probe" ]]; then
      ln -s "${SYSFS_ROOT}/bus/pci/drivers/vfio-pci" "${device_root}/driver"
    fi
  }

  bind_device_to_vfio "${dev}"

  rendered="$(printf '%s\n' "${recorded_writes[@]}")"
  assert_equals 'vfio-pci' "$(current_driver "${dev}")"
  assert_contains "${rendered}" "${dev}|${device_root}/driver/unbind"
  assert_contains "${rendered}" "vfio-pci|${device_root}/driver_override"
  assert_contains "${rendered}" "${dev}|${SYSFS_ROOT}/bus/pci/drivers_probe"
  rm -rf "${temp_dir}"
)

test_bind_is_noop_for_device_already_on_vfio() (
  local temp_dir dev device_root

  temp_dir="$(mktemp -d)"
  dev='0000:53:00.0'
  SYSFS_ROOT="${temp_dir}/sys"
  device_root="$(device_path "${dev}")"

  mkdir -p \
    "${device_root}" \
    "${SYSFS_ROOT}/bus/pci/drivers/vfio-pci" \
    "${SYSFS_ROOT}/kernel/iommu_groups/9" \
    "${SYSFS_ROOT}/module/vfio/parameters"
  printf 'N' > "${SYSFS_ROOT}/module/vfio/parameters/enable_unsafe_noiommu_mode"
  ln -s "${SYSFS_ROOT}/bus/pci/drivers/vfio-pci" "${device_root}/driver"
  ln -s "${SYSFS_ROOT}/kernel/iommu_groups/9" "${device_root}/iommu_group"

  write_sysfs() {
    fail 'write_sysfs should not be called for a device already bound to vfio-pci'
  }

  bind_device_to_vfio "${dev}"
  rm -rf "${temp_dir}"
)

test_current_driver_returns_empty_for_unbound_device
test_bind_refuses_missing_iommu_group_without_unsafe_mode
test_bind_device_uses_driver_override_and_probe
test_bind_is_noop_for_device_already_on_vfio

printf 'PASS: %s\n' "$(basename "$0")"
