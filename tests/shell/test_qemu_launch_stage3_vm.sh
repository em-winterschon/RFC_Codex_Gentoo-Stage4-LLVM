#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-stage3-vm.sh"

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
  QEMU_SERIAL_MODE='file'
  QEMU_SERIAL_FILE='/tmp/stage3.serial.log'
  QEMU_SERIAL_TCP='127.0.0.1:4555,server=on,wait=off,telnet=on'
  QEMU_NETDEV_ID='net0'
  QEMU_NETDEV_BACKEND='user,hostfwd=tcp:127.0.0.1:2222-:22'
  QEMU_NETDEV_MODEL='virtio-net-pci'
  QEMU_NETDEV_HELP_OUTPUT=$'user\ntap\n'
  QEMU_DISPLAY_HELP_OUTPUT=''
  HOST_DISK_CACHE='none'
  HOST_DISK_AIO='native'
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
  QEMU_CMD=()
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
  : >"${QCOW_IMAGE}"
  : >"${EFI_FIRM}"
  : >"${BPOOL_DISK0}"
  : >"${BPOOL_DISK1}"
  : >"${RPOOL_DISK0}"
  : >"${RPOOL_DISK1}"

  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" '-boot strict=on'
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
  : >"${QCOW_IMAGE}"
  : >"${EFI_FIRM}"
  : >"${BPOOL_DISK0}"
  : >"${BPOOL_DISK1}"
  : >"${RPOOL_DISK0}"
  : >"${RPOOL_DISK1}"

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
  : >"${EFI_FIRM}"
  : >"${BPOOL_DISK0}"
  : >"${BPOOL_DISK1}"
  : >"${RPOOL_DISK0}"
  : >"${RPOOL_DISK1}"

  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  [[ "${rendered}" != *"file=${QCOW_IMAGE},format=qcow2"* ]] || fail 'target-disks boot should not attach the QCOW boot disk'
  assert_contains "${rendered}" 'ide-hd,drive=bpool0,bus=ahci.1,serial=bpool-0,bootindex=1'
  assert_contains "${rendered}" 'ide-hd,drive=bpool1,bus=ahci.2,serial=bpool-1'
  assert_contains "${rendered}" '-boot strict=on'
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
  : >"${QCOW_IMAGE}"
  : >"${EFI_FIRM}"
  : >"${BPOOL_DISK0}"
  : >"${BPOOL_DISK1}"
  : >"${RPOOL_DISK0}"
  : >"${RPOOL_DISK1}"

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
  : >"${EFI_FIRM}"
  : >"${BPOOL_DISK0}"
  : >"${BPOOL_DISK1}"
  : >"${RPOOL_DISK0}"
  : >"${RPOOL_DISK1}"

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

test_default_launcher_log_file_uses_requested_format
test_build_qemu_cmd_uses_boot_disk_and_tcp_serial
test_build_qemu_cmd_supports_pty_serial
test_build_qemu_cmd_supports_target_disk_boot
test_validate_boot_source_rejects_invalid_value
test_main_dry_run_prints_stage3_vm_command
test_main_dry_run_prints_target_disk_boot_plan

printf 'PASS: %s\n' "$(basename "$0")"
