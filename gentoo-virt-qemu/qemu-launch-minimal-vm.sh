#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_LAUNCH_TRACE:-0}" == "1" ]]; then
  set -x
fi

# Launch a basic VM with the host disks intended for the test ZFS boot pool and
# root pool, plus configurable console and display options.
# Version: 0.3.0
# MBoard: X12SPL-F

BPOOL_DISK0="${BPOOL_DISK0-/dev/disk/by-id/ata-SATADOM-SL_3IE3_V2_BCA11708020382305}"
BPOOL_DISK1="${BPOOL_DISK1-/dev/disk/by-id/ata-SATADOM-SL_3IE3_V2_BCA11708020382932}"
RPOOL_DISK0="${RPOOL_DISK0-/dev/disk/by-id/ata-HBS3A1919A7E6B1_A03A5659}"
RPOOL_DISK1="${RPOOL_DISK1-/dev/disk/by-id/ata-HBS3A1919A7E6B1_A03A58E2}"
PCI_NETWK="${PCI_NETWK-}"
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
SYSFS_ROOT="${SYSFS_ROOT:-/sys}"
VFIO_DEV_ROOT="${VFIO_DEV_ROOT:-/dev/vfio}"
HOST_DISK_CACHE="${HOST_DISK_CACHE:-none}"
HOST_DISK_AIO="${HOST_DISK_AIO:-native}"
QEMU_NETDEV_ID="${QEMU_NETDEV_ID:-net0}"
QEMU_NETDEV_BACKEND="${QEMU_NETDEV_BACKEND:-user}"
QEMU_NETDEV_MODEL="${QEMU_NETDEV_MODEL:-virtio-net-pci}"
QEMU_NETDEV_HELP_OUTPUT="${QEMU_NETDEV_HELP_OUTPUT-}"
QEMU_HELP_OUTPUT="${QEMU_HELP_OUTPUT-}"
QEMU_DISPLAY_HELP_OUTPUT="${QEMU_DISPLAY_HELP_OUTPUT-}"
QEMU_DISPLAY_MODE="${QEMU_DISPLAY_MODE:-nographic}"
QEMU_SERIAL_MODE="${QEMU_SERIAL_MODE:-auto}"
QEMU_VNC_ADDRESS="${QEMU_VNC_ADDRESS:-127.0.0.1:1}"
QEMU_SPICE_PORT="${QEMU_SPICE_PORT:-5930}"
QEMU_SPICE_OPTIONS="${QEMU_SPICE_OPTIONS:-port=${QEMU_SPICE_PORT},addr=127.0.0.1,disable-ticketing=on}"
QEMU_SERIAL_TCP="${QEMU_SERIAL_TCP:-127.0.0.1:4555,server=on,wait=off,telnet=on}"
QEMU_VIDEO_DEVICE="${QEMU_VIDEO_DEVICE:-auto}"
QEMU_VIDEO_DEVICE_HELP_OUTPUT="${QEMU_VIDEO_DEVICE_HELP_OUTPUT-}"
QEMU_CMD=()

log() {
  printf '[qemu-launch-minimal-vm] %s\n' "$*"
}

fail() {
  printf '[qemu-launch-minimal-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

canonicalize_pci_bdf() {
  local dev="$1"

  if [[ -z "${dev}" ]]; then
    return 0
  fi

  if [[ "${dev}" == 0000:* ]]; then
    printf '%s' "${dev}"
  else
    printf '0000:%s' "${dev}"
  fi
}

network_backend_name() {
  printf '%s' "${QEMU_NETDEV_BACKEND%%,*}"
}

display_mode_name() {
  printf '%s' "${QEMU_DISPLAY_MODE}"
}

serial_mode_name() {
  if [[ "${QEMU_SERIAL_MODE}" != 'auto' ]]; then
    printf '%s' "${QEMU_SERIAL_MODE}"
    return 0
  fi

  if [[ "$(display_mode_name)" == 'nographic' ]]; then
    printf 'integrated'
  else
    printf 'stdio'
  fi
}

video_device_name() {
  if [[ "${QEMU_VIDEO_DEVICE}" != 'auto' ]]; then
    printf '%s' "${QEMU_VIDEO_DEVICE}"
    return 0
  fi

  case "$(display_mode_name)" in
    spice)
      printf 'qxl-vga'
      ;;
    none|nographic)
      printf 'std'
      ;;
    *)
      printf 'virtio-vga'
      ;;
  esac
}

qemu_help_output() {
  if [[ -n "${QEMU_HELP_OUTPUT}" ]]; then
    printf '%s' "${QEMU_HELP_OUTPUT}"
    return 0
  fi

  "${QEMU_BIN}" -help 2>&1 || true
}

qemu_display_help_output() {
  if [[ -n "${QEMU_DISPLAY_HELP_OUTPUT}" ]]; then
    printf '%s' "${QEMU_DISPLAY_HELP_OUTPUT}"
    return 0
  fi

  "${QEMU_BIN}" -display help 2>&1 || true
}

qemu_device_help_output() {
  if [[ -n "${QEMU_VIDEO_DEVICE_HELP_OUTPUT}" ]]; then
    printf '%s' "${QEMU_VIDEO_DEVICE_HELP_OUTPUT}"
    return 0
  fi

  "${QEMU_BIN}" -device help 2>&1 || true
}

device_path() {
  printf '%s/bus/pci/devices/%s' "${SYSFS_ROOT}" "$(canonicalize_pci_bdf "$1")"
}

current_driver() {
  local driver_link

  driver_link="$(readlink -f "$(device_path "$1")/driver" 2>/dev/null || true)"
  if [[ -n "${driver_link}" && -e "${driver_link}" ]]; then
    basename "${driver_link}"
  fi
}

iommu_group_id() {
  local group_link

  group_link="$(readlink -f "$(device_path "$1")/iommu_group" 2>/dev/null || true)"
  if [[ -n "${group_link}" && -e "${group_link}" ]]; then
    basename "${group_link}"
  fi
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
      fail "QEMU net backend '${backend}' is not available in ${QEMU_BIN}; rebuild QEMU with USE=slirp or set QEMU_NETDEV_BACKEND to a supported backend such as tap,ifname=tap0,script=no,downscript=no"
    fi

    fail "QEMU net backend '${backend}' is not available in ${QEMU_BIN}; inspect '${QEMU_BIN} -netdev help' and set QEMU_NETDEV_BACKEND to a supported backend"
  fi
}

validate_display_backend() {
  local mode help_output

  mode="$(display_mode_name)"
  case "${mode}" in
    nographic|none)
      return 0
      ;;
    gtk|sdl)
      help_output="$(qemu_display_help_output)"
      [[ "${help_output}" == *"${mode}"* ]] || fail "QEMU display mode '${mode}' is not available in ${QEMU_BIN}; rebuild QEMU with USE=${mode} or choose a supported display mode"
      ;;
    vnc)
      help_output="$(qemu_help_output)"
      [[ "${help_output}" == *'-vnc '* ]] || fail "QEMU display mode '${mode}' is not available in ${QEMU_BIN}; rebuild QEMU with USE=vnc or choose another display mode"
      ;;
    spice)
      help_output="$(qemu_help_output)"
      [[ "${help_output}" == *'-spice '* ]] || fail "QEMU display mode '${mode}' is not available in ${QEMU_BIN}; rebuild QEMU with USE=spice and use app-emulation/virt-viewer as the client"
      ;;
    *)
      fail "Unsupported QEMU_DISPLAY_MODE: ${mode}"
      ;;
  esac
}

validate_video_device() {
  local device_name help_output

  device_name="$(video_device_name)"
  [[ -n "${device_name}" ]] || fail 'QEMU video device resolved to an empty name'

  case "${device_name}" in
    std|virtio-vga|qxl-vga)
      help_output="$(qemu_device_help_output)"
      [[ "${help_output}" == *"name \"${device_name}\""* ]] || fail "QEMU video device '${device_name}' is not available in ${QEMU_BIN}; inspect '${QEMU_BIN} -device help' and choose a supported QEMU_VIDEO_DEVICE"
      ;;
    *)
      ;;
  esac
}

require_vfio_passthrough_ready() {
  local dev="$1"
  local canonical_dev group_id group_dev noiommu_group_dev driver_name

  if [[ -z "${dev}" ]]; then
    return 0
  fi

  canonical_dev="$(canonicalize_pci_bdf "${dev}")"
  [[ -d "$(device_path "${dev}")" ]] || fail "PCI device not found: ${canonical_dev}"

  driver_name="$(current_driver "${dev}")"
  if [[ "${driver_name}" != 'vfio-pci' ]]; then
    fail "${canonical_dev} is not bound to vfio-pci (current driver: ${driver_name:-<unbound>})"
  fi

  group_id="$(iommu_group_id "${dev}")"
  if [[ -z "${group_id}" ]]; then
    fail "${canonical_dev} has no IOMMU group; QEMU vfio-pci cannot use unsafe no-IOMMU bindings here"
  fi

  group_dev="${VFIO_DEV_ROOT}/${group_id}"
  noiommu_group_dev="${VFIO_DEV_ROOT}/noiommu-${group_id}"
  if [[ -e "${noiommu_group_dev}" && ! -e "${group_dev}" ]]; then
    fail "${canonical_dev} is only available as ${noiommu_group_dev}; QEMU vfio-pci requires a real IOMMU-backed ${group_dev} device"
  fi

  [[ -e "${group_dev}" ]] || fail "${canonical_dev} is in IOMMU group ${group_id}, but ${group_dev} is missing"
}

validate_passthrough_devices() {
  require_vfio_passthrough_ready "${PCI_NETWK}"
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

append_optional_passthrough_nic() {
  if [[ -n "${PCI_NETWK}" ]]; then
    QEMU_CMD+=( -device "vfio-pci,host=${PCI_NETWK}" )
  fi
}

append_video_args() {
  local device_name

  device_name="$(video_device_name)"
  case "${device_name}" in
    std)
      QEMU_CMD+=( -vga std )
      ;;
    qxl-vga|virtio-vga)
      QEMU_CMD+=( -device "${device_name}" )
      ;;
    none)
      return 0
      ;;
    *)
      QEMU_CMD+=( -device "${device_name}" )
      ;;
  esac
}

append_display_args() {
  case "$(display_mode_name)" in
    nographic)
      QEMU_CMD+=( -nographic )
      ;;
    none)
      QEMU_CMD+=( -display none )
      ;;
    gtk|sdl)
      QEMU_CMD+=( -display "$(display_mode_name)" )
      ;;
    vnc)
      QEMU_CMD+=( -display none -vnc "${QEMU_VNC_ADDRESS}" )
      ;;
    spice)
      QEMU_CMD+=( -display none -spice "${QEMU_SPICE_OPTIONS}" )
      ;;
  esac
}

append_serial_args() {
  case "$(serial_mode_name)" in
    integrated|none)
      return 0
      ;;
    stdio)
      QEMU_CMD+=( -serial mon:stdio )
      ;;
    pty)
      QEMU_CMD+=( -serial pty )
      ;;
    tcp)
      QEMU_CMD+=( -serial "tcp:${QEMU_SERIAL_TCP}" )
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
    -device 'ich9-ahci,id=ahci'
    -drive "if=none,id=installer,file=${ISO_INST},format=raw,media=cdrom,readonly=on"
    -device 'ide-cd,drive=installer,bus=ahci.0'
  )

  append_video_args
  append_host_disk 'bpool0' "${BPOOL_DISK0}" '1' 'bpool-0'
  append_host_disk 'bpool1' "${BPOOL_DISK1}" '2' 'bpool-1'
  append_host_disk 'rpool0' "${RPOOL_DISK0}" '3' 'rpool-0'
  append_host_disk 'rpool1' "${RPOOL_DISK1}" '4' 'rpool-1'

  QEMU_CMD+=(
    -netdev "${QEMU_NETDEV_BACKEND},id=${QEMU_NETDEV_ID}"
    -device "${QEMU_NETDEV_MODEL},netdev=${QEMU_NETDEV_ID}"
  )

  append_optional_passthrough_nic
  append_display_args
  append_serial_args
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
  validate_host_disks
  validate_net_backend
  validate_display_backend
  validate_video_device
  validate_passthrough_devices
  log 'Launching QEMU VM'
  run_qemu_cmd
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
