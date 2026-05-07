#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-elasticsearch-test-vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

test_dry_run_uses_pathb_elasticsearch_defaults() {
  local temp_dir output

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  : > "${temp_dir}/vmlinuz"
  : > "${temp_dir}/initramfs.img"
  : > "${temp_dir}/elasticsearch-test-root.qcow2"

  output="$(
    INSTANCE_NAME=elasticsearch-test-unit \
      QEMU_VM_DIR="${temp_dir}" \
      QEMU_ROOTDISK="${temp_dir}/elasticsearch-test-root.qcow2" \
      QEMU_DIRECT_KERNEL="${temp_dir}/vmlinuz" \
      QEMU_DIRECT_INITRD="${temp_dir}/initramfs.img" \
      QEMU_LAUNCH_DRY_RUN=1 \
      LAUNCHER_LOG_ENABLE=0 \
      bash "${LAUNCH_SCRIPT}"
  )"

  assert_contains "${output}" 'elasticsearch-test-root.qcow2'
  assert_contains "${output}" 'ip=10.9.8.91::10.9.8.1:255.255.255.0:elasticsearch-test:eth0:none'
  assert_contains "${output}" 'ifname=tap-es-test'
  assert_contains "${output}" 'Serial target: telnet 127.0.0.1 5005'
}

test_dry_run_uses_pathb_elasticsearch_defaults

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
