#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_LAUNCH_TRACE:-0}" == '1' ]]; then
  set -x
fi

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
INSTANCE_NAME="${INSTANCE_NAME:-gentoo-stage4-testvm}"
STAGE3_IMAGE_DIR="${STAGE3_IMAGE_DIR:-/opt/gentoo-virt-qemu/stage3}"
QCOW_IMAGE="${QCOW_IMAGE:-${STAGE3_IMAGE_DIR}/images/${INSTANCE_NAME}.qcow2}"
QEMU_BOOT_SOURCE="${QEMU_BOOT_SOURCE:-qcow}"
BPOOL_DISK0="${BPOOL_DISK0-/dev/disk/by-id/ata-SATADOM-SL_3IE3_V2_BCA11708020382305}"
BPOOL_DISK1="${BPOOL_DISK1-/dev/disk/by-id/ata-SATADOM-SL_3IE3_V2_BCA11708020382932}"
RPOOL_DISK0="${RPOOL_DISK0-/dev/disk/by-id/ata-HBS3A1919A7E6B1_A03A5659}"
RPOOL_DISK1="${RPOOL_DISK1-/dev/disk/by-id/ata-HBS3A1919A7E6B1_A03A58E2}"
QEMU_BIN="${QEMU_BIN:-/usr/bin/qemu-system-x86_64}"
EFI_FIRM="${EFI_FIRM:-/usr/share/edk2-ovmf/OVMF_CODE.fd}"
EFI_VARS_TEMPLATE="${EFI_VARS_TEMPLATE:-/usr/share/edk2-ovmf/OVMF_VARS.fd}"
EFI_VARS_FILE="${EFI_VARS_FILE:-${STAGE3_IMAGE_DIR}/state/${INSTANCE_NAME}.OVMF_VARS.fd}"
QEMU_MACHINE="${QEMU_MACHINE:-q35,accel=kvm}"
QEMU_CPU="${QEMU_CPU:-host}"
QEMU_SMP="${QEMU_SMP:-8}"
QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB:-16384}"
QEMU_BOOT_STRICT="${QEMU_BOOT_STRICT:-1}"
QEMU_BOOTDISK_ID="${QEMU_BOOTDISK_ID:-bootdisk}"
QEMU_BOOTDISK_MODEL="${QEMU_BOOTDISK_MODEL:-virtio-blk-pci}"
QEMU_BOOTDISK_BOOTINDEX="${QEMU_BOOTDISK_BOOTINDEX:-1}"
QEMU_LAUNCH_DRY_RUN="${QEMU_LAUNCH_DRY_RUN:-0}"
QEMU_DAEMONIZE="${QEMU_DAEMONIZE:-1}"
QEMU_DISPLAY_MODE="${QEMU_DISPLAY_MODE:-none}"
QEMU_SERIAL_MODE="${QEMU_SERIAL_MODE:-file}"
QEMU_SERIAL_FILE="${QEMU_SERIAL_FILE:-${STAGE3_IMAGE_DIR}/state/${INSTANCE_NAME}.serial.log}"
QEMU_SERIAL_TCP="${QEMU_SERIAL_TCP:-127.0.0.1:4555,server=on,wait=off,telnet=on}"
QEMU_NETWORK_MODE="${QEMU_NETWORK_MODE:-user}"
QEMU_NETDEV_ID="${QEMU_NETDEV_ID:-net0}"
QEMU_NETDEV_BACKEND="${QEMU_NETDEV_BACKEND:-user,hostfwd=tcp:127.0.0.1:2222-:22}"
QEMU_NETDEV_MODEL="${QEMU_NETDEV_MODEL:-virtio-net-pci}"
QEMU_NET_ALIAS_DEV="${QEMU_NET_ALIAS_DEV:-lo}"
QEMU_NET_ALIAS_CIDR="${QEMU_NET_ALIAS_CIDR:-10.9.8.108/24}"
QEMU_NET_ALIAS_SUBNET="${QEMU_NET_ALIAS_SUBNET:-10.9.8.0/24}"
QEMU_NET_ALIAS_GUEST_IPV4="${QEMU_NET_ALIAS_GUEST_IPV4:-10.9.8.7}"
QEMU_TAP_IFNAME="${QEMU_TAP_IFNAME:-tap-stage4}"
QEMU_BRIDGE_IFNAME="${QEMU_BRIDGE_IFNAME:-}"
QEMU_TAP_HOST_CIDR="${QEMU_TAP_HOST_CIDR:-}"
QEMU_NETDEV_HELP_OUTPUT="${QEMU_NETDEV_HELP_OUTPUT-}"
QEMU_DISPLAY_HELP_OUTPUT="${QEMU_DISPLAY_HELP_OUTPUT-}"
IP_BIN="${IP_BIN:-/usr/sbin/ip}"
HOST_DISK_CACHE="${HOST_DISK_CACHE:-none}"
HOST_DISK_AIO="${HOST_DISK_AIO:-native}"
WAIT_FOR_SSH="${WAIT_FOR_SSH:-1}"
SSH_READY_PROBE="${SSH_READY_PROBE:-banner}"
SSH_READY_HOST="${SSH_READY_HOST:-127.0.0.1}"
SSH_READY_PORT="${SSH_READY_PORT:-2222}"
SSH_WAIT_TIMEOUT="${SSH_WAIT_TIMEOUT:-120}"
SSH_BANNER_TIMEOUT="${SSH_BANNER_TIMEOUT:-5}"
LAUNCHER_LOG_ENABLE="${LAUNCHER_LOG_ENABLE:-1}"
LAUNCHER_LOG_DIR="${LAUNCHER_LOG_DIR:-/tmp}"
LAUNCHER_LOG_FILE="${LAUNCHER_LOG_FILE-}"
LAUNCHER_LOG_TIMESTAMP="${LAUNCHER_LOG_TIMESTAMP-}"
LAUNCHER_LOG_INITIALIZED=0
ALLOCATED_SERIAL_PTY=''
RESOLVED_QEMU_NETDEV_BACKEND=''
RESOLVED_SSH_READY_HOST=''
QEMU_CMD=()

log() {
  printf '[qemu-launch-stage3-vm] %s\n' "$*"
}

fail() {
  printf '[qemu-launch-stage3-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

print_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

network_backend_name() {
  printf '%s' "${QEMU_NETDEV_BACKEND%%,*}"
}

display_mode_name() {
  printf '%s' "${QEMU_DISPLAY_MODE}"
}

serial_mode_name() {
  printf '%s' "${QEMU_SERIAL_MODE}"
}

network_mode_name() {
  printf '%s' "${QEMU_NETWORK_MODE}"
}

boot_source_name() {
  printf '%s' "${QEMU_BOOT_SOURCE}"
}

alias_host_ipv4() {
  printf '%s' "${QEMU_NET_ALIAS_CIDR%%/*}"
}

ensure_alias_address() {
  local existing_addrs

  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  existing_addrs="$("${IP_BIN}" -o -4 addr show dev "${QEMU_NET_ALIAS_DEV}" 2> /dev/null || true)"
  if [[ "${existing_addrs}" == *"${QEMU_NET_ALIAS_CIDR}"* ]]; then
    return 0
  fi

  "${IP_BIN}" address add "${QEMU_NET_ALIAS_CIDR}" dev "${QEMU_NET_ALIAS_DEV}"
}

ensure_tap_interface() {
  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  if ! "${IP_BIN}" link show dev "${QEMU_TAP_IFNAME}" > /dev/null 2>&1; then
    "${IP_BIN}" tuntap add dev "${QEMU_TAP_IFNAME}" mode tap
  fi

  "${IP_BIN}" link set "${QEMU_TAP_IFNAME}" up

  if [[ -n "${QEMU_TAP_HOST_CIDR}" ]]; then
    if ! "${IP_BIN}" -o -4 addr show dev "${QEMU_TAP_IFNAME}" | grep -Fq "${QEMU_TAP_HOST_CIDR}"; then
      "${IP_BIN}" address add "${QEMU_TAP_HOST_CIDR}" dev "${QEMU_TAP_IFNAME}"
    fi
  fi
}

ensure_bridge_membership() {
  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  [[ -n "${QEMU_BRIDGE_IFNAME}" ]] || fail 'QEMU_BRIDGE_IFNAME is required for QEMU_NETWORK_MODE=bridge'
  "${IP_BIN}" link show dev "${QEMU_BRIDGE_IFNAME}" > /dev/null 2>&1 || fail "Bridge interface is missing: ${QEMU_BRIDGE_IFNAME}"
  "${IP_BIN}" link set "${QEMU_TAP_IFNAME}" master "${QEMU_BRIDGE_IFNAME}"
}

resolve_network_backend() {
  RESOLVED_SSH_READY_HOST="${SSH_READY_HOST}"
  case "$(network_mode_name)" in
  user)
    RESOLVED_QEMU_NETDEV_BACKEND="${QEMU_NETDEV_BACKEND}"
    ;;
  alias)
    ensure_alias_address
    RESOLVED_SSH_READY_HOST="$(alias_host_ipv4)"
    RESOLVED_QEMU_NETDEV_BACKEND="user,net=${QEMU_NET_ALIAS_SUBNET},host=${RESOLVED_SSH_READY_HOST},dhcpstart=${QEMU_NET_ALIAS_GUEST_IPV4},hostfwd=tcp:${RESOLVED_SSH_READY_HOST}:${SSH_READY_PORT}-:22"
    ;;
  tap)
    ensure_tap_interface
    RESOLVED_QEMU_NETDEV_BACKEND="tap,ifname=${QEMU_TAP_IFNAME},script=no,downscript=no"
    ;;
  bridge)
    ensure_tap_interface
    ensure_bridge_membership
    RESOLVED_QEMU_NETDEV_BACKEND="tap,ifname=${QEMU_TAP_IFNAME},script=no,downscript=no"
    ;;
  *)
    fail "Unsupported QEMU_NETWORK_MODE: $(network_mode_name) (supported: user, alias, tap, bridge)"
    ;;
  esac
}

launcher_log_timestamp() {
  if [[ -n "${LAUNCHER_LOG_TIMESTAMP}" ]]; then
    printf '%s' "${LAUNCHER_LOG_TIMESTAMP}"
    return 0
  fi

  TZ=UTC date +"%Y-%m%d-%H%M_%s.UTC%z"
}

default_launcher_log_file() {
  printf '%s/%s.%s-%s.%s.log' \
    "${LAUNCHER_LOG_DIR}" \
    "${SCRIPT_NAME}" \
    "${PPID}" \
    "$$" \
    "$(launcher_log_timestamp)"
}

setup_launcher_logging() {
  if [[ "${LAUNCHER_LOG_ENABLE}" != '1' || "${LAUNCHER_LOG_INITIALIZED}" == '1' ]]; then
    return 0
  fi

  if [[ -z "${LAUNCHER_LOG_FILE}" ]]; then
    LAUNCHER_LOG_FILE="$(default_launcher_log_file)"
  fi

  mkdir -p "${LAUNCHER_LOG_DIR}"
  exec > >(tee -a "${LAUNCHER_LOG_FILE}") 2>&1
  LAUNCHER_LOG_INITIALIZED=1
  log "Launcher log file: ${LAUNCHER_LOG_FILE}"
}

require_host_disk_ready() {
  local path="$1"
  local label="$2"
  local resolved_path

  [[ -n "${path}" ]] || fail "${label} is empty"
  [[ -e "${path}" ]] || fail "${label} is missing: ${path}"

  resolved_path="$(readlink -f "${path}" 2> /dev/null || true)"
  if [[ "${path}" == /dev/* || "${resolved_path}" == /dev/* ]]; then
    [[ -n "${resolved_path}" && -b "${resolved_path}" ]] || fail "${label} is not a block device: ${path}"
  fi
}

validate_host_disks() {
  require_host_disk_ready "${BPOOL_DISK0}" 'BPOOL_DISK0'
  require_host_disk_ready "${BPOOL_DISK1}" 'BPOOL_DISK1'
  require_host_disk_ready "${RPOOL_DISK0}" 'RPOOL_DISK0'
  require_host_disk_ready "${RPOOL_DISK1}" 'RPOOL_DISK1'
}

validate_boot_source() {
  case "$(boot_source_name)" in
  qcow | target-disks) ;;
  *)
    fail "Unsupported QEMU_BOOT_SOURCE: $(boot_source_name) (supported: qcow, target-disks)"
    ;;
  esac
}

validate_qcow_image() {
  if [[ "$(boot_source_name)" != 'qcow' ]]; then
    return 0
  fi

  [[ -f "${QCOW_IMAGE}" ]] || fail "QCOW_IMAGE is missing: ${QCOW_IMAGE}"
}

validate_efi_firmware() {
  [[ -f "${EFI_FIRM}" ]] || fail "EFI_FIRM is missing: ${EFI_FIRM}"
  [[ -f "${EFI_VARS_TEMPLATE}" ]] || fail "EFI_VARS_TEMPLATE is missing: ${EFI_VARS_TEMPLATE}"
}

validate_net_backend() {
  local backend help_output

  resolve_network_backend
  backend="$(network_backend_name)"
  if [[ "${backend}" == 'alias' ]]; then
    backend='user'
  elif [[ "${backend}" == 'bridge' ]]; then
    backend='tap'
  fi
  [[ -n "${backend}" ]] || fail 'QEMU_NETDEV_BACKEND is empty'

  help_output="${QEMU_NETDEV_HELP_OUTPUT}"
  if [[ -z "${help_output}" ]]; then
    help_output="$("${QEMU_BIN}" -netdev help 2>&1 || true)"
  fi

  if [[ "${help_output}" != *"${backend}"* ]]; then
    if [[ "${backend}" == 'user' ]]; then
      fail "QEMU net backend '${backend}' is not available in ${QEMU_BIN}; rebuild QEMU with USE=slirp or choose a supported backend"
    fi

    fail "QEMU net backend '${backend}' is not available in ${QEMU_BIN}"
  fi
}

validate_display_backend() {
  local help_output

  case "$(display_mode_name)" in
  none)
    return 0
    ;;
  gtk | sdl)
    help_output="${QEMU_DISPLAY_HELP_OUTPUT}"
    if [[ -z "${help_output}" ]]; then
      help_output="$("${QEMU_BIN}" -display help 2>&1 || true)"
    fi
    [[ "${help_output}" == *"$(display_mode_name)"* ]] || fail "QEMU display mode '$(display_mode_name)' is not available in ${QEMU_BIN}"
    ;;
  *)
    fail "Unsupported QEMU_DISPLAY_MODE: $(display_mode_name)"
    ;;
  esac
}

validate_serial_mode() {
  case "$(serial_mode_name)" in
  none | stdio | pty | tcp | file) ;;
  *)
    fail "Unsupported QEMU_SERIAL_MODE: $(serial_mode_name) (supported: none, stdio, pty, tcp, file)"
    ;;
  esac

  if [[ "$(serial_mode_name)" == 'stdio' && "${QEMU_DAEMONIZE}" == '1' ]]; then
    fail 'QEMU_SERIAL_MODE=stdio requires QEMU_DAEMONIZE=0'
  fi
}

append_host_disk() {
  local drive_id="$1"
  local drive_path="$2"
  local ahci_port="$3"
  local serial="$4"
  local bootindex="${5-}"
  local device_args="ide-hd,drive=${drive_id},bus=ahci.${ahci_port},serial=${serial}"

  if [[ -n "${bootindex}" ]]; then
    device_args+=",bootindex=${bootindex}"
  fi

  QEMU_CMD+=(
    -drive "if=none,id=${drive_id},file=${drive_path},format=raw,cache=${HOST_DISK_CACHE},aio=${HOST_DISK_AIO}"
    -device "${device_args}"
  )
}

append_boot_args() {
  if [[ "${QEMU_BOOT_STRICT}" == '1' ]]; then
    QEMU_CMD+=(-boot strict=on)
  fi
}

append_display_args() {
  case "$(display_mode_name)" in
  none)
    QEMU_CMD+=(-display none)
    ;;
  gtk | sdl)
    QEMU_CMD+=(-display "$(display_mode_name)")
    ;;
  esac
}

append_serial_args() {
  case "$(serial_mode_name)" in
  none)
    return 0
    ;;
  stdio)
    QEMU_CMD+=(-serial mon:stdio)
    ;;
  pty)
    QEMU_CMD+=(-serial pty)
    ;;
  tcp)
    QEMU_CMD+=(-serial "tcp:${QEMU_SERIAL_TCP}")
    ;;
  file)
    mkdir -p "$(dirname "${QEMU_SERIAL_FILE}")"
    QEMU_CMD+=(-serial "file:${QEMU_SERIAL_FILE}")
    ;;
  esac
}

prepare_ovmf_vars_file() {
  mkdir -p "$(dirname "${EFI_VARS_FILE}")"
  if [[ ! -f "${EFI_VARS_FILE}" ]]; then
    cp "${EFI_VARS_TEMPLATE}" "${EFI_VARS_FILE}"
  fi
}

build_qemu_cmd() {
  resolve_network_backend
  prepare_ovmf_vars_file
  QEMU_CMD=(
    "${QEMU_BIN}"
    -enable-kvm
    -machine "${QEMU_MACHINE}"
    -cpu "${QEMU_CPU}"
    -smp "${QEMU_SMP}"
    -m "${QEMU_MEMORY_MIB}"
    -drive "if=pflash,format=raw,readonly=on,file=${EFI_FIRM}"
    -drive "if=pflash,format=raw,file=${EFI_VARS_FILE}"
    -smbios 'type=0,uefi=on'
    -device 'ich9-ahci,id=ahci'
  )

  if [[ "$(boot_source_name)" == 'qcow' ]]; then
    QEMU_CMD+=(
      -drive "if=none,id=${QEMU_BOOTDISK_ID},file=${QCOW_IMAGE},format=qcow2"
      -device "${QEMU_BOOTDISK_MODEL},drive=${QEMU_BOOTDISK_ID},bootindex=${QEMU_BOOTDISK_BOOTINDEX},serial=stage3-boot"
    )
  fi

  if [[ "$(boot_source_name)" == 'target-disks' ]]; then
    append_host_disk 'bpool0' "${BPOOL_DISK0}" '1' 'bpool-0' '1'
  else
    append_host_disk 'bpool0' "${BPOOL_DISK0}" '1' 'bpool-0'
  fi
  append_host_disk 'bpool1' "${BPOOL_DISK1}" '2' 'bpool-1'
  append_host_disk 'rpool0' "${RPOOL_DISK0}" '3' 'rpool-0'
  append_host_disk 'rpool1' "${RPOOL_DISK1}" '4' 'rpool-1'

  QEMU_CMD+=(
    -netdev "${RESOLVED_QEMU_NETDEV_BACKEND},id=${QEMU_NETDEV_ID}"
    -device "${QEMU_NETDEV_MODEL},netdev=${QEMU_NETDEV_ID}"
  )

  append_boot_args
  append_display_args
  append_serial_args

  if [[ "${QEMU_DAEMONIZE}" == '1' ]]; then
    QEMU_CMD+=(-daemonize)
  fi
}

port_is_open() {
  exec 3<> "/dev/tcp/${SSH_READY_HOST}/${SSH_READY_PORT}" && exec 3>&- 3<&-
}

probe_ssh_banner() {
  local banner=''

  exec 3<> "/dev/tcp/${SSH_READY_HOST}/${SSH_READY_PORT}" || return 1
  if ! IFS= read -r -t "${SSH_BANNER_TIMEOUT}" banner <&3; then
    exec 3>&- 3<&-
    return 1
  fi
  exec 3>&- 3<&-

  [[ "${banner}" == SSH-* ]]
}

wait_for_ssh_ready() {
  local deadline

  if [[ "${WAIT_FOR_SSH}" != '1' || "${QEMU_DAEMONIZE}" != '1' ]]; then
    return 0
  fi

  deadline=$((SECONDS + SSH_WAIT_TIMEOUT))
  case "${SSH_READY_PROBE}" in
  none)
    return 0
    ;;
  tcp-port)
    until port_is_open; do
      if ((SECONDS >= deadline)); then
        fail "Timed out waiting for TCP port ${SSH_READY_HOST}:${SSH_READY_PORT}"
      fi
      sleep 1
    done
    ;;
  banner)
    until probe_ssh_banner; do
      if ((SECONDS >= deadline)); then
        fail "Timed out waiting for an SSH banner on ${SSH_READY_HOST}:${SSH_READY_PORT}; inspect the serial console for guest boot status"
      fi
      sleep 1
    done
    ;;
  *)
    fail "Unsupported SSH_READY_PROBE: ${SSH_READY_PROBE}"
    ;;
  esac
}

capture_qemu_startup_output() {
  local qemu_output status

  set +e
  qemu_output="$("${QEMU_CMD[@]}" 2>&1)"
  status=$?
  set -e

  if [[ -n "${qemu_output}" ]]; then
    printf '%s\n' "${qemu_output}"
  fi

  if ((status != 0)); then
    return "${status}"
  fi

  ALLOCATED_SERIAL_PTY="$(printf '%s\n' "${qemu_output}" | grep -Eo '/dev/pts/[0-9]+' | tail -n1 || true)"
  if [[ -n "${ALLOCATED_SERIAL_PTY}" ]]; then
    log "Serial PTY: ${ALLOCATED_SERIAL_PTY}"
  fi
}

run_qemu_cmd() {
  build_qemu_cmd

  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    print_cmd "${QEMU_CMD[@]}"
    return 0
  fi

  if [[ "$(serial_mode_name)" == 'pty' && "${QEMU_DAEMONIZE}" == '1' ]]; then
    capture_qemu_startup_output
    return 0
  fi

  "${QEMU_CMD[@]}"
}

main() {
  setup_launcher_logging
  validate_boot_source
  validate_qcow_image
  validate_efi_firmware
  validate_host_disks
  validate_net_backend
  validate_display_backend
  validate_serial_mode
  log "Boot source: $(boot_source_name)"
  log "Network mode: $(network_mode_name)"
  if [[ "$(boot_source_name)" == 'qcow' ]]; then
    log "QCOW image: ${QCOW_IMAGE}"
  else
    log "Target-disk boot: prioritizing ${BPOOL_DISK0} via UEFI removable path"
  fi
  log "SSH target after boot: ssh -p ${SSH_READY_PORT} root@${RESOLVED_SSH_READY_HOST}"
  run_qemu_cmd
  SSH_READY_HOST="${RESOLVED_SSH_READY_HOST}"
  wait_for_ssh_ready
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
