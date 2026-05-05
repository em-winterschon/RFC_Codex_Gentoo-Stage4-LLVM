#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: with-ansible-vault-env.sh [command...]

Sources the local Ansible Vault environment and executes command. If no command
is provided, runs ansible-vault.

Environment:
  ANSIBLE_VAULT_ENV_FILE  Path to env file. Default: /root/.ssh/vault/ANSIBLE_VARS.ENV

The env file is expected to export Ansible Vault variables such as:
  ANSIBLE_VAULT_PASSWORD_FILE
  ANSIBLE_VAULT_IDENTITY_LIST
  ANSIBLE_VAULT_ENCRYPT_IDENTITY
  ANSIBLE_VAULT_ID_MATCH
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

vault_env_file="${ANSIBLE_VAULT_ENV_FILE:-/root/.ssh/vault/ANSIBLE_VARS.ENV}"

if [[ ! -r "${vault_env_file}" ]]; then
  printf 'ERROR: vault env file is not readable: %s\n' "${vault_env_file}" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "${vault_env_file}"
set +a

expand_home_path() {
  local path="$1"
  case "${path}" in
    '~')
      printf '%s\n' "${HOME}"
      ;;
    '~/'*)
      printf '%s/%s\n' "${HOME}" "${path#\~/}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}

expand_identity_list_home_paths() {
  local identity_list="$1"
  local identity
  local identity_name
  local identity_path
  local expanded=()

  IFS=',' read -r -a identities <<< "${identity_list}"
  for identity in "${identities[@]}"; do
    if [[ "${identity}" == *@* ]]; then
      identity_name="${identity%%@*}"
      identity_path="${identity#*@}"
      expanded+=("${identity_name}@$(expand_home_path "${identity_path}")")
    else
      expanded+=("$(expand_home_path "${identity}")")
    fi
  done

  local IFS=','
  printf '%s\n' "${expanded[*]}"
}

if [[ -z "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]]; then
  printf 'ERROR: ANSIBLE_VAULT_PASSWORD_FILE is not set by %s\n' "${vault_env_file}" >&2
  exit 2
fi

ANSIBLE_VAULT_PASSWORD_FILE="$(expand_home_path "${ANSIBLE_VAULT_PASSWORD_FILE}")"
export ANSIBLE_VAULT_PASSWORD_FILE

if [[ -n "${ANSIBLE_VAULT_IDENTITY_LIST:-}" ]]; then
  ANSIBLE_VAULT_IDENTITY_LIST="$(expand_identity_list_home_paths "${ANSIBLE_VAULT_IDENTITY_LIST}")"
  export ANSIBLE_VAULT_IDENTITY_LIST
fi

if [[ ! -r "${ANSIBLE_VAULT_PASSWORD_FILE}" ]]; then
  printf 'ERROR: ANSIBLE_VAULT_PASSWORD_FILE is not readable: %s\n' "${ANSIBLE_VAULT_PASSWORD_FILE}" >&2
  exit 2
fi

if [[ "$#" -eq 0 ]]; then
  set -- ansible-vault
fi

exec "$@"
