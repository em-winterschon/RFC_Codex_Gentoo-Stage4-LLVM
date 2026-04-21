#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-cloudinit-vm.sh"

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

test_resolve_cloud_image_url_parses_latest_info() {
  local resolved_url

  CLOUD_IMAGE_URL=''
  CLOUD_IMAGE_INFO_URL='https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-di-amd64-cloudinit.txt'
  fetch_text() {
    cat <<'EOF'
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
  QEMU_NETDEV_BACKEND='user,hostfwd=tcp:127.0.0.1:2222-:22'
  : >"${BASE_IMAGE_PATH}"
  : >"${OVERLAY_IMAGE}"
  : >"${SEED_ISO}"
  : >"${EFI_FIRM}"
  : >"${BPOOL_DISK0}"
  : >"${BPOOL_DISK1}"
  : >"${RPOOL_DISK0}"
  : >"${RPOOL_DISK1}"

  build_qemu_cmd

  rendered="${QEMU_CMD[*]}"
  assert_contains "${rendered}" "if=virtio,file=${OVERLAY_IMAGE},format=qcow2"
  assert_contains "${rendered}" "file=${SEED_ISO},format=raw,media=cdrom,readonly=on"
  assert_contains "${rendered}" "hostfwd=tcp:127.0.0.1:2222-:22,id=${QEMU_NETDEV_ID}"
  assert_contains "${rendered}" "${QEMU_NETDEV_MODEL},netdev=${QEMU_NETDEV_ID}"
  assert_contains "${rendered}" "file=${BPOOL_DISK0},format=raw,cache=${HOST_DISK_CACHE},aio=${HOST_DISK_AIO}"
  assert_contains "${rendered}" "file=${RPOOL_DISK1},format=raw,cache=${HOST_DISK_CACHE},aio=${HOST_DISK_AIO}"
  assert_contains "${rendered}" "file:${QEMU_SERIAL_FILE}"
  assert_contains "${rendered}" '-daemonize'
  rm -rf "${temp_dir}"
}

test_main_dry_run_prints_overlay_and_qemu_commands() {
  local temp_dir output
  temp_dir="$(mktemp -d)"

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
  QEMU_NETDEV_HELP_OUTPUT=$'user\ntap\n'
  QEMU_LAUNCH_DRY_RUN='1'
  GENERATE_SEED='0'
  WAIT_FOR_SSH='0'
  QEMU_DISPLAY_MODE='none'
  QEMU_SERIAL_MODE='file'
  QEMU_DAEMONIZE='1'
  : >"${CLOUD_IMAGE_PATH}"
  : >"${SEED_ISO}"
  : >"${EFI_FIRM}"
  : >"${BPOOL_DISK0}"
  : >"${BPOOL_DISK1}"
  : >"${RPOOL_DISK0}"
  : >"${RPOOL_DISK1}"

  output="$(main 2>&1)"

  assert_contains "${output}" 'Creating writable overlay'
  assert_contains "${output}" '/usr/bin/qemu-img create -f qcow2 -F qcow2'
  assert_contains "${output}" '/usr/bin/qemu-system-x86_64'
  assert_contains "${output}" 'ssh -p 2222 root@127.0.0.1'
  assert_contains "${output}" '[COMPLETE]'
  rm -rf "${temp_dir}"
}

test_resolve_cloud_image_url_parses_latest_info
test_build_qemu_cmd_uses_cloud_boot_disk_seed_and_host_disks
test_main_dry_run_prints_overlay_and_qemu_commands

printf 'PASS: %s\n' "$(basename "$0")"
