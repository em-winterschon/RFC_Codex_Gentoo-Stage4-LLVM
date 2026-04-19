#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_LAUNCH_TRACE:-0}" == "1" ]]; then
  set -x
fi

# Launch a basic VM with selected PCI passthrough devices.
# Version: 0.0.3
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

PCI_NVME0="${PCI_NVME0:-53:00.0}"
PCI_NVME1="${PCI_NVME1:-54:00.0}"
PCI_NETWK="${PCI_NETWK:-02:00.0}"
BASE_DIR="${BASE_DIR:-/opt/gentoo-virt-qemu/iso}"
ISO_ORIG="${ISO_ORIG:-${BASE_DIR}/install-amd64-minimal-20260412T164603Z.iso}"
ISO_INST="${ISO_INST:-${BASE_DIR}/gentoo-amd64-minimal.iso}"
EFI_FIRM="${EFI_FIRM:-/usr/share/edk2-ovmf/OVMF_CODE.fd}"
QEMU_BIN="${QEMU_BIN:-/usr/bin/qemu-system-x86_64}"
QEMU_MACHINE="${QEMU_MACHINE:-q35,accel=kvm}"
QEMU_CPU="${QEMU_CPU:-host}"
QEMU_SMP="${QEMU_SMP:-8}"
QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB:-16384}"
QEMU_LAUNCH_DRY_RUN="${QEMU_LAUNCH_DRY_RUN:-0}"
SYSFS_ROOT="${SYSFS_ROOT:-/sys}"
VFIO_DEV_ROOT="${VFIO_DEV_ROOT:-/dev/vfio}"
QEMU_CMD=()

log() {
  printf '[qemu-launch-minimal-vm] %s\n' "$*"
}

fail() {
  printf '[qemu-launch-minimal-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

canonicalize_pci_bdf() {
  local dev="$1"

  if [[ -z "${dev}" ]]; then
    return 0
  fi

  if [[ "${dev}" == 0000:* ]]; then
    printf '%s' "${dev}"
  else
    printf '0000:%s' "${dev}"
  fi
}

device_path() {
  printf '%s/bus/pci/devices/%s' "${SYSFS_ROOT}" "$(canonicalize_pci_bdf "$1")"
}

current_driver() {
  local driver_link

  driver_link="$(readlink -f "$(device_path "$1")/driver" 2>/dev/null || true)"
  if [[ -n "${driver_link}" && -e "${driver_link}" ]]; then
    basename "${driver_link}"
  fi
}

iommu_group_id() {
  local group_link

  group_link="$(readlink -f "$(device_path "$1")/iommu_group" 2>/dev/null || true)"
  if [[ -n "${group_link}" && -e "${group_link}" ]]; then
    basename "${group_link}"
  fi
}

ensure_base_dir() {
  mkdir -p "${BASE_DIR}"
}

prepare_iso() {
  if [[ -f "${ISO_ORIG}" && "${ISO_ORIG}" != "${ISO_INST}" ]]; then
    mv "${ISO_ORIG}" "${ISO_INST}"
  fi

  if [[ ! -f "${ISO_INST}" ]]; then
    printf 'Missing installer ISO at %s\n' "${ISO_INST}" >&2
    return 1
  fi
}

require_vfio_passthrough_ready() {
  local dev="$1"
  local canonical_dev group_id group_dev driver_name

  if [[ -z "${dev}" ]]; then
    return 0
  fi

  canonical_dev="$(canonicalize_pci_bdf "${dev}")"
  [[ -d "$(device_path "${dev}")" ]] || fail "PCI device not found: ${canonical_dev}"

  driver_name="$(current_driver "${dev}")"
  if [[ "${driver_name}" != 'vfio-pci' ]]; then
    fail "${canonical_dev} is not bound to vfio-pci (current driver: ${driver_name:-<unbound>})"
  fi

  group_id="$(iommu_group_id "${dev}")"
  if [[ -z "${group_id}" ]]; then
    fail "${canonical_dev} has no IOMMU group; QEMU vfio-pci cannot use unsafe no-IOMMU bindings here"
  fi

  group_dev="${VFIO_DEV_ROOT}/${group_id}"
  [[ -e "${group_dev}" ]] || fail "${canonical_dev} is in IOMMU group ${group_id}, but ${group_dev} is missing"
}

validate_passthrough_devices() {
  require_vfio_passthrough_ready "${PCI_NETWK}"
  require_vfio_passthrough_ready "${PCI_NVME0}"
  require_vfio_passthrough_ready "${PCI_NVME1}"
}

append_passthrough_device() {
  local dev="$1"

  if [[ -n "${dev}" ]]; then
    QEMU_CMD+=( -device "vfio-pci,host=${dev}" )
  fi
}

build_qemu_cmd() {
  QEMU_CMD=(
    "${QEMU_BIN}"
    -enable-kvm
    -machine "${QEMU_MACHINE}"
    -cpu "${QEMU_CPU}"
    -smp "${QEMU_SMP}"
    -m "${QEMU_MEMORY_MIB}"
    -bios "${EFI_FIRM}"
    -drive "file=${ISO_INST},media=cdrom"
  )

  append_passthrough_device "${PCI_NETWK}"
  append_passthrough_device "${PCI_NVME0}"
  append_passthrough_device "${PCI_NVME1}"

  QEMU_CMD+=( -nographic )
}

print_qemu_cmd() {
  printf '%q ' "${QEMU_CMD[@]}"
  printf '\n'
}

run_qemu_cmd() {
  build_qemu_cmd

  if [[ "${QEMU_LAUNCH_DRY_RUN}" == "1" ]]; then
    print_qemu_cmd
    return 0
  fi

  "${QEMU_CMD[@]}"
}

main() {
  ensure_base_dir
  prepare_iso
  validate_passthrough_devices
  log 'Launching QEMU VM'
  run_qemu_cmd
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
