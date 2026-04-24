#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_LAUNCH_TRACE:-0}" == '1' ]]; then
  set -x
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED_SCRIPT="${SEED_SCRIPT:-${SCRIPT_DIR}/generate-cloud-init-seed.sh}"
INSTANCE_NAME="${INSTANCE_NAME:-gentoo-stage4-testvm}"
BASE_DIR="${BASE_DIR:-/opt/gentoo-virt-qemu/cloud}"
IMAGE_CACHE_DIR="${IMAGE_CACHE_DIR:-${BASE_DIR}/images}"
STATE_DIR="${STATE_DIR:-${BASE_DIR}/state/${INSTANCE_NAME}}"
SEED_DIR="${SEED_DIR:-${STATE_DIR}/seed}"
SEED_ISO="${SEED_ISO:-${STATE_DIR}/${INSTANCE_NAME}-seed.iso}"
CLOUD_IMAGE_PATH="${CLOUD_IMAGE_PATH-}"
CLOUD_IMAGE_URL="${CLOUD_IMAGE_URL-}"
CLOUD_IMAGE_INFO_URL="${CLOUD_IMAGE_INFO_URL:-https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-di-amd64-cloudinit.txt}"
BASE_IMAGE_PATH="${BASE_IMAGE_PATH-}"
OVERLAY_IMAGE="${OVERLAY_IMAGE:-${STATE_DIR}/${INSTANCE_NAME}.qcow2}"
RECREATE_OVERLAY="${RECREATE_OVERLAY:-0}"
GENERATE_SEED="${GENERATE_SEED:-1}"
SSH_FORWARD_HOST="${SSH_FORWARD_HOST:-127.0.0.1}"
SSH_FORWARD_PORT="${SSH_FORWARD_PORT:-2222}"
WAIT_FOR_SSH="${WAIT_FOR_SSH:-1}"
SSH_WAIT_TIMEOUT="${SSH_WAIT_TIMEOUT:-120}"
SSH_READY_PROBE="${SSH_READY_PROBE:-banner}"
SSH_BANNER_TIMEOUT="${SSH_BANNER_TIMEOUT:-5}"
BPOOL_DISK0="${BPOOL_DISK0-/dev/disk/by-id/ata-SATADOM-SL_3IE3_V2_BCA11708020382305}"
BPOOL_DISK1="${BPOOL_DISK1-/dev/disk/by-id/ata-SATADOM-SL_3IE3_V2_BCA11708020382932}"
RPOOL_DISK0="${RPOOL_DISK0-/dev/disk/by-id/ata-HBS3A1919A7E6B1_A03A5659}"
RPOOL_DISK1="${RPOOL_DISK1-/dev/disk/by-id/ata-HBS3A1919A7E6B1_A03A58E2}"
QEMU_BIN="${QEMU_BIN:-/usr/bin/qemu-system-x86_64}"
QEMU_IMG_BIN="${QEMU_IMG_BIN:-/usr/bin/qemu-img}"
EFI_FIRM="${EFI_FIRM:-/usr/share/edk2-ovmf/OVMF_CODE.fd}"
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
QEMU_SERIAL_FILE="${QEMU_SERIAL_FILE:-${STATE_DIR}/${INSTANCE_NAME}.serial.log}"
QEMU_NETDEV_ID="${QEMU_NETDEV_ID:-net0}"
QEMU_NETDEV_BACKEND="${QEMU_NETDEV_BACKEND:-user,hostfwd=tcp:${SSH_FORWARD_HOST}:${SSH_FORWARD_PORT}-:22}"
QEMU_NETDEV_MODEL="${QEMU_NETDEV_MODEL:-virtio-net-pci}"
QEMU_ENABLE_VSOCK="${QEMU_ENABLE_VSOCK:-0}"
QEMU_VSOCK_MODEL="${QEMU_VSOCK_MODEL:-vhost-vsock-pci}"
QEMU_VSOCK_CID="${QEMU_VSOCK_CID:-3}"
QEMU_NETDEV_HELP_OUTPUT="${QEMU_NETDEV_HELP_OUTPUT-}"
QEMU_DISPLAY_HELP_OUTPUT="${QEMU_DISPLAY_HELP_OUTPUT-}"
QEMU_DEVICE_HELP_OUTPUT="${QEMU_DEVICE_HELP_OUTPUT-}"
SYSFS_ROOT="${SYSFS_ROOT:-/sys}"
HOST_DISK_CACHE="${HOST_DISK_CACHE:-none}"
HOST_DISK_AIO="${HOST_DISK_AIO:-native}"
QEMU_CMD=()
OVERLAY_CMD=()

log() {
  printf '[qemu-launch-cloudinit-vm] %s\n' "$*"
}

fail() {
  printf '[qemu-launch-cloudinit-vm] ERROR: %s\n' "$*" >&2
  exit 1
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

ensure_dirs() {
  mkdir -p "${IMAGE_CACHE_DIR}" "${STATE_DIR}" "${SEED_DIR}"
}

require_host_disk_ready() {
  local path="$1"
  local label="$2"
  local resolved_path

  [[ -n "${path}" ]] || fail "${label} is empty"
  [[ -e "${path}" ]] || fail "${label} is missing: ${path}"

  resolved_path="$(readlink -f "${path}" 2>/dev/null || true)"
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

validate_net_backend() {
  local backend help_output

  backend="$(network_backend_name)"
  [[ -n "${backend}" ]] || fail 'QEMU_NETDEV_BACKEND is empty'

  help_output="${QEMU_NETDEV_HELP_OUTPUT}"
  if [[ -z "${help_output}" ]]; then
    help_output="$("${QEMU_BIN}" -netdev help 2>&1 || true)"
  fi

  if [[ "${help_output}" != *"${backend}"* ]]; then
    if [[ "${backend}" == 'user' ]]; then
      fail "QEMU net backend '${backend}' is not available in ${QEMU_BIN}; rebuild QEMU with USE=slirp or set QEMU_NETDEV_BACKEND to a supported backend"
    fi

    fail "QEMU net backend '${backend}' is not available in ${QEMU_BIN}; inspect '${QEMU_BIN} -netdev help' and set QEMU_NETDEV_BACKEND to a supported backend"
  fi
}

validate_display_backend() {
  local help_output

  case "$(display_mode_name)" in
    none)
      return 0
      ;;
    gtk|sdl)
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

validate_vsock_backend() {
  local help_output

  if [[ "${QEMU_ENABLE_VSOCK}" != '1' ]]; then
    return 0
  fi

  help_output="${QEMU_DEVICE_HELP_OUTPUT}"
  if [[ -z "${help_output}" ]]; then
    help_output="$("${QEMU_BIN}" -device help 2>&1 || true)"
  fi

  [[ "${help_output}" == *"${QEMU_VSOCK_MODEL}"* ]] || fail "QEMU vsock device '${QEMU_VSOCK_MODEL}' is not available in ${QEMU_BIN}"
}

find_fetch_tool() {
  if command -v curl >/dev/null 2>&1; then
    printf 'curl'
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    printf 'wget'
    return 0
  fi

  fail 'Neither curl nor wget is available for downloading the Gentoo cloud image metadata'
}

fetch_text() {
  local url="$1"

  case "$(find_fetch_tool)" in
    curl)
      curl -fsSL "${url}"
      ;;
    wget)
      wget -qO- "${url}"
      ;;
  esac
}

download_file() {
  local url="$1"
  local dest="$2"

  case "$(find_fetch_tool)" in
    curl)
      curl -fL -o "${dest}" "${url}"
      ;;
    wget)
      wget -O "${dest}" "${url}"
      ;;
  esac
}

resolve_cloud_image_url() {
  local info_text resolved_url resolved_path resolved_name

  if [[ -n "${CLOUD_IMAGE_URL}" ]]; then
    printf '%s' "${CLOUD_IMAGE_URL}"
    return 0
  fi

  info_text="$(fetch_text "${CLOUD_IMAGE_INFO_URL}")"
  resolved_url="$(printf '%s\n' "${info_text}" | grep -Eo 'https://[^[:space:]]+\.qcow2' | head -n1 || true)"
  if [[ -n "${resolved_url}" ]]; then
    printf '%s' "${resolved_url}"
    return 0
  fi

  resolved_path="$(printf '%s\n' "${info_text}" | grep -Eo '/releases/[^[:space:]]+\.qcow2' | head -n1 || true)"
  if [[ -n "${resolved_path}" ]]; then
    printf 'https://distfiles.gentoo.org%s' "${resolved_path}"
    return 0
  fi

  resolved_name="$(printf '%s\n' "${info_text}" | grep -Eo 'di-amd64-cloudinit-[0-9TZ]+\.qcow2' | head -n1 || true)"
  if [[ -n "${resolved_name}" ]]; then
    printf 'https://distfiles.gentoo.org/releases/amd64/autobuilds/current-di-amd64-cloudinit/%s' "${resolved_name}"
    return 0
  fi

  fail "Unable to resolve a Gentoo cloud image URL from ${CLOUD_IMAGE_INFO_URL}"
}

ensure_base_image() {
  local image_url image_filename

  if [[ -n "${CLOUD_IMAGE_PATH}" ]]; then
    [[ -f "${CLOUD_IMAGE_PATH}" ]] || fail "CLOUD_IMAGE_PATH does not exist: ${CLOUD_IMAGE_PATH}"
    BASE_IMAGE_PATH="${CLOUD_IMAGE_PATH}"
    return 0
  fi

  image_url="$(resolve_cloud_image_url)"
  image_filename="$(basename "${image_url}")"
  if [[ -z "${BASE_IMAGE_PATH}" ]]; then
    BASE_IMAGE_PATH="${IMAGE_CACHE_DIR}/${image_filename}"
  fi

  if [[ -f "${BASE_IMAGE_PATH}" ]]; then
    return 0
  fi

  log "Downloading Gentoo cloud image from ${image_url}"
  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    log "[DRY RUN] would download to ${BASE_IMAGE_PATH}"
    return 0
  fi

  download_file "${image_url}" "${BASE_IMAGE_PATH}"
}

build_overlay_cmd() {
  OVERLAY_CMD=(
    "${QEMU_IMG_BIN}"
    create
    -f qcow2
    -F qcow2
    -b "${BASE_IMAGE_PATH}"
    "${OVERLAY_IMAGE}"
  )
}

print_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

ensure_overlay_image() {
  if [[ "${RECREATE_OVERLAY}" == '1' ]]; then
    rm -f "${OVERLAY_IMAGE}"
  fi

  if [[ -f "${OVERLAY_IMAGE}" ]]; then
    return 0
  fi

  build_overlay_cmd
  log "Creating writable overlay ${OVERLAY_IMAGE}"
  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    print_cmd "${OVERLAY_CMD[@]}"
    return 0
  fi

  "${OVERLAY_CMD[@]}"
}

ensure_seed_iso() {
  local seed_instance_name seed_state_dir seed_dir_path seed_iso_path seed_dry_run

  if [[ "${GENERATE_SEED}" != '1' ]]; then
    [[ -f "${SEED_ISO}" || "${QEMU_LAUNCH_DRY_RUN}" == '1' ]] || fail "SEED_ISO is missing and GENERATE_SEED=0: ${SEED_ISO}"
    return 0
  fi

  seed_instance_name="${INSTANCE_NAME}"
  seed_state_dir="${STATE_DIR}"
  seed_dir_path="${SEED_DIR}"
  seed_iso_path="${SEED_ISO}"
  seed_dry_run="${QEMU_LAUNCH_DRY_RUN}"

  env \
    INSTANCE_NAME="${seed_instance_name}" \
    LOCAL_HOSTNAME="${seed_instance_name}" \
    INSTANCE_ID="${seed_instance_name}" \
    SEED_BASE_DIR="${seed_state_dir}" \
    SEED_DIR="${seed_dir_path}" \
    SEED_ISO="${seed_iso_path}" \
    CLOUD_INIT_SEED_DRY_RUN="${seed_dry_run}" \
    bash "${SEED_SCRIPT}"
}

append_host_disk() {
  local drive_id="$1"
  local drive_path="$2"
  local ahci_port="$3"
  local serial="$4"

  QEMU_CMD+=(
    -drive "if=none,id=${drive_id},file=${drive_path},format=raw,cache=${HOST_DISK_CACHE},aio=${HOST_DISK_AIO}"
    -device "ide-hd,drive=${drive_id},bus=ahci.${ahci_port},serial=${serial}"
  )
}

append_vsock_args() {
  if [[ "${QEMU_ENABLE_VSOCK}" == '1' ]]; then
    QEMU_CMD+=( -device "${QEMU_VSOCK_MODEL},guest-cid=${QEMU_VSOCK_CID}" )
  fi
}

append_boot_args() {
  if [[ "${QEMU_BOOT_STRICT}" == '1' ]]; then
    QEMU_CMD+=( -boot strict=on )
  fi
}

append_display_args() {
  case "$(display_mode_name)" in
    none)
      QEMU_CMD+=( -display none )
      ;;
    gtk|sdl)
      QEMU_CMD+=( -display "$(display_mode_name)" )
      ;;
  esac
}

append_serial_args() {
  case "$(serial_mode_name)" in
    none)
      return 0
      ;;
    stdio)
      QEMU_CMD+=( -serial mon:stdio )
      ;;
    pty)
      QEMU_CMD+=( -serial pty )
      ;;
    file)
      QEMU_CMD+=( -serial "file:${QEMU_SERIAL_FILE}" )
      ;;
    *)
      fail "Unsupported QEMU_SERIAL_MODE: $(serial_mode_name)"
      ;;
  esac
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
    -smbios 'type=0,uefi=on'
    -device 'ich9-ahci,id=ahci'
    -drive "if=none,id=${QEMU_BOOTDISK_ID},file=${OVERLAY_IMAGE},format=qcow2"
    -device "${QEMU_BOOTDISK_MODEL},drive=${QEMU_BOOTDISK_ID},bootindex=${QEMU_BOOTDISK_BOOTINDEX},serial=cloud-boot"
    -drive "if=none,id=seed,file=${SEED_ISO},format=raw,media=cdrom,readonly=on"
    -device 'ide-cd,drive=seed,bus=ahci.0'
  )

  append_host_disk 'bpool0' "${BPOOL_DISK0}" '1' 'bpool-0'
  append_host_disk 'bpool1' "${BPOOL_DISK1}" '2' 'bpool-1'
  append_host_disk 'rpool0' "${RPOOL_DISK0}" '3' 'rpool-0'
  append_host_disk 'rpool1' "${RPOOL_DISK1}" '4' 'rpool-1'

  QEMU_CMD+=(
    -netdev "${QEMU_NETDEV_BACKEND},id=${QEMU_NETDEV_ID}"
    -device "${QEMU_NETDEV_MODEL},netdev=${QEMU_NETDEV_ID}"
  )

  append_vsock_args
  append_boot_args
  append_display_args
  append_serial_args
  if [[ "${QEMU_DAEMONIZE}" == '1' ]]; then
    QEMU_CMD+=( -daemonize )
  fi
}

port_is_open() {
  exec 3<>"/dev/tcp/${SSH_FORWARD_HOST}/${SSH_FORWARD_PORT}" && exec 3>&- 3<&-
}

probe_ssh_banner() {
  local banner=''

  exec 3<>"/dev/tcp/${SSH_FORWARD_HOST}/${SSH_FORWARD_PORT}" || return 1
  if ! IFS= read -r -t "${SSH_BANNER_TIMEOUT}" banner <&3; then
    exec 3>&- 3<&-
    return 1
  fi
  exec 3>&- 3<&-

  [[ "${banner}" == SSH-* ]]
}

serial_log_vsock_hint() {
  local hint=''

  [[ -f "${QEMU_SERIAL_FILE}" ]] || return 0
  hint="$(grep -Eo "ssh vsock%[^']+" "${QEMU_SERIAL_FILE}" | tail -n1 || true)"
  printf '%s' "${hint}"
}

wait_for_ssh_ready() {
  local deadline
  local hint=''

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
        if (( SECONDS >= deadline )); then
          fail "Timed out waiting for TCP port ${SSH_FORWARD_HOST}:${SSH_FORWARD_PORT}"
        fi
        sleep 1
      done
      ;;
    banner)
      until probe_ssh_banner; do
        if (( SECONDS >= deadline )); then
          hint="$(serial_log_vsock_hint)"
          if [[ -n "${hint}" ]]; then
            fail "Timed out waiting for an SSH banner on ${SSH_FORWARD_HOST}:${SSH_FORWARD_PORT}; serial log advertises '${hint}'. If this image prefers vsock SSH, relaunch with QEMU_ENABLE_VSOCK=1 and use the guest-advertised command."
          fi
          fail "Timed out waiting for an SSH banner on ${SSH_FORWARD_HOST}:${SSH_FORWARD_PORT}; inspect ${QEMU_SERIAL_FILE} for guest boot status"
        fi
        sleep 1
      done
      ;;
    *)
      fail "Unsupported SSH_READY_PROBE: ${SSH_READY_PROBE}"
      ;;
  esac
}

run_qemu_cmd() {
  build_qemu_cmd

  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    print_cmd "${QEMU_CMD[@]}"
    return 0
  fi

  "${QEMU_CMD[@]}"
}

main() {
  ensure_dirs
  validate_host_disks
  validate_net_backend
  validate_display_backend
  validate_vsock_backend
  ensure_base_image
  ensure_overlay_image
  ensure_seed_iso
  log "Using base image: ${BASE_IMAGE_PATH}"
  log "Overlay image: ${OVERLAY_IMAGE}"
  log "SSH target after boot: ssh -p ${SSH_FORWARD_PORT} root@${SSH_FORWARD_HOST}"
  if [[ "${QEMU_ENABLE_VSOCK}" == '1' ]]; then
    log "Guest vsock enabled with CID ${QEMU_VSOCK_CID}; if the serial log advertises an 'ssh vsock%%...' target, use the guest banner's exact command"
  fi
  run_qemu_cmd
  wait_for_ssh_ready
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
