#!/usr/bin/env bash
set -euo pipefail

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

# Passthrough both Samsung NVMe devices to VFIO for test-vm.
echo "VFIO-PCI: BINDING SM981/PM981/PM983 [144d:a808] 0000:53:00.0"
echo 0000:53:00.0 > /sys/bus/pci/devices/0000:53:00.0/driver/unbind || exit 21
echo 0000:53:00.0 > /sys/bus/pci/drivers/vfio-pci/bind || exit 31

echo "VFIO-PCI: BINDING SM981/PM981/PM983 [144d:a808] 0000:54:00.0"
echo 0000:54:00.0 > /sys/bus/pci/devices/0000:54:00.0/driver/unbind || exit 22
echo 0000:54:00.0 > /sys/bus/pci/drivers/vfio-pci/bind || exit 32

# Alternate method without initial unbinding:
# echo 0000:53:00.0 > /sys/bus/pci/drivers/vfio-pci/new_id
# echo 0000:54:00.0 > /sys/bus/pci/drivers/vfio-pci/new_id

# Passthrough the second 1GbE i210 NIC to VFIO for test-vm.
# Device: eno2, MAC: 3c:ec:ef:dc:c3:13
echo "VFIO-PCI: BINDING ETHERNET I210 Gigabit Network Connection [8086:1533] 0000:02:00.0"
echo 0000:02:00.0 > /sys/bus/pci/devices/0000:02:00.0/driver/unbind || exit 23
echo 0000:02:00.0 > /sys/bus/pci/drivers/vfio-pci/bind || exit 33

echo "[COMPLETE]"
