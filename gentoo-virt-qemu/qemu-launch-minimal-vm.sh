#!/usr/bin/env bash
set -exo pipefail

# Launch a basic VM with 2x NVMe + 1x NIC passthrough.
# Version: 0.0.1
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

# PCIe 2x NVMe + 1x 1GbE NIC
PCI_NVME0="53:00.0"
PCI_NVME1="54:00.0"
PCI_NETWK="02:00.0"

# Download the Gentoo minimal AutoBuild installer ISO ahead of time.
# Latest ISO URL can be grepped from:
# https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-install-amd64-minimal.txt
# Example:
# wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20260412T164603Z/install-amd64-minimal-20260412T164603Z.iso

BASE_DIR="/opt/gentoo-virt-qemu/iso"
ISO_ORIG="${BASE_DIR}/install-amd64-minimal-20260412T164603Z.iso"
ISO_INST="${BASE_DIR}/gentoo-amd64-minimal.iso"
EFI_FIRM="/usr/share/edk2-ovmf/OVMF_CODE.fd"
test -d "${BASE_DIR}" || mkdir -p "${BASE_DIR}"
mv "${ISO_ORIG}" "${ISO_INST}" || true

echo "[STATUS]: Launching Qemu VM"
/usr/bin/qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,accel=kvm \
    -cpu host \
    -smp 8 \
    -m 16384 \
    -bios "${EFI_FIRM}" \
    -drive file="${ISO_INST}",medium=cdrom \
    -device vfio-pci,host="${PCI_NETWK}" \
    -device vfio-pci,host="${PCI_NVME0}" \
    -device vfio-pci,host="${PCI_NVME1}" \
    -nographic || exit 44

echo "[COMPLETE]"
