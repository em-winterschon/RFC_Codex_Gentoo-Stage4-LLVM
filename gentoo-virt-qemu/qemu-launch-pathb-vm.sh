#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_PATHB_TRACE:-0}" == '1' ]]; then
  set -x
fi

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
QEMU_PATHB_SOURCE_ONLY="${QEMU_PATHB_SOURCE_ONLY:-0}"
INSTANCE_NAME="${INSTANCE_NAME:-pathb-ipxe-client}"
QEMU_VM_DIR="${QEMU_VM_DIR:-/opt/gentoo-netboot/path-b/vms/${INSTANCE_NAME}}"
QEMU_ROOTDISK="${QEMU_ROOTDISK:-${QEMU_VM_DIR}/${INSTANCE_NAME}.qcow2}"
QEMU_IPXE_EFI_DIR="${QEMU_IPXE_EFI_DIR:-${QEMU_VM_DIR}/ipxe-efi}"
QEMU_PATHB_BOOT_MODE="${QEMU_PATHB_BOOT_MODE:-ipxe}"
QEMU_DIRECT_KERNEL="${QEMU_DIRECT_KERNEL:-/var/lib/netboot/path-b/artifacts/gentoo-installer/vmlinuz}"
QEMU_DIRECT_INITRD="${QEMU_DIRECT_INITRD:-/var/lib/netboot/path-b/artifacts/gentoo-installer/initramfs.img}"
QEMU_DIRECT_ROOTFS_URL="${QEMU_DIRECT_ROOTFS_URL:-http://10.9.8.108:8080/g/rootfs.img}"
QEMU_DIRECT_APPEND="${QEMU_DIRECT_APPEND:-console=tty0 console=ttyS0,115200 ip=dhcp rd.neednet=1 rd.live.image root=live:${QEMU_DIRECT_ROOTFS_URL}}"
QEMU_BIN="${QEMU_BIN:-/usr/bin/qemu-system-x86_64}"
EFI_FIRM="${EFI_FIRM:-/usr/share/edk2-ovmf/OVMF_CODE.fd}"
EFI_VARS_TEMPLATE="${EFI_VARS_TEMPLATE:-/usr/share/edk2-ovmf/OVMF_VARS.fd}"
EFI_VARS_FILE="${EFI_VARS_FILE:-${QEMU_VM_DIR}/OVMF_VARS.fd}"
EFI_FIRM_FORMAT="${EFI_FIRM_FORMAT:-}"
EFI_VARS_FORMAT="${EFI_VARS_FORMAT:-}"
QEMU_MACHINE="${QEMU_MACHINE:-q35,accel=kvm}"
QEMU_CPU="${QEMU_CPU:-host}"
QEMU_SMP="${QEMU_SMP:-16}"
QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB:-32768}"
QEMU_NETDEV_MODEL="${QEMU_NETDEV_MODEL:-e1000}"
QEMU_MAC_ADDRESS="${QEMU_MAC_ADDRESS:-52:54:00:12:34:78}"
QEMU_TAP_IFNAME="${QEMU_TAP_IFNAME:-tap-${INSTANCE_NAME}}"
QEMU_BRIDGE_IFNAME="${QEMU_BRIDGE_IFNAME:-br-pathb}"
QEMU_DISPLAY_MODE="${QEMU_DISPLAY_MODE:-none}"
QEMU_SERIAL_MODE="${QEMU_SERIAL_MODE:-telnet}"
QEMU_SERIAL_HOST="${QEMU_SERIAL_HOST:-127.0.0.1}"
QEMU_SERIAL_PORT="${QEMU_SERIAL_PORT:-5003}"
QEMU_SERIAL_FILE="${QEMU_SERIAL_FILE:-/tmp/${INSTANCE_NAME}.serial.log}"
QEMU_MEMORY_DRIVES_FILE="${QEMU_MEMORY_DRIVES_FILE:-}"
QEMU_RESET_EFI_VARS="${QEMU_RESET_EFI_VARS:-0}"
QEMU_DAEMONIZE="${QEMU_DAEMONIZE:-1}"
QEMU_LAUNCH_DRY_RUN="${QEMU_LAUNCH_DRY_RUN:-0}"
IP_BIN="${IP_BIN:-/usr/sbin/ip}"
HOST_DISK_CACHE="${HOST_DISK_CACHE:-writeback}"
LAUNCHER_LOG_ENABLE="${LAUNCHER_LOG_ENABLE:-1}"
LAUNCHER_LOG_DIR="${LAUNCHER_LOG_DIR:-/tmp}"
LAUNCHER_LOG_FILE="${LAUNCHER_LOG_FILE:-}"
LAUNCHER_LOG_INITIALIZED=0
QEMU_CMD=()

log() {
  printf '[qemu-launch-pathb-vm] %s\n' "$*"
}

fail() {
  printf '[qemu-launch-pathb-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

launcher_log_timestamp() {
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

require_file() {
  local path="$1"
  local label="$2"
  [[ -f "${path}" ]] || fail "${label} is missing: ${path}"
}

require_dir() {
  local path="$1"
  local label="$2"
  [[ -d "${path}" ]] || fail "${label} is missing: ${path}"
}

resolve_nonempty_file() {
  local candidate

  for candidate in "$@"; do
    [[ -n "${candidate}" ]] || continue
    if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' && -f "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
    if [[ -f "${candidate}" && -s "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  return 1
}

resolve_ovmf_paths() {
  EFI_FIRM="$(
    resolve_nonempty_file \
      "${EFI_FIRM}" \
      /usr/share/edk2/OvmfX64/OVMF_CODE.fd \
      /usr/share/edk2/OvmfX64/OVMF_CODE_4M.qcow2 \
      /usr/share/edk2/OvmfX64/OVMF_CODE.secboot.fd
  )" || fail "No usable OVMF code image found; checked ${EFI_FIRM} and standard edk2 paths"

  EFI_VARS_TEMPLATE="$(
    resolve_nonempty_file \
      "${EFI_VARS_TEMPLATE}" \
      /usr/share/edk2/OvmfX64/OVMF_VARS.fd \
      /usr/share/edk2/OvmfX64/OVMF_VARS_4M.qcow2 \
      /usr/share/edk2/OvmfX64/OVMF_VARS.secboot.fd
  )" || fail "No usable OVMF vars template found; checked ${EFI_VARS_TEMPLATE} and standard edk2 paths"
}

infer_qemu_image_format() {
  case "$1" in
  *.qcow2)
    printf 'qcow2'
    ;;
  *)
    printf 'raw'
    ;;
  esac
}

resolve_ovmf_formats() {
  if [[ -z "${EFI_FIRM_FORMAT}" ]]; then
    EFI_FIRM_FORMAT="$(infer_qemu_image_format "${EFI_FIRM}")"
  fi
  if [[ -z "${EFI_VARS_FORMAT}" ]]; then
    EFI_VARS_FORMAT="$(infer_qemu_image_format "${EFI_VARS_TEMPLATE}")"
  fi
}

require_host_disk_ready() {
  local path="$1"
  local label="$2"
  [[ -n "${path}" ]] || fail "${label} is empty"
  [[ -e "${path}" ]] || fail "${label} is missing: ${path}"
}

ensure_kvm_device() {
  local kvm_minor

  if [[ -e /dev/kvm ]]; then
    return 0
  fi

  kvm_minor="$(awk '$2 == "kvm" { print $1 }' /proc/misc 2> /dev/null || true)"
  [[ -n "${kvm_minor}" ]] || fail '/dev/kvm is missing and kvm is not registered in /proc/misc'

  if ! getent group kvm > /dev/null 2>&1; then
    fail '/dev/kvm is missing and group kvm is unavailable'
  fi

  mknod /dev/kvm c 10 "${kvm_minor}"
  chown root:kvm /dev/kvm
  chmod 660 /dev/kvm
}

ensure_tap_interface() {
  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  "${IP_BIN}" link show dev "${QEMU_BRIDGE_IFNAME}" > /dev/null 2>&1 || fail "Bridge interface is missing: ${QEMU_BRIDGE_IFNAME}"

  if ! "${IP_BIN}" link show dev "${QEMU_TAP_IFNAME}" > /dev/null 2>&1; then
    "${IP_BIN}" tuntap add dev "${QEMU_TAP_IFNAME}" mode tap user root
  fi

  "${IP_BIN}" link set "${QEMU_TAP_IFNAME}" master "${QEMU_BRIDGE_IFNAME}"
  "${IP_BIN}" link set "${QEMU_TAP_IFNAME}" up
}

prepare_ovmf_vars_file() {
  mkdir -p "$(dirname "${EFI_VARS_FILE}")"
  if [[ "${QEMU_RESET_EFI_VARS}" == '1' || ! -f "${EFI_VARS_FILE}" ]]; then
    cp "${EFI_VARS_TEMPLATE}" "${EFI_VARS_FILE}"
  fi
}

append_memory_drives() {
  local index=0
  local drive_id drive_path drive_format drive_serial drive_model drive_bootindex

  [[ -n "${QEMU_MEMORY_DRIVES_FILE}" ]] || return 0
  require_file "${QEMU_MEMORY_DRIVES_FILE}" 'QEMU_MEMORY_DRIVES_FILE'

  while IFS=$'\t' read -r drive_path drive_format drive_serial drive_model drive_bootindex; do
    [[ -n "${drive_path}" ]] || continue
    require_host_disk_ready "${drive_path}" "QEMU memory drive ${drive_serial:-memory-${index}}"
    drive_id="memdrv${index}"
    QEMU_CMD+=(-drive "if=none,id=${drive_id},file=${drive_path},format=${drive_format},cache=${HOST_DISK_CACHE}")
    if [[ -n "${drive_bootindex}" ]]; then
      QEMU_CMD+=(-device "${drive_model},drive=${drive_id},serial=${drive_serial},bootindex=${drive_bootindex}")
    else
      QEMU_CMD+=(-device "${drive_model},drive=${drive_id},serial=${drive_serial}")
    fi
    index=$((index + 1))
  done < <(
    python3 - "${QEMU_MEMORY_DRIVES_FILE}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

drives = payload.get("drives", payload if isinstance(payload, list) else [])
for drive in drives:
    print(
        "\t".join(
            [
                str(drive.get("path", "")),
                str(drive.get("format", "qcow2")),
                str(drive.get("serial", "")),
                str(drive.get("device_model", "virtio-blk-pci")),
                str(drive.get("bootindex", "")),
            ]
        )
    )
PY
  )
}

append_display_args() {
  case "${QEMU_DISPLAY_MODE}" in
  none)
    QEMU_CMD+=(-display none)
    ;;
  gtk | sdl)
    QEMU_CMD+=(-display "${QEMU_DISPLAY_MODE}")
    ;;
  *)
    fail "Unsupported QEMU_DISPLAY_MODE: ${QEMU_DISPLAY_MODE}"
    ;;
  esac
}

append_serial_args() {
  case "${QEMU_SERIAL_MODE}" in
  telnet)
    QEMU_CMD+=(-serial "telnet:${QEMU_SERIAL_HOST}:${QEMU_SERIAL_PORT},server=on,wait=off")
    ;;
  file)
    mkdir -p "$(dirname "${QEMU_SERIAL_FILE}")"
    QEMU_CMD+=(-serial "file:${QEMU_SERIAL_FILE}")
    ;;
  stdio)
    [[ "${QEMU_DAEMONIZE}" == '0' ]] || fail 'QEMU_SERIAL_MODE=stdio requires QEMU_DAEMONIZE=0'
    QEMU_CMD+=(-serial mon:stdio)
    ;;
  *)
    fail "Unsupported QEMU_SERIAL_MODE: ${QEMU_SERIAL_MODE} (supported: telnet, file, stdio)"
    ;;
  esac
}

build_qemu_cmd() {
  QEMU_CMD=(
    "${QEMU_BIN}"
    -name "${INSTANCE_NAME}"
    -enable-kvm
    -machine "${QEMU_MACHINE}"
    -cpu "${QEMU_CPU}"
    -smp "${QEMU_SMP}"
    -m "${QEMU_MEMORY_MIB}"
  )

  case "${QEMU_PATHB_BOOT_MODE}" in
  ipxe)
    resolve_ovmf_formats
    prepare_ovmf_vars_file
    QEMU_CMD+=(
      -drive "if=pflash,format=${EFI_FIRM_FORMAT},readonly=on,unit=0,file=${EFI_FIRM}"
      -drive "if=pflash,format=${EFI_VARS_FORMAT},unit=1,file=${EFI_VARS_FILE}"
      -device 'ich9-ahci,id=ahci'
      -drive "if=none,id=efidisk,file=fat:rw:${QEMU_IPXE_EFI_DIR},format=raw,media=disk"
      -device 'ide-hd,drive=efidisk,bus=ahci.1,bootindex=1,serial=ipxe-efi'
      -drive "if=none,id=rootdisk,file=${QEMU_ROOTDISK},format=qcow2,cache=${HOST_DISK_CACHE}"
      -device 'ide-hd,drive=rootdisk,bus=ahci.2,serial=stage4-root'
    )
    ;;
  direct-kernel)
    QEMU_CMD+=(
      -device 'ich9-ahci,id=ahci'
      -drive "if=none,id=rootdisk,file=${QEMU_ROOTDISK},format=qcow2,cache=${HOST_DISK_CACHE}"
      -device 'ide-hd,drive=rootdisk,bus=ahci.1,serial=stage4-root'
      -kernel "${QEMU_DIRECT_KERNEL}"
      -initrd "${QEMU_DIRECT_INITRD}"
      -append "${QEMU_DIRECT_APPEND}"
    )
    ;;
  uefi-disk)
    resolve_ovmf_formats
    prepare_ovmf_vars_file
    QEMU_CMD+=(
      -drive "if=pflash,format=${EFI_FIRM_FORMAT},readonly=on,unit=0,file=${EFI_FIRM}"
      -drive "if=pflash,format=${EFI_VARS_FORMAT},unit=1,file=${EFI_VARS_FILE}"
      -device 'ich9-ahci,id=ahci'
      -drive "if=none,id=rootdisk,file=${QEMU_ROOTDISK},format=qcow2,cache=${HOST_DISK_CACHE}"
      -device 'ide-hd,drive=rootdisk,bus=ahci.1,bootindex=1,serial=stage4-root'
    )
    ;;
  *)
    fail "Unsupported QEMU_PATHB_BOOT_MODE: ${QEMU_PATHB_BOOT_MODE} (supported: ipxe, direct-kernel, uefi-disk)"
    ;;
  esac

  append_memory_drives

  QEMU_CMD+=(
    -netdev "tap,id=net0,ifname=${QEMU_TAP_IFNAME},script=no,downscript=no"
    -device "${QEMU_NETDEV_MODEL},netdev=net0,mac=${QEMU_MAC_ADDRESS}"
  )

  append_display_args
  append_serial_args
  QEMU_CMD+=(-monitor none)

  if [[ "${QEMU_DAEMONIZE}" == '1' ]]; then
    QEMU_CMD+=(-daemonize)
  fi
}

print_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

validate_inputs() {
  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' && ! -f "${QEMU_BIN}" ]]; then
    log "Dry-run: QEMU_BIN is not present on this host: ${QEMU_BIN}"
  else
    require_file "${QEMU_BIN}" 'QEMU_BIN'
  fi

  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' && ! -e "${QEMU_ROOTDISK}" ]]; then
    log "Dry-run: root disk is not present on this host: ${QEMU_ROOTDISK}"
  else
    require_host_disk_ready "${QEMU_ROOTDISK}" 'QEMU_ROOTDISK'
  fi

  case "${QEMU_PATHB_BOOT_MODE}" in
  ipxe)
    resolve_ovmf_paths
    resolve_ovmf_formats
    require_file "${EFI_FIRM}" 'EFI_FIRM'
    require_file "${EFI_VARS_TEMPLATE}" 'EFI_VARS_TEMPLATE'
    require_dir "${QEMU_IPXE_EFI_DIR}" 'QEMU_IPXE_EFI_DIR'
    ;;
  direct-kernel)
    require_file "${QEMU_DIRECT_KERNEL}" 'QEMU_DIRECT_KERNEL'
    require_file "${QEMU_DIRECT_INITRD}" 'QEMU_DIRECT_INITRD'
    ;;
  uefi-disk)
    resolve_ovmf_paths
    resolve_ovmf_formats
    require_file "${EFI_FIRM}" 'EFI_FIRM'
    require_file "${EFI_VARS_TEMPLATE}" 'EFI_VARS_TEMPLATE'
    ;;
  *)
    fail "Unsupported QEMU_PATHB_BOOT_MODE: ${QEMU_PATHB_BOOT_MODE} (supported: ipxe, direct-kernel, uefi-disk)"
    ;;
  esac
}

main() {
  setup_launcher_logging
  validate_inputs
  ensure_kvm_device
  ensure_tap_interface
  build_qemu_cmd

  log "VM directory: ${QEMU_VM_DIR}"
  log "Boot mode: ${QEMU_PATHB_BOOT_MODE}"
  log "Serial mode: ${QEMU_SERIAL_MODE}"
  if [[ "${QEMU_SERIAL_MODE}" == 'telnet' ]]; then
    log "Serial target: telnet ${QEMU_SERIAL_HOST} ${QEMU_SERIAL_PORT}"
  fi
  log "Tap interface: ${QEMU_TAP_IFNAME} -> ${QEMU_BRIDGE_IFNAME}"
  log "Launch command:"
  print_cmd "${QEMU_CMD[@]}"

  if [[ "${QEMU_LAUNCH_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  "${QEMU_CMD[@]}"
}

if [[ "${QEMU_PATHB_SOURCE_ONLY}" != '1' ]]; then
  main "$@"
fi
