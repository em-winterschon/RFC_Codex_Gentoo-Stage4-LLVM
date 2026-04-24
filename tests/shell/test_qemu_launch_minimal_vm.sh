#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-minimal-vm.sh"

# shellcheck disable=SC1091,SC2034
# shellcheck source=../../gentoo-virt-qemu/qemu-launch-minimal-vm.sh
source "${LAUNCH_SCRIPT}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_exists() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  [[ "${expected}" == "${actual}" ]] || fail "expected '${expected}', got '${actual}'"
}

mark_launch_globals_used() {
  : "${BASE_DIR}" \
    "${QEMU_BIN}" \
    "${QEMU_DISPLAY_HELP_OUTPUT}" \
    "${QEMU_DISPLAY_MODE}" \
    "${QEMU_HELP_OUTPUT}" \
    "${QEMU_LAUNCH_DRY_RUN}" \
    "${QEMU_NETDEV_HELP_OUTPUT}" \
    "${QEMU_SERIAL_MODE}" \
    "${QEMU_SERIAL_TCP}" \
    "${QEMU_SPICE_OPTIONS}" \
    "${QEMU_VNC_ADDRESS}" \
    "${SYSFS_ROOT}" \
    "${VFIO_DEV_ROOT}"
}

setup_vfio_noiommu_device() {
  local temp_root="$1"
  local dev="$2"
  local group_id="$3"
  local canonical_dev driver_root device_root group_root vfio_root

  canonical_dev="$(canonicalize_pci_bdf "${dev}")"
  driver_root="${temp_root}/sys/bus/pci/drivers/vfio-pci"
  device_root="${temp_root}/sys/bus/pci/devices/${canonical_dev}"
  group_root="${temp_root}/sys/kernel/iommu_groups/${group_id}"
  vfio_root="${temp_root}/dev/vfio"

  mkdir -p "${driver_root}" "${device_root}" "${group_root}" "${vfio_root}"
  ln -s "${driver_root}" "${device_root}/driver"
  ln -s "${group_root}" "${device_root}/iommu_group"
  : >"${vfio_root}/noiommu-${group_id}"
}

test_prepare_iso_moves_original() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  BASE_DIR="${temp_dir}"
  ISO_ORIG="${temp_dir}/orig.iso"
  ISO_INST="${temp_dir}/dest.iso"
  : >"${ISO_ORIG}"

  prepare_iso

  assert_file_exists "${ISO_INST}"
  assert_not_exists "${ISO_ORIG}"
  rm -rf "${temp_dir}"
}

test_prepare_iso_accepts_existing_installer_iso() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  BASE_DIR="${temp_dir}"
  ISO_ORIG="${temp_dir}/missing.iso"
  ISO_INST="${temp_dir}/gentoo.iso"
  : >"${ISO_INST}"

  prepare_iso

  assert_file_exists "${ISO_INST}"
  rm -rf "${temp_dir}"
}

test_validate_host_disks_rejects_missing_path() {
  local temp_dir output
  temp_dir="$(mktemp -d)"

  BPOOL_DISK0="${temp_dir}/missing-bpool0"
  BPOOL_DISK1="${temp_dir}/missing-bpool1"
  RPOOL_DISK0="${temp_dir}/missing-rpool0"
  RPOOL_DISK1="${temp_dir}/missing-rpool1"

  if output="$(validate_host_disks 2>&1)"; then
    fail 'expected validate_host_disks to fail for missing paths'
  fi

  assert_contains "${output}" 'BPOOL_DISK0 is missing'
  rm -rf "${temp_dir}"
}

test_validate_net_backend_rejects_missing_user_backend() {
  local output

  QEMU_NETDEV_BACKEND='user'
  QEMU_NETDEV_HELP_OUTPUT=$'socket\ntap\nvde\n'
  mark_launch_globals_used

  if output="$(validate_net_backend 2>&1)"; then
    fail 'expected validate_net_backend to fail when user backend is unavailable'
  fi

  assert_contains "${output}" 'rebuild QEMU with USE=slirp'
}

test_validate_net_backend_accepts_tap_backend() {
  QEMU_NETDEV_BACKEND='tap,ifname=tap0,script=no,downscript=no'
  QEMU_NETDEV_HELP_OUTPUT=$'socket\ntap\nuser\n'
  mark_launch_globals_used
  validate_net_backend
}

test_validate_display_backend_rejects_missing_spice() {
  local output

  QEMU_DISPLAY_MODE='spice'
  QEMU_HELP_OUTPUT=$'-machine\n-vnc\n'
  mark_launch_globals_used

  if output="$(validate_display_backend 2>&1)"; then
    fail 'expected validate_display_backend to fail when spice support is unavailable'
  fi

  assert_contains "${output}" 'USE=spice'
  assert_contains "${output}" 'virt-viewer'
}

test_validate_display_backend_accepts_gtk() {
  QEMU_DISPLAY_MODE='gtk'
  QEMU_DISPLAY_HELP_OUTPUT=$'none\ngtk\nsdl\n'
  mark_launch_globals_used
  validate_display_backend
}

test_video_device_defaults_to_qxl_for_spice() {
  QEMU_DISPLAY_MODE='spice'
  QEMU_VIDEO_DEVICE='auto'
  mark_launch_globals_used
  assert_equals 'qxl-vga' "$(video_device_name)"
}

test_video_device_defaults_to_virtio_vga_for_gtk() {
  QEMU_DISPLAY_MODE='gtk'
  QEMU_VIDEO_DEVICE='auto'
  mark_launch_globals_used
  assert_equals 'virtio-vga' "$(video_device_name)"
}

test_validate_video_device_rejects_missing_qxl() {
  local output

  QEMU_DISPLAY_MODE='spice'
  QEMU_VIDEO_DEVICE='auto'
  QEMU_VIDEO_DEVICE_HELP_OUTPUT=$'name "virtio-vga"\nname "virtio-net-pci"\n'
  mark_launch_globals_used

  if output="$(validate_video_device 2>&1)"; then
    fail 'expected validate_video_device to fail when qxl-vga is unavailable'
  fi

  assert_contains "${output}" "video device 'qxl-vga'"
}

test_serial_mode_defaults_to_integrated_in_nographic() {
  QEMU_DISPLAY_MODE='nographic'
  QEMU_SERIAL_MODE='auto'
  mark_launch_globals_used
  assert_equals 'integrated' "$(serial_mode_name)"
}

test_serial_mode_defaults_to_stdio_for_graphical_modes() {
  QEMU_DISPLAY_MODE='vnc'
  QEMU_SERIAL_MODE='auto'
  mark_launch_globals_used
  assert_equals 'stdio' "$(serial_mode_name)"
}

test_append_serial_args_rejects_unknown_mode() {
  local output

  QEMU_DISPLAY_MODE='spice'
  QEMU_SERIAL_MODE='bogus'
  mark_launch_globals_used

  if output="$(append_serial_args 2>&1)"; then
    fail 'expected append_serial_args to fail for an unknown serial mode'
  fi

  assert_contains "${output}" 'Unsupported QEMU_SERIAL_MODE: bogus'
  assert_contains "${output}" 'supported: auto, stdio, pty, tcp, none'
}

test_build_qemu_cmd_uses_vnc_and_stdio_serial() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  ISO_INST="${temp_dir}/test.iso"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  QEMU_BIN="/usr/bin/qemu-system-x86_64"
  PCI_NETWK=''
  QEMU_DISPLAY_MODE='vnc'
  QEMU_SERIAL_MODE='stdio'
  QEMU_VNC_ADDRESS='127.0.0.1:4'
  QEMU_VIDEO_DEVICE='virtio-vga'
  mark_launch_globals_used
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"
  : > "${ISO_INST}"
  : > "${EFI_FIRM}"

  build_qemu_cmd

  rendered="${QEMU_CMD[*]}"
  assert_contains "${rendered}" '-device virtio-vga'
  assert_contains "${rendered}" '-display none'
  assert_contains "${rendered}" '-vnc 127.0.0.1:4'
  assert_contains "${rendered}" '-serial mon:stdio'
  assert_contains "${rendered}" 'virtio-net-pci,netdev=net0'
  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_uses_spice_qxl_and_tcp_serial() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  ISO_INST="${temp_dir}/test.iso"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  PCI_NETWK=''
  QEMU_DISPLAY_MODE='spice'
  QEMU_SERIAL_MODE='tcp'
  QEMU_SPICE_OPTIONS='port=5930,addr=0.0.0.0,disable-ticketing=on'
  QEMU_SERIAL_TCP='0.0.0.0:4555,server=on,wait=off,telnet=on'
  QEMU_VIDEO_DEVICE='auto'
  mark_launch_globals_used
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"
  : > "${ISO_INST}"
  : > "${EFI_FIRM}"

  build_qemu_cmd

  rendered="${QEMU_CMD[*]}"
  assert_contains "${rendered}" '-device qxl-vga'
  assert_contains "${rendered}" '-spice port=5930,addr=0.0.0.0,disable-ticketing=on'
  assert_contains "${rendered}" '-serial tcp:0.0.0.0:4555,server=on,wait=off,telnet=on'
  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_uses_host_disks_and_virtio_net() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  ISO_INST="${temp_dir}/test.iso"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  QEMU_BIN="/usr/bin/qemu-system-x86_64"
  PCI_NETWK=''
  QEMU_DISPLAY_MODE='nographic'
  QEMU_SERIAL_MODE='auto'
  QEMU_VIDEO_DEVICE='std'
  mark_launch_globals_used
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"
  : > "${ISO_INST}"
  : > "${EFI_FIRM}"

  build_qemu_cmd

  rendered="${QEMU_CMD[*]}"
  assert_contains "${rendered}" '-vga std'
  assert_contains "${rendered}" 'ich9-ahci,id=ahci'
  assert_contains "${rendered}" "file=${BPOOL_DISK0},format=raw,cache=${HOST_DISK_CACHE},aio=${HOST_DISK_AIO}"
  assert_contains "${rendered}" "file=${RPOOL_DISK1},format=raw,cache=${HOST_DISK_CACHE},aio=${HOST_DISK_AIO}"
  assert_contains "${rendered}" 'serial=bpool-0'
  assert_contains "${rendered}" 'serial=rpool-1'
  assert_contains "${rendered}" "${QEMU_NETDEV_BACKEND},id=${QEMU_NETDEV_ID}"
  assert_contains "${rendered}" "${QEMU_NETDEV_MODEL},netdev=${QEMU_NETDEV_ID}"
  assert_contains "${rendered}" '-nographic'
  [[ "${rendered}" != *'vfio-pci,host='* ]] || fail 'unexpected default PCI passthrough NIC'
  rm -rf "${temp_dir}"
}

test_blank_env_overrides_defaults_in_fresh_process() {
  local output

  output="$(bash --noprofile --norc -c 'PCI_NETWK=; source "$1"; printf "%s\n" "$PCI_NETWK"' _ "${LAUNCH_SCRIPT}")"
  assert_equals '' "${output}"
}

test_validate_passthrough_devices_rejects_vfio_noiommu_group() {
  local temp_dir output
  temp_dir="$(mktemp -d)"

  SYSFS_ROOT="${temp_dir}/sys"
  VFIO_DEV_ROOT="${temp_dir}/dev/vfio"
  PCI_NETWK='02:00.0'
  mark_launch_globals_used
  setup_vfio_noiommu_device "${temp_dir}" "${PCI_NETWK}" '2'

  if output="$(validate_passthrough_devices 2>&1)"; then
    fail 'expected validate_passthrough_devices to fail for vfio-noiommu only devices'
  fi

  assert_contains "${output}" '/dev/vfio/noiommu-2'
  assert_contains "${output}" 'requires a real IOMMU-backed'
  rm -rf "${temp_dir}"
}

test_main_dry_run_prints_command() {
  local temp_dir output
  temp_dir="$(mktemp -d)"

  BASE_DIR="${temp_dir}"
  ISO_ORIG="${temp_dir}/missing.iso"
  ISO_INST="${temp_dir}/gentoo.iso"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_LAUNCH_DRY_RUN=1
  QEMU_NETDEV_BACKEND='user'
  QEMU_NETDEV_HELP_OUTPUT=$'user\ntap\n'
  QEMU_DISPLAY_MODE='nographic'
  QEMU_SERIAL_MODE='auto'
  QEMU_VIDEO_DEVICE='std'
  QEMU_VIDEO_DEVICE_HELP_OUTPUT='name "std"'
  PCI_NETWK=''
  mark_launch_globals_used
  : > "${ISO_INST}"
  : > "${EFI_FIRM}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  output="$(main 2>&1)"

  assert_contains "${output}" 'Resolved display mode: nographic (video: std)'
  assert_contains "${output}" 'Resolved serial mode: integrated'
  assert_contains "${output}" 'Launching QEMU VM'
  assert_contains "${output}" 'qemu-system-x86_64'
  assert_contains "${output}" "file=${BPOOL_DISK0}"
  assert_contains "${output}" "file=${RPOOL_DISK1}"
  assert_contains "${output}" 'virtio-net-pci\,netdev=net0'
  assert_contains "${output}" '[COMPLETE]'
  rm -rf "${temp_dir}"
}

test_prepare_iso_moves_original
test_prepare_iso_accepts_existing_installer_iso
test_validate_host_disks_rejects_missing_path
test_validate_net_backend_rejects_missing_user_backend
test_validate_net_backend_accepts_tap_backend
test_validate_display_backend_rejects_missing_spice
test_validate_display_backend_accepts_gtk
test_video_device_defaults_to_qxl_for_spice
test_video_device_defaults_to_virtio_vga_for_gtk
test_validate_video_device_rejects_missing_qxl
test_serial_mode_defaults_to_integrated_in_nographic
test_serial_mode_defaults_to_stdio_for_graphical_modes
test_append_serial_args_rejects_unknown_mode
test_build_qemu_cmd_uses_vnc_and_stdio_serial
test_build_qemu_cmd_uses_spice_qxl_and_tcp_serial
test_build_qemu_cmd_uses_host_disks_and_virtio_net
test_blank_env_overrides_defaults_in_fresh_process
test_validate_passthrough_devices_rejects_vfio_noiommu_group
test_main_dry_run_prints_command

printf 'PASS: %s\n' "$(basename "$0")"
