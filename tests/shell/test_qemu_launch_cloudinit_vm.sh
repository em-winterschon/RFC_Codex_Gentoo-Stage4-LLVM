#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-cloudinit-vm.sh"

# shellcheck disable=SC1091
# shellcheck source=../../gentoo-virt-qemu/qemu-launch-cloudinit-vm.sh
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

mark_cloud_launch_globals_used() {
  : "${QEMU_NETDEV_HELP_OUTPUT-}" \
    "${CLOUD_IMAGE_URL-}" \
    "${CLOUD_IMAGE_INFO_URL-}" \
    "${QEMU_DISPLAY_HELP_OUTPUT-}" \
    "${QEMU_SERIAL_MODE-}" \
    "${QEMU_SERIAL_FILE-}" \
    "${QEMU_DISPLAY_MODE-}" \
    "${QEMU_DEVICE_HELP_OUTPUT-}" \
    "${QEMU_NETDEV_BACKEND-}" \
    "${QEMU_BOOT_STRICT-}" \
    "${QEMU_BOOTDISK_ID-}" \
    "${QEMU_BOOTDISK_MODEL-}" \
    "${QEMU_BOOTDISK_BOOTINDEX-}" \
    "${SEED_DIR-}" \
    "${QEMU_BIN-}" \
    "${QEMU_IMG_BIN-}" \
    "${QEMU_LAUNCH_DRY_RUN-}" \
    "${GENERATE_SEED-}" \
    "${QEMU_DAEMONIZE-}" \
    "${WAIT_FOR_SSH-}" \
    "${SSH_WAIT_TIMEOUT-}" \
    "${SSH_READY_PROBE-}" \
    "${SSH_BANNER_TIMEOUT-}" \
    "${SSH_READY_HOST-}" \
    "${SSH_READY_PORT-}" \
    "${QEMU_ENABLE_VSOCK-}"
}

reset_launcher_state() {
  CLOUD_IMAGE_URL=''
  CLOUD_IMAGE_INFO_URL='https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-di-amd64-cloudinit.txt'
  BASE_IMAGE_PATH=''
  QEMU_ENABLE_VSOCK='0'
  QEMU_VSOCK_MODEL='vhost-vsock-pci'
  QEMU_VSOCK_CID='3'
  QEMU_DEVICE_HELP_OUTPUT=''
  QEMU_NETDEV_HELP_OUTPUT=$'user\ntap\n'
  QEMU_DISPLAY_HELP_OUTPUT=''
  QEMU_BOOT_STRICT='1'
  QEMU_BOOTDISK_ID='bootdisk'
  QEMU_BOOTDISK_MODEL='virtio-blk-pci'
  QEMU_BOOTDISK_BOOTINDEX='1'
  QEMU_SERIAL_MODE='file'
  QEMU_DISPLAY_MODE='none'
  QEMU_DAEMONIZE='1'
  WAIT_FOR_SSH='1'
  SSH_WAIT_TIMEOUT='120'
  SSH_READY_PROBE='banner'
  SSH_BANNER_TIMEOUT='5'
  SSH_FORWARD_HOST='127.0.0.1'
  SSH_FORWARD_PORT='2222'
}

test_resolve_cloud_image_url_parses_latest_info() {
  local resolved_url

  reset_launcher_state
  CLOUD_IMAGE_URL=''
  CLOUD_IMAGE_INFO_URL='https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-di-amd64-cloudinit.txt'
  mark_cloud_launch_globals_used
  fetch_text() {
    cat << 'EOF'
[ Latest Files ]
https://distfiles.gentoo.org/releases/amd64/autobuilds/20260419T164601Z/di-amd64-cloudinit-20260419T164601Z.qcow2 12345
EOF
  }

  resolved_url="$(resolve_cloud_image_url)"
  assert_contains "${resolved_url}" 'di-amd64-cloudinit-20260419T164601Z.qcow2'
}

test_build_qemu_cmd_uses_cloud_boot_disk_seed_and_host_disks() {
  local temp_dir rendered
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  BASE_IMAGE_PATH="${temp_dir}/base.qcow2"
  OVERLAY_IMAGE="${temp_dir}/overlay.qcow2"
  SEED_ISO="${temp_dir}/seed.iso"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  QEMU_BIN='/usr/bin/qemu-system-x86_64'
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_SERIAL_MODE='file'
  QEMU_SERIAL_FILE="${temp_dir}/serial.log"
  QEMU_DISPLAY_MODE='none'
  QEMU_DAEMONIZE='1'
  QEMU_ENABLE_VSOCK='1'
  QEMU_VSOCK_CID='42'
  QEMU_NETDEV_BACKEND='user,hostfwd=tcp:127.0.0.1:2222-:22'
  mark_cloud_launch_globals_used
  : > "${BASE_IMAGE_PATH}"
  : > "${OVERLAY_IMAGE}"
  : > "${SEED_ISO}"
  : > "${EFI_FIRM}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  build_qemu_cmd

  rendered="${QEMU_CMD[*]}"
  assert_contains "${rendered}" "-boot strict=on"
  assert_contains "${rendered}" "if=none,id=${QEMU_BOOTDISK_ID},file=${OVERLAY_IMAGE},format=qcow2"
  assert_contains "${rendered}" "${QEMU_BOOTDISK_MODEL},drive=${QEMU_BOOTDISK_ID},bootindex=${QEMU_BOOTDISK_BOOTINDEX},serial=cloud-boot"
  assert_contains "${rendered}" "file=${SEED_ISO},format=raw,media=cdrom,readonly=on"
  assert_contains "${rendered}" "hostfwd=tcp:127.0.0.1:2222-:22,id=${QEMU_NETDEV_ID}"
  assert_contains "${rendered}" "${QEMU_NETDEV_MODEL},netdev=${QEMU_NETDEV_ID}"
  assert_contains "${rendered}" "${QEMU_VSOCK_MODEL},guest-cid=${QEMU_VSOCK_CID}"
  assert_contains "${rendered}" "file=${BPOOL_DISK0},format=raw,cache=${HOST_DISK_CACHE},aio=${HOST_DISK_AIO}"
  assert_contains "${rendered}" "file=${RPOOL_DISK1},format=raw,cache=${HOST_DISK_CACHE},aio=${HOST_DISK_AIO}"
  assert_contains "${rendered}" "file:${QEMU_SERIAL_FILE}"
  assert_contains "${rendered}" '-daemonize'
  rm -rf "${temp_dir}"
}

test_main_dry_run_prints_overlay_and_qemu_commands() {
  local temp_dir output status
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  CLOUD_IMAGE_PATH="${temp_dir}/base.qcow2"
  BASE_IMAGE_PATH=''
  OVERLAY_IMAGE="${temp_dir}/overlay.qcow2"
  SEED_ISO="${temp_dir}/seed.iso"
  STATE_DIR="${temp_dir}/state"
  SEED_DIR="${STATE_DIR}/seed"
  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  BPOOL_DISK0="${temp_dir}/bpool0.img"
  BPOOL_DISK1="${temp_dir}/bpool1.img"
  RPOOL_DISK0="${temp_dir}/rpool0.img"
  RPOOL_DISK1="${temp_dir}/rpool1.img"
  QEMU_BIN='/usr/bin/qemu-system-x86_64'
  QEMU_IMG_BIN='/usr/bin/qemu-img'
  QEMU_LAUNCH_DRY_RUN='1'
  GENERATE_SEED='0'
  WAIT_FOR_SSH='0'
  QEMU_DISPLAY_MODE='none'
  QEMU_SERIAL_MODE='file'
  QEMU_SERIAL_FILE="${temp_dir}/serial.log"
  QEMU_DAEMONIZE='1'
  mark_cloud_launch_globals_used
  : > "${CLOUD_IMAGE_PATH}"
  : > "${SEED_ISO}"
  : > "${EFI_FIRM}"
  : > "${BPOOL_DISK0}"
  : > "${BPOOL_DISK1}"
  : > "${RPOOL_DISK0}"
  : > "${RPOOL_DISK1}"

  set +e
  output="$(main 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '0'
  assert_contains "${output}" 'Creating writable overlay'
  assert_contains "${output}" '/usr/bin/qemu-img create -f qcow2 -F qcow2'
  assert_contains "${output}" '/usr/bin/qemu-system-x86_64'
  assert_contains "${output}" '-boot strict=on'
  assert_contains "${output}" 'ssh -p 2222 root@127.0.0.1'
  assert_contains "${output}" '[COMPLETE]'
  rm -rf "${temp_dir}"
}

test_wait_for_ssh_ready_requires_banner_not_just_open_port() {
  local temp_dir output status
  temp_dir="$(mktemp -d)"

  reset_launcher_state
  QEMU_SERIAL_FILE="${temp_dir}/serial.log"
  printf "%s\n" "Try contacting this VM's SSH server via 'ssh vsock%4294967295' from host." > "${QEMU_SERIAL_FILE}"
  WAIT_FOR_SSH='1'
  QEMU_DAEMONIZE='1'
  SSH_WAIT_TIMEOUT='0'
  SSH_READY_PROBE='banner'
  mark_cloud_launch_globals_used

  probe_ssh_banner() {
    return 1
  }

  set +e
  output="$(wait_for_ssh_ready 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '1'
  assert_contains "${output}" "Timed out waiting for an SSH banner on ${SSH_FORWARD_HOST}:${SSH_FORWARD_PORT}"
  assert_contains "${output}" "ssh vsock%4294967295"
  rm -rf "${temp_dir}"
}

test_validate_vsock_backend_checks_device_help() {
  local output status

  reset_launcher_state
  QEMU_ENABLE_VSOCK='1'
  QEMU_VSOCK_MODEL='vhost-vsock-pci'
  QEMU_DEVICE_HELP_OUTPUT='name "virtio-net-pci"'
  mark_cloud_launch_globals_used

  set +e
  output="$(validate_vsock_backend 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '1'
  assert_contains "${output}" "QEMU vsock device 'vhost-vsock-pci' is not available"
}

test_resolve_cloud_image_url_parses_latest_info
test_build_qemu_cmd_uses_cloud_boot_disk_seed_and_host_disks
test_main_dry_run_prints_overlay_and_qemu_commands
test_wait_for_ssh_ready_requires_banner_not_just_open_port
test_validate_vsock_backend_checks_device_help

printf 'PASS: %s\n' "$(basename "$0")"
