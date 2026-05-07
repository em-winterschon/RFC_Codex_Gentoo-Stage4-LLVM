#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-stage3-vm.sh"

# shellcheck disable=SC1091
# shellcheck source=../../gentoo-virt-qemu/qemu-launch-stage3-vm.sh
source "${LAUNCH_SCRIPT}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  [[ "${actual}" == "${expected}" ]] || fail "expected '${expected}', got '${actual}'"
}

mark_stage3_launch_globals_used() {
  : "${QEMU_BIN-}" \
    "${QEMU_MACHINE-}" \
    "${QEMU_CPU-}" \
    "${QEMU_SMP-}" \
    "${QEMU_MEMORY_MIB-}" \
    "${QEMU_BOOT_STRICT-}" \
    "${QEMU_LAUNCH_DRY_RUN-}" \
    "${QEMU_DAEMONIZE-}" \
    "${QEMU_DISPLAY_MODE-}" \
    "${QEMU_VIDEO_DEVICE-}" \
    "${QEMU_VIDEO_DEVICE_HELP_OUTPUT-}" \
    "${QEMU_SPICE_PORT-}" \
    "${QEMU_SPICE_ADDRESS-}" \
    "${QEMU_SPICE_OPTIONS-}" \
    "${QEMU_SPICE_AGENT-}" \
    "${QEMU_BOOT_SOURCE-}" \
    "${QEMU_SERIAL_MODE-}" \
    "${QEMU_NETWORK_MODE-}" \
    "${QEMU_SERIAL_FILE-}" \
    "${QEMU_NETDEV_MODEL-}" \
    "${QEMU_NETDEV_BACKEND-}" \
    "${QEMU_NET_ALIAS_DEV-}" \
    "${QEMU_NET_ALIAS_CIDR-}" \
    "${QEMU_NET_ALIAS_SUBNET-}" \
    "${QEMU_NET_ALIAS_GUEST_IPV4-}" \
    "${QEMU_TAP_IFNAME-}" \
    "${QEMU_BRIDGE_IFNAME-}" \
    "${QEMU_TAP_HOST_CIDR-}" \
    "${QEMU_NETDEV_HELP_OUTPUT-}" \
    "${QEMU_DISPLAY_HELP_OUTPUT-}" \
    "${IP_BIN-}" \
    "${HOST_DISK_CACHE-}" \
    "${HOST_DISK_AIO-}" \
    "${QEMU_MEMORY_DRIVES_FILE-}" \
    "${WAIT_FOR_SSH-}" \
    "${SSH_READY_PROBE-}" \
    "${SSH_READY_HOST-}" \
    "${SSH_READY_PORT-}" \
    "${SSH_WAIT_TIMEOUT-}" \
    "${SSH_BANNER_TIMEOUT-}" \
    "${LAUNCHER_LOG_ENABLE-}" \
    "${LAUNCHER_LOG_DIR-}" \
    "${LAUNCHER_LOG_FILE-}" \
    "${LAUNCHER_LOG_TIMESTAMP-}" \
    "${LAUNCHER_LOG_INITIALIZED-}" \
    "${ALLOCATED_SERIAL_PTY-}" \
    "${RESOLVED_QEMU_NETDEV_BACKEND-}" \
    "${RESOLVED_SSH_READY_HOST-}"
}

reset_launcher_state() {
  INSTANCE_NAME='gentoo-stage4-testvm'
  STAGE3_IMAGE_DIR='/tmp/stage3'
  QCOW_IMAGE="${STAGE3_IMAGE_DIR}/images/${INSTANCE_NAME}.qcow2"
  QEMU_BOOT_SOURCE='qcow'
  BPOOL_DISK0='/tmp/bpool0.img'
  BPOOL_DISK1='/tmp/bpool1.img'
  RPOOL_DISK0='/tmp/rpool0.img'
  RPOOL_DISK1='/tmp/rpool1.img'
  QEMU_BIN='/usr/bin/qemu-system-x86_64'
  EFI_FIRM='/tmp/OVMF_CODE.fd'
  EFI_VARS_TEMPLATE='/tmp/OVMF_VARS.fd'
  EFI_VARS_FILE='/tmp/stage3/OVMF_VARS.fd'
  QEMU_MACHINE='q35,accel=kvm'
  QEMU_CPU='host'
  QEMU_SMP='8'
  QEMU_MEMORY_MIB='16384'
  QEMU_BOOT_STRICT='1'
  QEMU_BOOTDISK_ID='bootdisk'
  QEMU_BOOTDISK_MODEL='virtio-blk-pci'
  QEMU_BOOTDISK_BOOTINDEX='1'
  QEMU_LAUNCH_DRY_RUN='1'
  QEMU_DAEMONIZE='1'
  QEMU_DISPLAY_MODE='none'
  QEMU_VIDEO_DEVICE='auto'
  QEMU_VIDEO_DEVICE_HELP_OUTPUT=$'name "std"\nname "virtio-vga"\nname "qxl-vga"\n'
  QEMU_SPICE_PORT='5931'
  QEMU_SPICE_ADDRESS='127.0.0.1'
  QEMU_SPICE_OPTIONS='port=5931,addr=127.0.0.1,disable-ticketing=on'
  QEMU_SPICE_AGENT='1'
  QEMU_SERIAL_MODE='file'
  QEMU_SERIAL_FILE='/tmp/stage3.serial.log'
  QEMU_SERIAL_TCP='127.0.0.1:4555,server=on,wait=off,telnet=on'
  QEMU_NETWORK_MODE='user'
  QEMU_NETDEV_ID='net0'
  QEMU_NETDEV_BACKEND='user,hostfwd=tcp:127.0.0.1:2222-:22'
  QEMU_NETDEV_MODEL='virtio-net-pci'
  QEMU_NET_ALIAS_DEV='lo'
  QEMU_NET_ALIAS_CIDR='10.9.8.108/24'
  QEMU_NET_ALIAS_SUBNET='10.9.8.0/24'
  QEMU_NET_ALIAS_GUEST_IPV4='10.9.8.7'
  QEMU_TAP_IFNAME='tap-stage4'
  QEMU_BRIDGE_IFNAME=''
  QEMU_TAP_HOST_CIDR=''
  QEMU_NETDEV_HELP_OUTPUT=$'user\ntap\n'
  QEMU_DISPLAY_HELP_OUTPUT=''
  IP_BIN='/usr/sbin/ip'
  HOST_DISK_CACHE='none'
  HOST_DISK_AIO='native'
  QEMU_MEMORY_DRIVES_FILE=''
  WAIT_FOR_SSH='0'
  SSH_READY_PROBE='banner'
  SSH_READY_HOST='127.0.0.1'
  SSH_READY_PORT='2222'
  SSH_WAIT_TIMEOUT='120'
  SSH_BANNER_TIMEOUT='5'
  LAUNCHER_LOG_ENABLE='0'
  LAUNCHER_LOG_DIR='/tmp'
  LAUNCHER_LOG_FILE=''
  LAUNCHER_LOG_TIMESTAMP='2026-0421-1830_1234567890.UTC+0000'
  LAUNCHER_LOG_INITIALIZED=0
  ALLOCATED_SERIAL_PTY=''
  RESOLVED_QEMU_NETDEV_BACKEND=''
  RESOLVED_SSH_READY_HOST=''
  QEMU_CMD=()
  mark_stage3_launch_globals_used
}

test_default_launcher_log_file_uses_requested_format() {
  local logfile

  reset_launcher_state
  logfile="$(default_launcher_log_file)"
  assert_equals "${logfile}" "/tmp/qemu-launch-stage3-vm.sh.${PPID}-${$}.2026-0421-1830_1234567890.UTC+0000.log"
}

test_build_qemu_cmd_uses_boot_disk_and_tcp_serial() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  QCOW_IMAGE="${temp_dir}/vm.qcow2"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_SERIAL_MODE='tcp'
  : > "${QCOW_IMAGE}"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" '-boot strict=on'
  assert_contains "${rendered}" "if=pflash,format=raw,readonly=on,file=${EFI_FIRM}"
  assert_contains "${rendered}" "if=pflash,format=raw,file=${EFI_VARS_FILE}"
  assert_contains "${rendered}" "if=none,id=${QEMU_BOOTDISK_ID},file=${QCOW_IMAGE},format=qcow2"
  assert_contains "${rendered}" "${QEMU_BOOTDISK_MODEL},drive=${QEMU_BOOTDISK_ID},bootindex=${QEMU_BOOTDISK_BOOTINDEX},serial=stage3-boot"
  assert_contains "${rendered}" "tcp:${QEMU_SERIAL_TCP}"
  assert_contains "${rendered}" "hostfwd=tcp:127.0.0.1:2222-:22,id=${QEMU_NETDEV_ID}"
  assert_contains "${rendered}" 'file=/tmp'
  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_supports_pty_serial() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  QCOW_IMAGE="${temp_dir}/vm.qcow2"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_SERIAL_MODE='pty'
  : > "${QCOW_IMAGE}"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" '-serial pty'
  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_supports_target_disk_boot() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  QCOW_IMAGE="${temp_dir}/vm.qcow2"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_BOOT_SOURCE='target-disks'
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  [[ "${rendered}" != *"file=${QCOW_IMAGE},format=qcow2"* ]] || fail 'target-disks boot should not attach the QCOW boot disk'
  assert_contains "${rendered}" 'ide-hd,drive=bpool0,bus=ahci.1,serial=bpool-0,bootindex=1'
  assert_contains "${rendered}" 'ide-hd,drive=bpool1,bus=ahci.2,serial=bpool-1'
  assert_contains "${rendered}" '-boot strict=on'
  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_supports_alias_network_mode() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  QCOW_IMAGE="${temp_dir}/vm.qcow2"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_NETWORK_MODE='alias'
  : > "${QCOW_IMAGE}"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" 'user,net=10.9.8.0/24,host=10.9.8.108,dhcpstart=10.9.8.7,hostfwd=tcp:10.9.8.108:2222-:22,id=net0'
  assert_equals "${RESOLVED_SSH_READY_HOST}" '10.9.8.108'
  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_supports_memory_drive_manifest() {
  local temp_dir manifest rendered
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  QCOW_IMAGE="${temp_dir}/vm.qcow2"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  manifest="${temp_dir}/memory-drives.json"
  cat > "${manifest}" << EOF
{"drives":[{"path":"${temp_dir}/mem0.qcow2","format":"qcow2","serial":"mem-portage-cache","device_model":"virtio-blk-pci"}]}
EOF
  QEMU_MEMORY_DRIVES_FILE="${manifest}"
  : > "${QCOW_IMAGE}"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"
  : > "${temp_dir}/mem0.qcow2"

  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" "if=none,id=memdrv0,file=${temp_dir}/mem0.qcow2,format=qcow2"
  assert_contains "${rendered}" "virtio-blk-pci,drive=memdrv0,serial=mem-portage-cache"
  rm -rf "${temp_dir}"
}

test_validate_boot_source_rejects_invalid_value() {
  local output status

  reset_launcher_state
  QEMU_BOOT_SOURCE='nope'

  set +e
  output="$(validate_boot_source 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '1'
  assert_contains "${output}" 'Unsupported QEMU_BOOT_SOURCE'
}

test_main_dry_run_prints_stage3_vm_command() {
  local temp_dir output status
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  QCOW_IMAGE="${temp_dir}/vm.qcow2"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  : > "${QCOW_IMAGE}"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  set +e
  output="$(main 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '0'
  assert_contains "${output}" 'QCOW image:'
  assert_contains "${output}" '/usr/bin/qemu-system-x86_64'
  assert_contains "${output}" '-boot strict=on'
  assert_contains "${output}" 'ssh -p 2222 root@127.0.0.1'
  assert_contains "${output}" '[COMPLETE]'
  rm -rf "${temp_dir}"
}

test_main_dry_run_prints_target_disk_boot_plan() {
  local temp_dir output status
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_BOOT_SOURCE='target-disks'
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  set +e
  output="$(main 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '0'
  assert_contains "${output}" 'Boot source: target-disks'
  assert_contains "${output}" 'Target-disk boot: prioritizing'
  assert_contains "${output}" 'bootindex=1'
  [[ "${output}" != *"QCOW image:"* ]] || fail 'target-disk boot should not log a QCOW image'
  rm -rf "${temp_dir}"
}

test_video_device_defaults_to_qxl_for_spice() {
  reset_launcher_state
  QEMU_DISPLAY_MODE='spice'
  assert_equals 'qxl-vga' "$(video_device_name)"
}

test_validate_display_backend_rejects_missing_spice() {
  local output status

  reset_launcher_state
  QEMU_DISPLAY_MODE='spice'
  QEMU_BIN='/tmp/fake-qemu'

  qemu_help_output() {
    printf '%s\n' 'QEMU options without spice'
  }

  set +e
  output="$(validate_display_backend 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '1'
  assert_contains "${output}" 'USE=spice'
}

test_build_qemu_cmd_supports_spice_qxl_and_agent() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  QCOW_IMAGE="${temp_dir}/vm.qcow2"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_DISPLAY_MODE='spice'
  QEMU_VIDEO_DEVICE='qxl-vga'
  QEMU_SPICE_PORT='5931'
  QEMU_SPICE_ADDRESS='127.0.0.1'
  QEMU_SPICE_OPTIONS='port=5931,addr=127.0.0.1,disable-ticketing=on'
  : > "${QCOW_IMAGE}"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" '-display none'
  assert_contains "${rendered}" '-spice port=5931,addr=127.0.0.1,disable-ticketing=on'
  assert_contains "${rendered}" '-device qxl-vga'
  assert_contains "${rendered}" '-device virtio-serial-pci'
  assert_contains "${rendered}" 'name=com.redhat.spice.0'
  rm -rf "${temp_dir}"
}

test_default_launcher_log_file_uses_requested_format
test_build_qemu_cmd_uses_boot_disk_and_tcp_serial
test_build_qemu_cmd_supports_pty_serial
test_build_qemu_cmd_supports_target_disk_boot
test_build_qemu_cmd_supports_alias_network_mode
test_build_qemu_cmd_supports_memory_drive_manifest
test_video_device_defaults_to_qxl_for_spice
test_validate_display_backend_rejects_missing_spice
test_build_qemu_cmd_supports_spice_qxl_and_agent
test_validate_boot_source_rejects_invalid_value
test_main_dry_run_prints_stage3_vm_command
test_main_dry_run_prints_target_disk_boot_plan

printf 'PASS: %s\n' "$(basename "$0")"
