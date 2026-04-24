#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_PCI_REMAP_TRACE:-0}" == "1" ]]; then
  set -x
fi

# Bind selected host PCI devices to vfio-pci for passthrough.
# Version: 0.0.2
# MBoard: X12SPL-F
#
# Example device inventory reference:
# lspci -nn | grep -Eiv "ice lake|bridge|sata|c620|audio|vga|dma|system"
# 01:00.0 Ethernet controller [0200]: Intel Corporation I210 Gigabit Network Connection [8086:1533] (rev 03)
# 02:00.0 Ethernet controller [0200]: Intel Corporation I210 Gigabit Network Connection [8086:1533] (rev 03)
# 53:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller SM981/PM981/PM983 [144d:a808]
# 54:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller SM981/PM981/PM983 [144d:a808]
# 8c:00.0 Non-Volatile memory controller [0108]: Intel Corporation PCIe Data Center SSD [8086:0953] (rev 02)
# 8d:00.0 Non-Volatile memory controller [0108]: Intel Corporation PCIe Data Center SSD [8086:0953] (rev 02)
# 90:00.0 Non-Volatile memory controller [0108]: Intel Corporation PCIe Data Center SSD [8086:0953] (rev 02)
# 91:00.0 Non-Volatile memory controller [0108]: Intel Corporation PCIe Data Center SSD [8086:0953] (rev 02)
# c3:00.0 Ethernet controller [0200]: Mellanox Technologies MT42822 BlueField-2 integrated ConnectX-6 Dx network controller [15b3:a2d6] (rev 01)
# c3:00.1 Ethernet controller [0200]: Mellanox Technologies MT42822 BlueField-2 integrated ConnectX-6 Dx network controller [15b3:a2d6] (rev 01)

PCI_NVME0="${PCI_NVME0:-0000:53:00.0}"
PCI_NVME1="${PCI_NVME1:-0000:54:00.0}"
PCI_NETWK="${PCI_NETWK:-0000:02:00.0}"
SYSFS_ROOT="${SYSFS_ROOT:-/sys}"
MODPROBE_BIN="${MODPROBE_BIN:-modprobe}"
LSPCI_BIN="${LSPCI_BIN:-lspci}"
QEMU_PCI_REMAP_DRY_RUN="${QEMU_PCI_REMAP_DRY_RUN:-0}"

log() {
  printf '[qemu-pci-remap] %s\n' "$*"
}

fail() {
  printf '[qemu-pci-remap] ERROR: %s\n' "$*" >&2
  exit 1
}

device_path() {
  printf '%s/bus/pci/devices/%s' "${SYSFS_ROOT}" "$1"
}

iommu_group_path() {
  printf '%s/iommu_group' "$(device_path "$1")"
}

current_driver() {
  local driver_link

  driver_link="$(readlink -f "$(device_path "$1")/driver" 2>/dev/null || true)"
  if [[ -n "${driver_link}" && -e "${driver_link}" ]]; then
    basename "${driver_link}"
  fi
}

has_iommu_group() {
  [[ -L "$(iommu_group_path "$1")" ]]
}

unsafe_noiommu_enabled() {
  local param_path

  param_path="${SYSFS_ROOT}/module/vfio/parameters/enable_unsafe_noiommu_mode"
  [[ -r "${param_path}" ]] && [[ "$(<"${param_path}")" == "Y" ]]
}

write_sysfs() {
  local value="$1"
  local path="$2"

  if [[ "${QEMU_PCI_REMAP_DRY_RUN}" == "1" ]]; then
    log "DRY-RUN: printf '%s' '${value}' > ${path}"
    return 0
  fi

  printf '%s' "${value}" > "${path}"
}

ensure_root() {
  if [[ "${QEMU_PCI_REMAP_DRY_RUN}" == "1" ]]; then
    return 0
  fi

  [[ "${EUID}" -eq 0 ]] || fail 'run as root or set QEMU_PCI_REMAP_DRY_RUN=1'
}

ensure_device_exists() {
  [[ -d "$(device_path "$1")" ]] || fail "PCI device not found: $1"
}

ensure_vfio_available() {
  "${MODPROBE_BIN}" vfio-pci
}

report_bind_failure() {
  local dev="$1"
  local driver_name

  driver_name="$(current_driver "${dev}")"
  log "Bind diagnostics for ${dev}"
  log "current driver: ${driver_name:-<unbound>}"

  if has_iommu_group "${dev}"; then
    log "iommu group: $(readlink -f "$(iommu_group_path "${dev}")")"
  else
    log 'iommu group: <missing>'
  fi

  if unsafe_noiommu_enabled; then
    log 'vfio unsafe no-IOMMU mode: enabled'
  else
    log 'vfio unsafe no-IOMMU mode: disabled'
  fi

  "${LSPCI_BIN}" -s "${dev#0000:}" -knn || true
}

unbind_current_driver() {
  local dev="$1"
  local driver_name

  driver_name="$(current_driver "${dev}")"
  if [[ -z "${driver_name}" ]]; then
    log "${dev} is already unbound"
    return 0
  fi

  if [[ "${driver_name}" == "vfio-pci" ]]; then
    log "${dev} is already bound to vfio-pci"
    return 0
  fi

  log "Unbinding ${dev} from ${driver_name}"
  write_sysfs "${dev}" "$(device_path "${dev}")/driver/unbind"
}

ensure_vfio_attach_preconditions() {
  local dev="$1"

  if has_iommu_group "${dev}"; then
    log "${dev} iommu group: $(basename "$(readlink -f "$(iommu_group_path "${dev}")")")"
    return 0
  fi

  if unsafe_noiommu_enabled; then
    log "${dev} has no IOMMU group; proceeding with unsafe no-IOMMU mode"
    return 0
  fi

  fail "${dev} has no IOMMU group and vfio unsafe no-IOMMU mode is disabled"
}

bind_device_to_vfio() {
  local dev="$1"

  ensure_device_exists "${dev}"
  ensure_vfio_attach_preconditions "${dev}"

  if [[ "$(current_driver "${dev}")" == 'vfio-pci' ]]; then
    log "${dev} is already bound to vfio-pci"
    return 0
  fi

  unbind_current_driver "${dev}"
  log "Binding ${dev} to vfio-pci"
  write_sysfs 'vfio-pci' "$(device_path "${dev}")/driver_override"
  write_sysfs "${dev}" "${SYSFS_ROOT}/bus/pci/drivers_probe"

  if [[ "${QEMU_PCI_REMAP_DRY_RUN}" == "1" ]]; then
    return 0
  fi

  if [[ "$(current_driver "${dev}")" != 'vfio-pci' ]]; then
    report_bind_failure "${dev}"
    fail "vfio-pci bind failed for ${dev}"
  fi
}

main() {
  ensure_root
  ensure_vfio_available

  log "Binding SM981/PM981/PM983 [144d:a808] ${PCI_NVME0}"
  bind_device_to_vfio "${PCI_NVME0}"

  log "Binding SM981/PM981/PM983 [144d:a808] ${PCI_NVME1}"
  bind_device_to_vfio "${PCI_NVME1}"

  log "Binding Ethernet I210 Gigabit Network Connection [8086:1533] ${PCI_NETWK}"
  bind_device_to_vfio "${PCI_NETWK}"

  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
