#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-routeros-chr-pathb}"
CHR_RAW_IMAGE="${CHR_RAW_IMAGE:-/opt/routeros/images/chr-7.21.4.img}"
CHR_DISK="${CHR_DISK:-/opt/routeros/routeros-chr-7.21.4-pathb-fresh.qcow2}"
CHR_STATE_DISK="${CHR_STATE_DISK:-/opt/routeros/routeros-lab-state-pathb-fresh.qcow2}"
BACKUP_DIR="${BACKUP_DIR:-/opt/routeros/backups}"
FRESH_DISK="${FRESH_DISK:-false}"
LAN_BRIDGE="${LAN_BRIDGE:-br-pathb}"
LAN_TAP="${LAN_TAP:-tap-ros}"
WAN_BRIDGE="${WAN_BRIDGE:-br-ros-wan}"
WAN_TAP="${WAN_TAP:-tap-ros-wan}"
WAN_PHYS_IF="${WAN_PHYS_IF:-eno2}"
SERIAL_HOST="${SERIAL_HOST:-127.0.0.1}"
SERIAL_PORT="${SERIAL_PORT:-5001}"
ROUTEROS_RAM_MB="${ROUTEROS_RAM_MB:-2048}"
ROUTEROS_CPUS="${ROUTEROS_CPUS:-2}"
LAN_MAC="${LAN_MAC:-52:54:00:90:00:01}"
WAN_MAC="${WAN_MAC:-52:54:00:90:00:02}"

die() {
  printf '[qemu-launch-routeros-pathb-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" > /dev/null 2>&1 || die "missing required command: $1"
}

bool_true() {
  case "${1,,}" in
  1 | true | yes | y | on) return 0 ;;
  *) return 1 ;;
  esac
}

ensure_tap() {
  local tap_if=$1
  local bridge_if=$2
  if ! ip link show "${tap_if}" > /dev/null 2>&1; then
    ip tuntap add dev "${tap_if}" mode tap
  fi
  ip link set "${tap_if}" up
  ip link set "${tap_if}" master "${bridge_if}"
}

require_cmd ip
require_cmd qemu-img
require_cmd qemu-system-x86_64

if pgrep -af "qemu-system-x86_64 .*${VM_NAME}" > /dev/null; then
  die "VM appears to already be running: ${VM_NAME}"
fi

ip link show "${LAN_BRIDGE}" > /dev/null 2>&1 || die "LAN bridge not found: ${LAN_BRIDGE}"

mkdir -p "$(dirname "${CHR_DISK}")" "${BACKUP_DIR}"
if bool_true "${FRESH_DISK}" || [[ ! -f "${CHR_DISK}" ]]; then
  [[ -f "${CHR_RAW_IMAGE}" ]] || die "raw CHR image not found: ${CHR_RAW_IMAGE}"
  stamp="$(date +%Y%m%d-%H%M%S)"
  if [[ -f "${CHR_DISK}" ]]; then
    mv "${CHR_DISK}" "${BACKUP_DIR}/$(basename "${CHR_DISK}").${stamp}.bak"
  fi
  if [[ -f "${CHR_STATE_DISK}" ]]; then
    mv "${CHR_STATE_DISK}" "${BACKUP_DIR}/$(basename "${CHR_STATE_DISK}").${stamp}.bak"
  fi
  qemu-img convert -f raw -O qcow2 "${CHR_RAW_IMAGE}" "${CHR_DISK}"
  qemu-img create -f qcow2 "${CHR_STATE_DISK}" 16M > /dev/null
  chmod 0640 "${CHR_DISK}" "${CHR_STATE_DISK}"
fi

if ! ip link show "${WAN_BRIDGE}" > /dev/null 2>&1; then
  ip link add "${WAN_BRIDGE}" type bridge
fi
ip addr flush dev "${WAN_BRIDGE}" || true
ip link set "${WAN_BRIDGE}" up

if [[ -n "${WAN_PHYS_IF}" ]]; then
  ip link show "${WAN_PHYS_IF}" > /dev/null 2>&1 || die "WAN physical interface not found: ${WAN_PHYS_IF}"
  ip link set "${WAN_PHYS_IF}" up
  ip link set "${WAN_PHYS_IF}" master "${WAN_BRIDGE}"
fi

ensure_tap "${LAN_TAP}" "${LAN_BRIDGE}"
ensure_tap "${WAN_TAP}" "${WAN_BRIDGE}"

exec qemu-system-x86_64 \
  -name "${VM_NAME}" \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -m "${ROUTEROS_RAM_MB}" \
  -smp "${ROUTEROS_CPUS}" \
  -drive if=virtio,file="${CHR_DISK}",format=qcow2 \
  -drive if=virtio,file="${CHR_STATE_DISK}",format=qcow2 \
  -netdev tap,id=net0,ifname="${LAN_TAP}",script=no,downscript=no \
  -device virtio-net-pci,netdev=net0,mac="${LAN_MAC}" \
  -netdev tap,id=net1,ifname="${WAN_TAP}",script=no,downscript=no \
  -device virtio-net-pci,netdev=net1,mac="${WAN_MAC}" \
  -serial telnet:"${SERIAL_HOST}":"${SERIAL_PORT}",server=on,wait=off \
  -display none \
  -daemonize
