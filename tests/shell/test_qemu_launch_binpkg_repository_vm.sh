#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-binpkg-repository-vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

test_dry_run_uses_pathb_binpkg_defaults() {
  local temp_dir output

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  : > "${temp_dir}/vmlinuz"
  : > "${temp_dir}/initramfs.img"

  output="$(
    INSTANCE_NAME=binpkg-repository-test \
    QEMU_VM_DIR="${temp_dir}" \
    QEMU_ROOTDISK="${temp_dir}/binpkg-repository-root.qcow2" \
    QEMU_DIRECT_KERNEL="${temp_dir}/vmlinuz" \
    QEMU_DIRECT_INITRD="${temp_dir}/initramfs.img" \
    QEMU_MEMORY_DRIVES_FILE="${temp_dir}/missing-memory-drives.json" \
    QEMU_LAUNCH_DRY_RUN=1 \
    LAUNCHER_LOG_ENABLE=0 \
    bash "${LAUNCH_SCRIPT}"
  )"

  assert_contains "${output}" 'binpkg-repository-root.qcow2'
  assert_contains "${output}" 'ip=10.9.8.90::10.9.8.108:255.255.255.0:binpkg-repository:eth0:none'
  assert_contains "${output}" 'ifname=tap-binpkg'
  assert_contains "${output}" 'Serial target: telnet 127.0.0.1 5004'
}

test_dry_run_uses_pathb_binpkg_defaults

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
