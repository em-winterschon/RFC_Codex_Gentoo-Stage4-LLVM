#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
VAULT_ENV_HELPER="${SCRIPT_DIR}/with-ansible-vault-env.sh"

usage() {
  cat << 'EOF'
Usage: validate-ansible-vaults.sh [path...]

Validates that Ansible vault files are encrypted and decryptable with the
configured local vault identity. If no paths are supplied, scans the Ansible
inventory tree for files named vault.yml or vault.yaml.

This script never prints decrypted vault content.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

vault_files=()

if [[ "$#" -gt 0 ]]; then
  for path in "$@"; do
    if [[ -d "${path}" ]]; then
      while IFS= read -r file; do
        vault_files+=("${file}")
      done < <(find "${path}" -type f \( -name 'vault.yml' -o -name 'vault.yaml' \) | sort)
    elif [[ -f "${path}" ]]; then
      vault_files+=("${path}")
    else
      printf 'ERROR: vault path does not exist: %s\n' "${path}" >&2
      exit 2
    fi
  done
else
  while IFS= read -r file; do
    vault_files+=("${file}")
  done < <(find "${ANSIBLE_ROOT}/inventories" -type f \( -name 'vault.yml' -o -name 'vault.yaml' \) | sort)
fi

if [[ "${#vault_files[@]}" -eq 0 ]]; then
  printf 'ERROR: no vault files found\n' >&2
  exit 2
fi

for vault_file in "${vault_files[@]}"; do
  first_line="$(head -n 1 "${vault_file}")"
  if [[ "${first_line}" != '$ANSIBLE_VAULT;'* ]]; then
    printf 'ERROR: vault file is not encrypted: %s\n' "${vault_file}" >&2
    exit 1
  fi

  "${VAULT_ENV_HELPER}" ansible-vault view "${vault_file}" > /dev/null
  printf 'PASS: decryptable vault %s\n' "${vault_file}"
done
