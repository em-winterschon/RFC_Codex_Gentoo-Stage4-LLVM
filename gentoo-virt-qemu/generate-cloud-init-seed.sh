#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_LAUNCH_TRACE:-0}" == '1' ]]; then
  set -x
fi

INSTANCE_NAME="${INSTANCE_NAME:-gentoo-stage4-testvm}"
LOCAL_HOSTNAME="${LOCAL_HOSTNAME:-${INSTANCE_NAME}}"
INSTANCE_ID="${INSTANCE_ID:-${INSTANCE_NAME}}"
SEED_BASE_DIR="${SEED_BASE_DIR:-/opt/gentoo-virt-qemu/cloud/state/${INSTANCE_NAME}}"
SEED_DIR="${SEED_DIR:-${SEED_BASE_DIR}/seed}"
SEED_ISO="${SEED_ISO:-${SEED_BASE_DIR}/${INSTANCE_NAME}-seed.iso}"
META_DATA_PATH="${META_DATA_PATH:-${SEED_DIR}/meta-data}"
USER_DATA_PATH="${USER_DATA_PATH:-${SEED_DIR}/user-data}"
NETWORK_CONFIG_PATH="${NETWORK_CONFIG_PATH:-${SEED_DIR}/network-config}"
CREATE_NETWORK_CONFIG="${CREATE_NETWORK_CONFIG:-1}"
CLOUD_INIT_USERNAME="${CLOUD_INIT_USERNAME:-root}"
CLOUD_INIT_LOCK_PASSWD="${CLOUD_INIT_LOCK_PASSWD:-1}"
CLOUD_INIT_PASSWORD_HASH="${CLOUD_INIT_PASSWORD_HASH-}"
SSH_AUTHORIZED_KEY="${SSH_AUTHORIZED_KEY-}"
SSH_AUTHORIZED_KEY_FILE="${SSH_AUTHORIZED_KEY_FILE-}"
MKISOFS_BIN="${MKISOFS_BIN:-/usr/bin/mkisofs}"
XORRISO_BIN="${XORRISO_BIN:-/usr/bin/xorriso}"
CLOUD_INIT_SEED_DRY_RUN="${CLOUD_INIT_SEED_DRY_RUN:-0}"
SEED_ISO_CMD=()

log() {
  printf '[generate-cloud-init-seed] %s\n' "$*"
}

fail() {
  printf '[generate-cloud-init-seed] ERROR: %s\n' "$*" >&2
  exit 1
}

ensure_seed_dir() {
  mkdir -p "${SEED_DIR}" "${SEED_BASE_DIR}"
}

resolve_ssh_authorized_key() {
  local candidate

  if [[ -n "${SSH_AUTHORIZED_KEY}" ]]; then
    printf '%s' "${SSH_AUTHORIZED_KEY}"
    return 0
  fi

  if [[ -n "${SSH_AUTHORIZED_KEY_FILE}" ]]; then
    [[ -f "${SSH_AUTHORIZED_KEY_FILE}" ]] || fail "SSH_AUTHORIZED_KEY_FILE does not exist: ${SSH_AUTHORIZED_KEY_FILE}"
    sed -n '1p' "${SSH_AUTHORIZED_KEY_FILE}"
    return 0
  fi

  for candidate in "${HOME:-/root}/.ssh/id_ed25519.pub" "${HOME:-/root}/.ssh/id_rsa.pub"; do
    if [[ -f "${candidate}" ]]; then
      sed -n '1p' "${candidate}"
      return 0
    fi
  done

  fail 'No SSH authorized key available; set SSH_AUTHORIZED_KEY or SSH_AUTHORIZED_KEY_FILE'
}

render_meta_data() {
  cat > "${META_DATA_PATH}" << EOF
instance-id: ${INSTANCE_ID}
local-hostname: ${LOCAL_HOSTNAME}
EOF
}

render_user_data() {
  local ssh_key lock_passwd_literal

  ssh_key="$(resolve_ssh_authorized_key)"
  lock_passwd_literal='true'
  if [[ "${CLOUD_INIT_LOCK_PASSWD}" == '0' ]]; then
    lock_passwd_literal='false'
  fi

  {
    printf '#cloud-config\n'
    printf 'hostname: %s\n' "${LOCAL_HOSTNAME}"
    printf 'preserve_hostname: false\n'
    printf 'manage_etc_hosts: true\n'
    printf 'disable_root: false\n'
    printf 'ssh_pwauth: false\n'
    printf 'users:\n'
    printf '  - name: %s\n' "${CLOUD_INIT_USERNAME}"
    printf '    gecos: Codex Test User\n'
    printf '    shell: /bin/bash\n'
    printf '    lock_passwd: %s\n' "${lock_passwd_literal}"
    if [[ "${CLOUD_INIT_USERNAME}" != 'root' ]]; then
      printf '    sudo: ALL=(ALL) NOPASSWD:ALL\n'
    fi
    printf '    ssh_authorized_keys:\n'
    printf '      - %s\n' "${ssh_key}"
    if [[ -n "${CLOUD_INIT_PASSWORD_HASH}" ]]; then
      printf 'chpasswd:\n'
      printf '  expire: false\n'
      printf '  list: |\n'
      printf '    %s:%s\n' "${CLOUD_INIT_USERNAME}" "${CLOUD_INIT_PASSWORD_HASH}"
    fi
    printf 'growpart:\n'
    printf '  mode: auto\n'
    printf "  devices: ['/']\n"
    printf 'resize_rootfs: true\n'
  } > "${USER_DATA_PATH}"
}

render_network_config() {
  if [[ "${CREATE_NETWORK_CONFIG}" != '1' ]]; then
    rm -f "${NETWORK_CONFIG_PATH}"
    return 0
  fi

  cat > "${NETWORK_CONFIG_PATH}" << 'EOF'
version: 2
ethernets:
  default:
    match:
      name: "en*"
    dhcp4: true
    dhcp6: false
EOF
}

build_seed_iso_cmd() {
  local files

  files=("${USER_DATA_PATH}" "${META_DATA_PATH}")
  if [[ "${CREATE_NETWORK_CONFIG}" == '1' ]]; then
    files+=("${NETWORK_CONFIG_PATH}")
  fi

  if [[ -x "${MKISOFS_BIN}" ]]; then
    SEED_ISO_CMD=(
      "${MKISOFS_BIN}"
      -output "${SEED_ISO}"
      -volid cidata
      -joliet
      -rock
      "${files[@]}"
    )
    return 0
  fi

  if [[ -x "${XORRISO_BIN}" ]]; then
    SEED_ISO_CMD=(
      "${XORRISO_BIN}"
      -as mkisofs
      -output "${SEED_ISO}"
      -volid cidata
      -joliet
      -rock
      "${files[@]}"
    )
    return 0
  fi

  fail 'No ISO builder found; install app-cdr/cdrtools for mkisofs or provide XORRISO_BIN'
}

print_seed_iso_cmd() {
  printf '%q ' "${SEED_ISO_CMD[@]}"
  printf '\n'
}

run_seed_iso_cmd() {
  build_seed_iso_cmd

  if [[ "${CLOUD_INIT_SEED_DRY_RUN}" == '1' ]]; then
    print_seed_iso_cmd
    return 0
  fi

  rm -f "${SEED_ISO}"
  "${SEED_ISO_CMD[@]}"
}

main() {
  ensure_seed_dir
  render_meta_data
  render_user_data
  render_network_config
  log "Writing seed ISO to ${SEED_ISO}"
  run_seed_iso_cmd
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
