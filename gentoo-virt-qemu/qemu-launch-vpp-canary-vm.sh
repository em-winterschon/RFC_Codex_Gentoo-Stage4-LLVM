#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_LAUNCH_TRACE:-0}" == '1' ]]; then
  set -x
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH_SCRIPT="${LAUNCH_SCRIPT:-${SCRIPT_DIR}/qemu-launch-cloudinit-vm.sh}"
INSTANCE_NAME="${INSTANCE_NAME:-vpp-canary}"
VPP_CANARY_BASE_DIR="${VPP_CANARY_BASE_DIR:-/opt/gentoo-virt-qemu/vpp-canary}"
BASE_DIR="${BASE_DIR:-${VPP_CANARY_BASE_DIR}}"
IMAGE_CACHE_DIR="${IMAGE_CACHE_DIR:-${BASE_DIR}/images}"
STATE_DIR="${STATE_DIR:-${BASE_DIR}/state/${INSTANCE_NAME}}"
SEED_DIR="${SEED_DIR:-${STATE_DIR}/seed}"
SEED_ISO="${SEED_ISO:-${STATE_DIR}/${INSTANCE_NAME}-seed.iso}"
CLOUD_IMAGE_URL="${CLOUD_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
OVERLAY_IMAGE="${OVERLAY_IMAGE:-${STATE_DIR}/${INSTANCE_NAME}.qcow2}"
SSH_FORWARD_HOST="${SSH_FORWARD_HOST:-127.0.0.1}"
SSH_FORWARD_PORT="${SSH_FORWARD_PORT:-2224}"
QEMU_SMP="${QEMU_SMP:-4}"
QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB:-4096}"
QEMU_DISPLAY_MODE="${QEMU_DISPLAY_MODE:-none}"
QEMU_SERIAL_MODE="${QEMU_SERIAL_MODE:-file}"
QEMU_SERIAL_FILE="${QEMU_SERIAL_FILE:-${STATE_DIR}/${INSTANCE_NAME}.serial.log}"
QEMU_DAEMONIZE="${QEMU_DAEMONIZE:-1}"
WAIT_FOR_SSH="${WAIT_FOR_SSH:-1}"
SSH_WAIT_TIMEOUT="${SSH_WAIT_TIMEOUT:-480}"
ATTACH_HOST_DISKS="${ATTACH_HOST_DISKS:-0}"
VPP_CANARY_ENABLE_OVS_TAP="${VPP_CANARY_ENABLE_OVS_TAP:-1}"
VPP_CANARY_OVS_BRIDGE="${VPP_CANARY_OVS_BRIDGE:-br_ovs0}"
VPP_CANARY_TAP_NAME="${VPP_CANARY_TAP_NAME:-tap-vppcan0}"
VPP_CANARY_APPEND_FILE="${VPP_CANARY_APPEND_FILE:-${STATE_DIR}/vpp-canary-cloud-init.yml}"
VPP_CANARY_AF_PACKET_SCRIPT="${VPP_CANARY_AF_PACKET_SCRIPT:-${SCRIPT_DIR}/vpp-canary-afpacket.sh}"
VPP_CANARY_AF_PACKET_SERVICE="${VPP_CANARY_AF_PACKET_SERVICE:-${SCRIPT_DIR}/vpp-canary-afpacket.service}"
VPP_CANARY_STARTUP_CONF="${VPP_CANARY_STARTUP_CONF:-${SCRIPT_DIR}/vpp-canary-startup.conf}"
VPP_CANARY_NETWORK_CONFIG="${VPP_CANARY_NETWORK_CONFIG:-${SCRIPT_DIR}/vpp-canary-network-config.yaml}"
QEMU_SECOND_NETDEV_ID="${QEMU_SECOND_NETDEV_ID:-net1}"
QEMU_SECOND_NETDEV_MODEL="${QEMU_SECOND_NETDEV_MODEL:-virtio-net-pci}"
QEMU_SECOND_NETDEV_MAC="${QEMU_SECOND_NETDEV_MAC:-52:54:00:70:ca:01}"
GENERATE_VPP_CLOUD_INIT_APPEND="${GENERATE_VPP_CLOUD_INIT_APPEND:-1}"
CLOUD_INIT_USER_DATA_APPEND_FILE="${CLOUD_INIT_USER_DATA_APPEND_FILE:-${VPP_CANARY_APPEND_FILE}}"
SSH_AUTHORIZED_KEYS_FILE="${SSH_AUTHORIZED_KEYS_FILE:-/root/.ssh/authorized_keys}"

log() {
  printf '[qemu-launch-vpp-canary-vm] %s\n' "$*"
}

fail() {
  printf '[qemu-launch-vpp-canary-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

ensure_state_dir() {
  mkdir -p "${STATE_DIR}" "${SEED_DIR}" "${IMAGE_CACHE_DIR}"
}

render_vpp_cloud_init_append() {
  if [[ "${GENERATE_VPP_CLOUD_INIT_APPEND}" != '1' ]]; then
    return 0
  fi

  [[ -f "${VPP_CANARY_AF_PACKET_SCRIPT}" ]] || fail "Missing AF_PACKET helper: ${VPP_CANARY_AF_PACKET_SCRIPT}"
  [[ -f "${VPP_CANARY_AF_PACKET_SERVICE}" ]] || fail "Missing AF_PACKET service: ${VPP_CANARY_AF_PACKET_SERVICE}"
  [[ -f "${VPP_CANARY_STARTUP_CONF}" ]] || fail "Missing VPP startup config: ${VPP_CANARY_STARTUP_CONF}"
  [[ -f "${VPP_CANARY_NETWORK_CONFIG}" ]] || fail "Missing VPP network config: ${VPP_CANARY_NETWORK_CONFIG}"

  {
    cat <<'EOF'
package_update: true
package_upgrade: false
write_files:
  - path: /usr/local/sbin/vpp-canary-afpacket.sh
    permissions: '0755'
    owner: root:root
    content: |
EOF
    sed 's/^/      /' "${VPP_CANARY_AF_PACKET_SCRIPT}"
    cat <<'EOF'
  - path: /etc/systemd/system/vpp-canary-afpacket.service
    permissions: '0644'
    owner: root:root
    content: |
EOF
    sed 's/^/      /' "${VPP_CANARY_AF_PACKET_SERVICE}"
    cat <<'EOF'
  - path: /usr/local/share/vpp-canary/startup.conf
    permissions: '0644'
    owner: root:root
    content: |
EOF
    sed 's/^/      /' "${VPP_CANARY_STARTUP_CONF}"
    cat <<'EOF'
runcmd:
  - |
    set -eux
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    curl -fsSL https://packagecloud.io/install/repositories/fdio/release/script.deb.sh | bash
    apt-get update
    apt-get install -y vpp vpp-plugin-core vpp-plugin-dpdk
    install -d -m 0755 /var/log/vpp /run/vpp /var/lib/vpp
    install -D -m 0644 /usr/local/share/vpp-canary/startup.conf /etc/vpp/startup.conf
    touch /var/log/vpp/vpp.log
    systemctl daemon-reload
    systemctl enable --now vpp
    systemctl enable --now vpp-canary-afpacket.service
    vppctl show version >/root/vpp-version.txt
    vppctl show interface >/root/vpp-interfaces.txt
    date -u +%FT%TZ >/var/lib/vpp-canary.ready
EOF
  } > "${VPP_CANARY_APPEND_FILE}"
}

prepare_ovs_tap() {
  if [[ "${VPP_CANARY_ENABLE_OVS_TAP}" != '1' ]]; then
    return 0
  fi

  QEMU_SECOND_NETDEV_BACKEND="${QEMU_SECOND_NETDEV_BACKEND:-tap,ifname=${VPP_CANARY_TAP_NAME},script=no,downscript=no}"
  if [[ "${QEMU_LAUNCH_DRY_RUN:-0}" == '1' ]]; then
    log "[DRY RUN] would ensure tap ${VPP_CANARY_TAP_NAME} exists on ${VPP_CANARY_OVS_BRIDGE}"
    return 0
  fi

  command -v ip >/dev/null 2>&1 || fail 'ip command is required to prepare the VPP canary tap'
  command -v ovs-vsctl >/dev/null 2>&1 || fail 'ovs-vsctl is required to attach the VPP canary tap'
  ovs-vsctl br-exists "${VPP_CANARY_OVS_BRIDGE}" || fail "OVS bridge does not exist: ${VPP_CANARY_OVS_BRIDGE}"

  if ! ip link show "${VPP_CANARY_TAP_NAME}" >/dev/null 2>&1; then
    ip tuntap add dev "${VPP_CANARY_TAP_NAME}" mode tap
  fi

  ip link set "${VPP_CANARY_TAP_NAME}" up
  ovs-vsctl --may-exist add-port "${VPP_CANARY_OVS_BRIDGE}" "${VPP_CANARY_TAP_NAME}" \
    -- set Interface "${VPP_CANARY_TAP_NAME}" \
    external_ids:owner=forge \
    external_ids:role=vpp-canary \
    external_ids:instance="${INSTANCE_NAME}"
}

run_cloudinit_launcher() {
  env \
    INSTANCE_NAME="${INSTANCE_NAME}" \
    BASE_DIR="${BASE_DIR}" \
    IMAGE_CACHE_DIR="${IMAGE_CACHE_DIR}" \
    STATE_DIR="${STATE_DIR}" \
    SEED_DIR="${SEED_DIR}" \
    SEED_ISO="${SEED_ISO}" \
    CLOUD_IMAGE_URL="${CLOUD_IMAGE_URL}" \
    OVERLAY_IMAGE="${OVERLAY_IMAGE}" \
    SSH_FORWARD_HOST="${SSH_FORWARD_HOST}" \
    SSH_FORWARD_PORT="${SSH_FORWARD_PORT}" \
    QEMU_SMP="${QEMU_SMP}" \
    QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB}" \
    QEMU_DISPLAY_MODE="${QEMU_DISPLAY_MODE}" \
    QEMU_SERIAL_MODE="${QEMU_SERIAL_MODE}" \
    QEMU_SERIAL_FILE="${QEMU_SERIAL_FILE}" \
    QEMU_DAEMONIZE="${QEMU_DAEMONIZE}" \
    WAIT_FOR_SSH="${WAIT_FOR_SSH}" \
    SSH_WAIT_TIMEOUT="${SSH_WAIT_TIMEOUT}" \
    ATTACH_HOST_DISKS="${ATTACH_HOST_DISKS}" \
    QEMU_SECOND_NETDEV_ID="${QEMU_SECOND_NETDEV_ID}" \
    QEMU_SECOND_NETDEV_BACKEND="${QEMU_SECOND_NETDEV_BACKEND-}" \
    QEMU_SECOND_NETDEV_MODEL="${QEMU_SECOND_NETDEV_MODEL}" \
    QEMU_SECOND_NETDEV_MAC="${QEMU_SECOND_NETDEV_MAC}" \
    CLOUD_INIT_USER_DATA_APPEND_FILE="${CLOUD_INIT_USER_DATA_APPEND_FILE}" \
    CLOUD_INIT_NETWORK_CONFIG_FILE="${VPP_CANARY_NETWORK_CONFIG}" \
    SSH_AUTHORIZED_KEYS_FILE="${SSH_AUTHORIZED_KEYS_FILE}" \
    bash "${LAUNCH_SCRIPT}"
}

main() {
  ensure_state_dir
  render_vpp_cloud_init_append
  prepare_ovs_tap
  log "Launching ${INSTANCE_NAME} with SSH forwarded on ${SSH_FORWARD_HOST}:${SSH_FORWARD_PORT}"
  log "OVS bridge ${VPP_CANARY_OVS_BRIDGE} tap ${VPP_CANARY_TAP_NAME}; physical NIC drivers remain unchanged"
  run_cloudinit_launcher
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
