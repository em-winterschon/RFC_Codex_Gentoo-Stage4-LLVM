#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SEED_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/generate-cloud-init-seed.sh"

# shellcheck source=../../gentoo-virt-qemu/generate-cloud-init-seed.sh
source "${SEED_SCRIPT}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
  assert_contains "$(<"${path}")" "${needle}"
}

test_render_user_data_uses_explicit_ssh_key_file() {
  local temp_dir ssh_key
  temp_dir="$(mktemp -d)"
  ssh_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey codex@test'

  SEED_BASE_DIR="${temp_dir}"
  SEED_DIR="${temp_dir}/seed"
  USER_DATA_PATH="${SEED_DIR}/user-data"
  META_DATA_PATH="${SEED_DIR}/meta-data"
  NETWORK_CONFIG_PATH="${SEED_DIR}/network-config"
  SSH_AUTHORIZED_KEY=''
  SSH_AUTHORIZED_KEY_FILE="${temp_dir}/id_ed25519.pub"
  CLOUD_INIT_USERNAME='root'
  printf '%s\n' "${ssh_key}" >"${SSH_AUTHORIZED_KEY_FILE}"

  ensure_seed_dir
  render_user_data

  assert_file_contains "${USER_DATA_PATH}" 'name: root'
  assert_file_contains "${USER_DATA_PATH}" "${ssh_key}"
  rm -rf "${temp_dir}"
}

test_render_meta_data_contains_instance_and_hostname() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  INSTANCE_ID='gentoo-stage4-testvm'
  LOCAL_HOSTNAME='gentoo-stage4-testvm'
  SEED_BASE_DIR="${temp_dir}"
  SEED_DIR="${temp_dir}/seed"
  META_DATA_PATH="${SEED_DIR}/meta-data"

  ensure_seed_dir
  render_meta_data

  assert_file_contains "${META_DATA_PATH}" 'instance-id: gentoo-stage4-testvm'
  assert_file_contains "${META_DATA_PATH}" 'local-hostname: gentoo-stage4-testvm'
  rm -rf "${temp_dir}"
}

test_render_network_config_can_be_disabled() {
  local temp_dir
  temp_dir="$(mktemp -d)"

  CREATE_NETWORK_CONFIG='0'
  SEED_BASE_DIR="${temp_dir}"
  SEED_DIR="${temp_dir}/seed"
  NETWORK_CONFIG_PATH="${SEED_DIR}/network-config"

  ensure_seed_dir
  render_network_config

  [[ ! -e "${NETWORK_CONFIG_PATH}" ]] || fail 'expected network-config to be omitted when disabled'
  rm -rf "${temp_dir}"
}

test_build_seed_iso_cmd_uses_mkisofs() {
  local temp_dir rendered ssh_key
  temp_dir="$(mktemp -d)"
  ssh_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey codex@test'

  SEED_BASE_DIR="${temp_dir}"
  SEED_DIR="${temp_dir}/seed"
  SEED_ISO="${temp_dir}/seed.iso"
  USER_DATA_PATH="${SEED_DIR}/user-data"
  META_DATA_PATH="${SEED_DIR}/meta-data"
  NETWORK_CONFIG_PATH="${SEED_DIR}/network-config"
  SSH_AUTHORIZED_KEY="${ssh_key}"
  SSH_AUTHORIZED_KEY_FILE=''
  CREATE_NETWORK_CONFIG='1'
  MKISOFS_BIN='/usr/bin/mkisofs'
  XORRISO_BIN='/usr/bin/xorriso'

  ensure_seed_dir
  render_meta_data
  render_user_data
  render_network_config
  build_seed_iso_cmd

  rendered="${SEED_ISO_CMD[*]}"
  assert_contains "${rendered}" '/usr/bin/mkisofs'
  assert_contains "${rendered}" '-volid cidata'
  assert_contains "${rendered}" "${USER_DATA_PATH}"
  assert_contains "${rendered}" "${NETWORK_CONFIG_PATH}"
  rm -rf "${temp_dir}"
}

test_main_dry_run_prints_iso_command() {
  local temp_dir output ssh_key
  temp_dir="$(mktemp -d)"
  ssh_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey codex@test'

  INSTANCE_NAME='gentoo-stage4-testvm'
  LOCAL_HOSTNAME='gentoo-stage4-testvm'
  INSTANCE_ID='gentoo-stage4-testvm'
  SEED_BASE_DIR="${temp_dir}"
  SEED_DIR="${temp_dir}/seed"
  SEED_ISO="${temp_dir}/seed.iso"
  USER_DATA_PATH="${SEED_DIR}/user-data"
  META_DATA_PATH="${SEED_DIR}/meta-data"
  NETWORK_CONFIG_PATH="${SEED_DIR}/network-config"
  SSH_AUTHORIZED_KEY="${ssh_key}"
  SSH_AUTHORIZED_KEY_FILE=''
  MKISOFS_BIN='/usr/bin/mkisofs'
  CLOUD_INIT_SEED_DRY_RUN='1'
  CREATE_NETWORK_CONFIG='1'

  output="$(main 2>&1)"

  assert_contains "${output}" 'Writing seed ISO'
  assert_contains "${output}" '/usr/bin/mkisofs'
  assert_contains "${output}" '-volid cidata'
  assert_contains "${output}" '[COMPLETE]'
  rm -rf "${temp_dir}"
}

test_render_user_data_uses_explicit_ssh_key_file
test_render_meta_data_contains_instance_and_hostname
test_render_network_config_can_be_disabled
test_build_seed_iso_cmd_uses_mkisofs
test_main_dry_run_prints_iso_command

printf 'PASS: %s\n' "$(basename "$0")"
