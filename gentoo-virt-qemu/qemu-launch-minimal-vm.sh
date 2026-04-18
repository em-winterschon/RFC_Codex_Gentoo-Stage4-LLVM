#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_LAUNCH_TRACE:-0}" == "1" ]]; then
  set -x
fi

# Launch a basic VM with 2x NVMe + 1x NIC passthrough.
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
QEMU_CMD=()

log() {
  printf '[qemu-launch-minimal-vm] %s\n' "$*"
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

build_qemu_cmd() {
  QEMU_CMD=(
    "${QEMU_BIN}"
    -enable-kvm
    -machine "${QEMU_MACHINE}"
    -cpu "${QEMU_CPU}"
    -smp "${QEMU_SMP}"
    -m "${QEMU_MEMORY_MIB}"
    -bios "${EFI_FIRM}"
    -drive "file=${ISO_INST},medium=cdrom"
    -device "vfio-pci,host=${PCI_NETWK}"
    -device "vfio-pci,host=${PCI_NVME0}"
    -device "vfio-pci,host=${PCI_NVME1}"
    -nographic
  )
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
  log 'Launching QEMU VM'
  run_qemu_cmd
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
