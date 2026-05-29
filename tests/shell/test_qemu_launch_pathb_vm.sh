#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-pathb-vm.sh"
TEST_TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP_ROOT}"' EXIT

QEMU_PATHB_SOURCE_ONLY=1
# shellcheck disable=SC1091
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

reset_pathb_globals() {
  INSTANCE_NAME='pathb-ipxe-client'
  QEMU_VM_DIR="${TEST_TMP_ROOT}/pathb-ipxe-client"
  QEMU_ROOTDISK="${QEMU_VM_DIR}/root.qcow2"
  QEMU_IPXE_EFI_DIR="${QEMU_VM_DIR}/ipxe-efi"
  QEMU_PATHB_BOOT_MODE='ipxe'
  QEMU_DIRECT_KERNEL="${TEST_TMP_ROOT}/pathb-vmlinuz"
  QEMU_DIRECT_INITRD="${TEST_TMP_ROOT}/pathb-initramfs.img"
  QEMU_DIRECT_ROOTFS_URL='http://10.9.8.108:8080/g/rootfs.img'
  QEMU_DIRECT_APPEND="console=tty0 console=ttyS0,115200 ip=dhcp rd.neednet=1 rd.live.image root=live:${QEMU_DIRECT_ROOTFS_URL}"
  QEMU_BIN='/usr/bin/qemu-system-x86_64'
  EFI_FIRM="${TEST_TMP_ROOT}/OVMF_CODE.fd"
  EFI_VARS_TEMPLATE="${TEST_TMP_ROOT}/OVMF_VARS.fd"
  EFI_VARS_FILE="${TEST_TMP_ROOT}/pathb-ipxe-client.OVMF_VARS.fd"
  QEMU_MACHINE='q35,accel=kvm'
  QEMU_CPU='host'
  QEMU_SMP='16'
  QEMU_MEMORY_MIB='32768'
  QEMU_NETDEV_MODEL='e1000'
  QEMU_MAC_ADDRESS='52:54:00:12:34:78'
  QEMU_TAP_IFNAME='tap-pathb-client'
  QEMU_BRIDGE_IFNAME='br-pathb'
  QEMU_DISPLAY_MODE='none'
  QEMU_SERIAL_MODE='telnet'
  QEMU_SERIAL_HOST='127.0.0.1'
  QEMU_SERIAL_PORT='5003'
  QEMU_SERIAL_FILE="${TEST_TMP_ROOT}/pathb-ipxe-client.serial.log"
  QEMU_MEMORY_DRIVES_FILE=''
  QEMU_RESET_EFI_VARS='0'
  QEMU_DAEMONIZE='1'
  QEMU_LAUNCH_DRY_RUN='1'
  IP_BIN='/usr/sbin/ip'
  HOST_DISK_CACHE='writeback'
  LAUNCHER_LOG_ENABLE='0'
  LAUNCHER_LOG_DIR="${TEST_TMP_ROOT}"
  LAUNCHER_LOG_FILE=''
  LAUNCHER_LOG_INITIALIZED=0
  QEMU_CMD=()
}

set_temp_ovmf_paths() {
  local temp_dir="$1"

  EFI_FIRM="${temp_dir}/OVMF_CODE.fd"
  EFI_VARS_TEMPLATE="${temp_dir}/OVMF_VARS_TEMPLATE.fd"
  EFI_VARS_FILE="${temp_dir}/OVMF_VARS.fd"
}

test_build_qemu_cmd_uses_uefi_tap_and_telnet() {
  local temp_dir rendered

  temp_dir="$(mktemp -d)"
  reset_pathb_globals
  set_temp_ovmf_paths "${temp_dir}"
  mkdir -p "${temp_dir}/ipxe-efi"
  : > "${temp_dir}/root.qcow2"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"

  QEMU_VM_DIR="${temp_dir}"
  QEMU_ROOTDISK="${temp_dir}/root.qcow2"
  QEMU_IPXE_EFI_DIR="${temp_dir}/ipxe-efi"
  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" "if=pflash,format=raw,readonly=on,unit=0,file=${EFI_FIRM}"
  assert_contains "${rendered}" "if=pflash,format=raw,unit=1,file=${temp_dir}/OVMF_VARS.fd"
  assert_contains "${rendered}" "file=fat:rw:${temp_dir}/ipxe-efi,format=raw,media=disk"
  assert_contains "${rendered}" 'tap,id=net0,ifname=tap-pathb-client,script=no,downscript=no'
  assert_contains "${rendered}" 'e1000,netdev=net0,mac=52:54:00:12:34:78'
  assert_contains "${rendered}" 'telnet:127.0.0.1:5003,server=on,wait=off'
  assert_contains "${rendered}" '-daemonize'

  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_supports_memory_drives_manifest() {
  local temp_dir rendered

  temp_dir="$(mktemp -d)"
  reset_pathb_globals
  set_temp_ovmf_paths "${temp_dir}"
  mkdir -p "${temp_dir}/ipxe-efi"
  : > "${temp_dir}/root.qcow2"
  : > "${temp_dir}/extra.qcow2"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"
  cat > "${temp_dir}/memory.json" << EOF
{"drives":[{"path":"${temp_dir}/extra.qcow2","format":"qcow2","serial":"mem-extra","device_model":"virtio-blk-pci"}]}
EOF

  QEMU_VM_DIR="${temp_dir}"
  QEMU_ROOTDISK="${temp_dir}/root.qcow2"
  QEMU_IPXE_EFI_DIR="${temp_dir}/ipxe-efi"
  QEMU_MEMORY_DRIVES_FILE="${temp_dir}/memory.json"
  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" "file=${temp_dir}/extra.qcow2,format=qcow2,cache=writeback"
  assert_contains "${rendered}" 'virtio-blk-pci,drive=memdrv0,serial=mem-extra'

  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_supports_stdio_without_daemonize() {
  local temp_dir rendered

  temp_dir="$(mktemp -d)"
  reset_pathb_globals
  set_temp_ovmf_paths "${temp_dir}"
  mkdir -p "${temp_dir}/ipxe-efi"
  : > "${temp_dir}/root.qcow2"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"

  QEMU_VM_DIR="${temp_dir}"
  QEMU_ROOTDISK="${temp_dir}/root.qcow2"
  QEMU_IPXE_EFI_DIR="${temp_dir}/ipxe-efi"
  QEMU_SERIAL_MODE='stdio'
  QEMU_DAEMONIZE='0'
  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" '-serial mon:stdio'

  rm -rf "${temp_dir}"
}

test_build_qemu_cmd_supports_direct_kernel_mode() {
  local temp_dir rendered

  temp_dir="$(mktemp -d)"
  : > "${temp_dir}/root.qcow2"
  : > "${temp_dir}/vmlinuz"
  : > "${temp_dir}/initramfs.img"

  reset_pathb_globals
  QEMU_VM_DIR="${temp_dir}"
  QEMU_ROOTDISK="${temp_dir}/root.qcow2"
  QEMU_PATHB_BOOT_MODE='direct-kernel'
  QEMU_DIRECT_KERNEL="${temp_dir}/vmlinuz"
  QEMU_DIRECT_INITRD="${temp_dir}/initramfs.img"
  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" "-kernel ${temp_dir}/vmlinuz"
  assert_contains "${rendered}" "-initrd ${temp_dir}/initramfs.img"
  assert_contains "${rendered}" "root=live:http://10.9.8.108:8080/g/rootfs.img"
}

test_build_qemu_cmd_supports_uefi_disk_mode() {
  local temp_dir rendered

  temp_dir="$(mktemp -d)"
  reset_pathb_globals
  set_temp_ovmf_paths "${temp_dir}"
  : > "${temp_dir}/root.qcow2"
  : > "${EFI_FIRM}"
  : > "${EFI_VARS_TEMPLATE}"

  QEMU_VM_DIR="${temp_dir}"
  QEMU_ROOTDISK="${temp_dir}/root.qcow2"
  QEMU_PATHB_BOOT_MODE='uefi-disk'
  build_qemu_cmd
  rendered="${QEMU_CMD[*]}"

  assert_contains "${rendered}" "if=pflash,format=raw,readonly=on,unit=0,file=${EFI_FIRM}"
  assert_contains "${rendered}" "if=pflash,format=raw,unit=1,file=${temp_dir}/OVMF_VARS.fd"
  assert_contains "${rendered}" "file=${temp_dir}/root.qcow2,format=qcow2,cache=writeback"
  assert_contains "${rendered}" 'ide-hd,drive=rootdisk,bus=ahci.1,bootindex=1,serial=stage4-root'
}

test_build_qemu_cmd_uses_uefi_tap_and_telnet
test_build_qemu_cmd_supports_memory_drives_manifest
test_build_qemu_cmd_supports_stdio_without_daemonize
test_build_qemu_cmd_supports_direct_kernel_mode
test_build_qemu_cmd_supports_uefi_disk_mode

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
