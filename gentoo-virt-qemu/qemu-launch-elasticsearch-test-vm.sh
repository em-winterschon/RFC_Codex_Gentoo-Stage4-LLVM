#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INSTANCE_NAME="${INSTANCE_NAME:-elasticsearch-test}"
QEMU_VM_DIR="${QEMU_VM_DIR:-/opt/gentoo-netboot/path-b/vms/elasticsearch-test}"
QEMU_ROOTDISK="${QEMU_ROOTDISK:-${QEMU_VM_DIR}/elasticsearch-test-root.qcow2}"
QEMU_ROOTDISK_SIZE="${QEMU_ROOTDISK_SIZE:-256G}"
QEMU_BIN="${QEMU_BIN:-/usr/bin/qemu-system-x86_64}"
QEMU_PATHB_BOOT_MODE="${QEMU_PATHB_BOOT_MODE:-direct-kernel}"
QEMU_DIRECT_KERNEL="${QEMU_DIRECT_KERNEL:-/var/lib/netboot/path-b/artifacts/gentoo-installer/vmlinuz}"
QEMU_DIRECT_INITRD="${QEMU_DIRECT_INITRD:-/var/lib/netboot/path-b/artifacts/gentoo-installer/initramfs.img}"
QEMU_DIRECT_ROOTFS_URL="${QEMU_DIRECT_ROOTFS_URL:-http://10.9.8.108:8080/g/rootfs.img}"
QEMU_DIRECT_GUEST_IP="${QEMU_DIRECT_GUEST_IP:-10.9.8.91}"
QEMU_DIRECT_GATEWAY="${QEMU_DIRECT_GATEWAY:-10.9.8.1}"
QEMU_DIRECT_NETMASK="${QEMU_DIRECT_NETMASK:-255.255.255.0}"
QEMU_DIRECT_INTERFACE="${QEMU_DIRECT_INTERFACE:-eth0}"
QEMU_DIRECT_HOSTNAME="${QEMU_DIRECT_HOSTNAME:-elasticsearch-test}"
QEMU_DIRECT_APPEND="${QEMU_DIRECT_APPEND:-console=tty0 console=ttyS0,115200 ip=${QEMU_DIRECT_GUEST_IP}::${QEMU_DIRECT_GATEWAY}:${QEMU_DIRECT_NETMASK}:${QEMU_DIRECT_HOSTNAME}:${QEMU_DIRECT_INTERFACE}:none rd.neednet=1 rd.live.image root=live:${QEMU_DIRECT_ROOTFS_URL}}"
QEMU_SMP="${QEMU_SMP:-16}"
QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB:-65536}"
QEMU_MAC_ADDRESS="${QEMU_MAC_ADDRESS:-52:54:00:12:34:91}"
QEMU_TAP_IFNAME="${QEMU_TAP_IFNAME:-tap-es-test}"
QEMU_BRIDGE_IFNAME="${QEMU_BRIDGE_IFNAME:-br-pathb}"
QEMU_SERIAL_MODE="${QEMU_SERIAL_MODE:-telnet}"
QEMU_SERIAL_HOST="${QEMU_SERIAL_HOST:-127.0.0.1}"
QEMU_SERIAL_PORT="${QEMU_SERIAL_PORT:-5005}"
QEMU_MEMORY_DRIVES_FILE="${QEMU_MEMORY_DRIVES_FILE:-}"
QEMU_CREATE_ROOTDISK="${QEMU_CREATE_ROOTDISK:-1}"
QEMU_RESET_ROOTDISK="${QEMU_RESET_ROOTDISK:-0}"
QEMU_LAUNCH_DRY_RUN="${QEMU_LAUNCH_DRY_RUN:-0}"

log() {
  printf '[qemu-launch-elasticsearch-test-vm] %s\n' "$*"
}

fail() {
  printf '[qemu-launch-elasticsearch-test-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

prepare_rootdisk() {
  mkdir -p "$(dirname "${QEMU_ROOTDISK}")"

  if [[ "${QEMU_RESET_ROOTDISK}" == '1' && "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    log "Dry-run: would remove root disk ${QEMU_ROOTDISK}"
  elif [[ "${QEMU_RESET_ROOTDISK}" == '1' ]]; then
    rm -f "${QEMU_ROOTDISK}"
  fi

  if [[ ! -f "${QEMU_ROOTDISK}" ]]; then
    [[ "${QEMU_CREATE_ROOTDISK}" == '1' ]] || fail "QEMU_ROOTDISK is missing: ${QEMU_ROOTDISK}"
    if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
      log "Dry-run: would create root disk ${QEMU_ROOTDISK} (${QEMU_ROOTDISK_SIZE})"
      return 0
    fi
    command -v qemu-img >/dev/null 2>&1 || fail 'missing required command: qemu-img'
    log "Creating root disk ${QEMU_ROOTDISK} (${QEMU_ROOTDISK_SIZE})"
    qemu-img create -f qcow2 "${QEMU_ROOTDISK}" "${QEMU_ROOTDISK_SIZE}" >/dev/null
  fi
}

main() {
  prepare_rootdisk

  export \
    INSTANCE_NAME \
    QEMU_VM_DIR \
    QEMU_ROOTDISK \
    QEMU_BIN \
    QEMU_PATHB_BOOT_MODE \
    QEMU_DIRECT_KERNEL \
    QEMU_DIRECT_INITRD \
    QEMU_DIRECT_ROOTFS_URL \
    QEMU_DIRECT_APPEND \
    QEMU_SMP \
    QEMU_MEMORY_MIB \
    QEMU_MAC_ADDRESS \
    QEMU_TAP_IFNAME \
    QEMU_BRIDGE_IFNAME \
    QEMU_SERIAL_MODE \
    QEMU_SERIAL_HOST \
    QEMU_SERIAL_PORT \
    QEMU_MEMORY_DRIVES_FILE \
    QEMU_LAUNCH_DRY_RUN

  exec "${SCRIPT_DIR}/qemu-launch-pathb-vm.sh" "$@"
}

main "$@"
