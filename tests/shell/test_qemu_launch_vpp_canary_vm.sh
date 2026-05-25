#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-vpp-canary-vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}'"
}

test_vpp_canary_dry_run_uses_safe_vm_defaults() {
  local temp_dir output status
  temp_dir="$(mktemp -d)"

  : > "${temp_dir}/base.qcow2"
  : > "${temp_dir}/seed.iso"
  : > "${temp_dir}/OVMF_CODE.fd"
  printf '%s\n' 'ssh-ed25519 AAAAvppcanary test@example' > "${temp_dir}/authorized_keys"

  set +e
  output="$(
    env \
      VPP_CANARY_ENABLE_OVS_TAP=0 \
      QEMU_LAUNCH_DRY_RUN=1 \
      CLOUD_IMAGE_PATH="${temp_dir}/base.qcow2" \
      BASE_IMAGE_PATH='' \
      BASE_DIR="${temp_dir}/base" \
      STATE_DIR="${temp_dir}/state" \
      SEED_DIR="${temp_dir}/state/seed" \
      SEED_ISO="${temp_dir}/seed.iso" \
      EFI_FIRM="${temp_dir}/OVMF_CODE.fd" \
      QEMU_NETDEV_HELP_OUTPUT=$'user\ntap\n' \
      SSH_AUTHORIZED_KEYS_FILE="${temp_dir}/authorized_keys" \
      GENERATE_SEED=0 \
      WAIT_FOR_SSH=0 \
      bash "${LAUNCH_SCRIPT}" 2>&1
  )"
  status=$?
  set -e

  [[ "${status}" == '0' ]] || fail "dry run failed: ${output}"
  assert_contains "${output}" '/usr/bin/qemu-system-x86_64'
  assert_contains "${output}" 'hostfwd=tcp:127.0.0.1:2224-:22'
  [[ "${output}" != *'bpool0'* ]] || fail 'VPP canary launcher must not attach host bpool disks'
  [[ "${output}" != *'rpool0'* ]] || fail 'VPP canary launcher must not attach host rpool disks'
  rm -rf "${temp_dir}"
}

test_vpp_canary_dry_run_uses_safe_vm_defaults

printf 'PASS: %s\n' "$(basename "$0")"
