#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/validate-llvm-qcow-builder.sh"

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

make_fake_repo() {
  local temp_dir="$1"
  mkdir -p "${temp_dir}/gentoo-virt-qemu"

  cat > "${temp_dir}/gentoo-virt-qemu/build-stage3-qcow.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'builder dry=%s key=%s\n' "${QEMU_STAGE3_BUILD_DRY_RUN:-0}" "${SSH_AUTHORIZED_KEY_FILE:-}" >>"${VALIDATOR_STATE_FILE}"
EOF
  chmod +x "${temp_dir}/gentoo-virt-qemu/build-stage3-qcow.sh"

  cat > "${temp_dir}/gentoo-virt-qemu/qemu-launch-stage3-vm.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'launcher serial=%s wait=%s\n' "${QEMU_SERIAL_MODE:-unset}" "${WAIT_FOR_SSH:-unset}" >>"${VALIDATOR_STATE_FILE}"
EOF
  chmod +x "${temp_dir}/gentoo-virt-qemu/qemu-launch-stage3-vm.sh"
}

remove_execute_bits() {
  local temp_dir="$1"
  chmod 0644 "${temp_dir}/gentoo-virt-qemu/build-stage3-qcow.sh"
  chmod 0644 "${temp_dir}/gentoo-virt-qemu/qemu-launch-stage3-vm.sh"
}

test_build_dry_run_mode_invokes_builder_with_expected_env() {
  local temp_dir key_file state_file log_file output status
  temp_dir="$(mktemp -d)"
  key_file="${temp_dir}/id_ed25519.pub"
  state_file="${temp_dir}/state.log"
  log_file="${temp_dir}/validator.log"
  printf 'ssh-ed25519 AAAATestKey codex@test\n' > "${key_file}"
  : > "${state_file}"
  make_fake_repo "${temp_dir}"
  remove_execute_bits "${temp_dir}"

  set +e
  output="$(
    VALIDATOR_STATE_FILE="${state_file}" \
      STAGE3_IMAGE_DIR="${temp_dir}" \
      bash "${VALIDATOR_SCRIPT}" \
      --mode build-dry-run \
      --working-dir "${temp_dir}" \
      --ssh-pubkey "${key_file}" \
      --log-file "${log_file}" 2>&1
  )"
  status=$?
  set -e

  assert_equals "${status}" '0'
  assert_contains "${output}" 'Mode: build-dry-run'
  assert_contains "$(cat "${state_file}")" "builder dry=1 key=${key_file}"
  assert_contains "$(cat "${log_file}")" 'Validation completed successfully'
  rm -rf "${temp_dir}"
}

test_full_mode_runs_builder_and_launcher_sequence() {
  local temp_dir key_file state_file output status
  temp_dir="$(mktemp -d)"
  key_file="${temp_dir}/id_ed25519.pub"
  state_file="${temp_dir}/state.log"
  printf 'ssh-ed25519 AAAATestKey codex@test\n' > "${key_file}"
  : > "${state_file}"
  make_fake_repo "${temp_dir}"
  remove_execute_bits "${temp_dir}"

  set +e
  output="$(
    VALIDATOR_STATE_FILE="${state_file}" \
      STAGE3_IMAGE_DIR="${temp_dir}" \
      VALIDATOR_SKIP_ROOT_CHECK=1 \
      bash "${VALIDATOR_SCRIPT}" \
      --mode full \
      --working-dir "${temp_dir}" \
      --ssh-pubkey "${key_file}" \
      --serial-mode tcp \
      --wait-for-ssh 1 \
      --log-dir "${temp_dir}" 2>&1
  )"
  status=$?
  set -e

  assert_equals "${status}" '0'
  assert_contains "${output}" 'Stage3 builder dry-run'
  assert_contains "${output}" 'Stage3 builder real run'
  assert_contains "${output}" 'Stage3 VM launch'
  assert_equals "$(sed -n '1p' "${state_file}")" "builder dry=1 key=${key_file}"
  assert_equals "$(sed -n '2p' "${state_file}")" "builder dry=0 key=${key_file}"
  assert_equals "$(sed -n '3p' "${state_file}")" 'launcher serial=tcp wait=1'
  rm -rf "${temp_dir}"
}

test_invalid_mode_fails_with_usage_code() {
  local temp_dir key_file output status
  temp_dir="$(mktemp -d)"
  key_file="${temp_dir}/id_ed25519.pub"
  printf 'ssh-ed25519 AAAATestKey codex@test\n' > "${key_file}"
  make_fake_repo "${temp_dir}"
  remove_execute_bits "${temp_dir}"

  set +e
  output="$(
    STAGE3_IMAGE_DIR="${temp_dir}" \
      bash "${VALIDATOR_SCRIPT}" \
      --mode nonsense \
      --working-dir "${temp_dir}" \
      --ssh-pubkey "${key_file}" \
      --log-dir "${temp_dir}" 2>&1
  )"
  status=$?
  set -e

  assert_equals "${status}" '64'
  assert_contains "${output}" 'Unsupported mode'
  rm -rf "${temp_dir}"
}

test_build_mode_rejects_running_qcow_conflict() {
  local temp_dir key_file output status
  temp_dir="$(mktemp -d)"
  key_file="${temp_dir}/id_ed25519.pub"
  printf 'ssh-ed25519 AAAATestKey codex@test\n' > "${key_file}"
  make_fake_repo "${temp_dir}"
  remove_execute_bits "${temp_dir}"

  set +e
  output="$(
    QEMU_PROCESS_LIST="1234 /usr/bin/qemu-system-x86_64 -drive if=none,id=bootdisk,file=${temp_dir}/images/gentoo-stage4-testvm.qcow2,format=qcow2" \
      STAGE3_IMAGE_DIR="${temp_dir}" \
      VALIDATOR_SKIP_ROOT_CHECK=1 \
      bash "${VALIDATOR_SCRIPT}" \
      --mode build \
      --working-dir "${temp_dir}" \
      --ssh-pubkey "${key_file}" \
      --log-dir "${temp_dir}" 2>&1
  )"
  status=$?
  set -e

  assert_equals "${status}" '65'
  assert_contains "${output}" 'QCOW image is in use by a running QEMU process'
  rm -rf "${temp_dir}"
}

test_launch_mode_rejects_running_qcow_conflict() {
  local temp_dir output status
  temp_dir="$(mktemp -d)"
  make_fake_repo "${temp_dir}"
  remove_execute_bits "${temp_dir}"

  set +e
  output="$(
    QEMU_PROCESS_LIST="1234 /usr/bin/qemu-system-x86_64 -drive if=none,id=bootdisk,file=${temp_dir}/images/gentoo-stage4-testvm.qcow2,format=qcow2" \
      STAGE3_IMAGE_DIR="${temp_dir}" \
      VALIDATOR_SKIP_ROOT_CHECK=1 \
      bash "${VALIDATOR_SCRIPT}" \
      --mode launch \
      --working-dir "${temp_dir}" \
      --log-dir "${temp_dir}" 2>&1
  )"
  status=$?
  set -e

  assert_equals "${status}" '65'
  assert_contains "${output}" 'Stage3 VM is already running from QCOW image'
  rm -rf "${temp_dir}"
}

test_build_dry_run_mode_invokes_builder_with_expected_env
test_full_mode_runs_builder_and_launcher_sequence
test_invalid_mode_fails_with_usage_code
test_build_mode_rejects_running_qcow_conflict
test_launch_mode_rejects_running_qcow_conflict

printf 'PASS: %s\n' "$(basename "$0")"
