#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_SCRIPT="${CREATE_SCRIPT:-${SCRIPT_DIR}/proxmox-create-stage4-service-vm.sh}"

export PVE_HOST="${PVE_HOST:-hasslehoff}"
export VMID="${VMID:-1094}"
export VM_NAME="${VM_NAME:-vm-workstation-nscde-gpu01}"
export VM_MEMORY_MIB="${VM_MEMORY_MIB:-24576}"
export VM_CORES="${VM_CORES:-8}"
export VM_BRIDGE="${VM_BRIDGE:-vmbr0}"
export VM_MAC="${VM_MAC:-52:54:00:99:10:94}"
export VM_IP_CIDR="${VM_IP_CIDR:-172.16.99.94/24}"
export VM_GATEWAY="${VM_GATEWAY:-172.16.99.1}"
export VM_DNS="${VM_DNS:-9.9.9.9}"
export VM_SEARCH_DOMAIN="${VM_SEARCH_DOMAIN:-rfc1918.host}"
export VM_STORAGE="${VM_STORAGE:-local-zfs}"
export SOURCE_QCOW="${SOURCE_QCOW:-/var/lib/vz/template/cache/vm-workstation-nscde.qcow2}"
export NETBOX_ROLE="${NETBOX_ROLE:-workstation-nscde}"
export VM_DESCRIPTION="${VM_DESCRIPTION:-Stage4 workstation VM; stage5_role=workstation-nscde; gpu=Quadro-K1200; network=qlogic-lacp-bridge-fallback}"
export VM_CPU="${VM_CPU:-host}"
export VM_BIOS="${VM_BIOS:-ovmf}"
export VM_ENABLE_EFIDISK="${VM_ENABLE_EFIDISK:-auto}"
export VM_DISK_SIZE="${VM_DISK_SIZE:-160G}"
export VM_SERIAL0="${VM_SERIAL0:-socket}"
export VM_VGA="${VM_VGA:-qxl}"
export PROXMOX_START_AFTER_CREATE="${PROXMOX_START_AFTER_CREATE:-0}"

qlogic_bridge="${VM_QLOGIC_BRIDGE:-vmbr-qlogic0}"
qlogic_vlan_a="${VM_QLOGIC_VLAN_A:-1098}"
qlogic_vlan_b="${VM_QLOGIC_VLAN_B:-1099}"
qlogic_mac_a="${VM_QLOGIC_MAC_A:-52:54:00:99:11:94}"
qlogic_mac_b="${VM_QLOGIC_MAC_B:-52:54:00:99:12:94}"

export VM_EXTRA_NETS="${VM_EXTRA_NETS:-net1=virtio=${qlogic_mac_a},bridge=${qlogic_bridge},tag=${qlogic_vlan_a}
net2=virtio=${qlogic_mac_b},bridge=${qlogic_bridge},tag=${qlogic_vlan_b}}"
export VM_HOSTPCI_DEVICES="${VM_HOSTPCI_DEVICES:-hostpci0=0000:01:00.0,pcie=1
hostpci1=0000:01:00.1,pcie=1}"

exec bash "${CREATE_SCRIPT}" "$@"
