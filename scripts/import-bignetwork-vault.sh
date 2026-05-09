#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_TOKEN_FILE="/root/.ssh/codex.d/tokens/BIGNETWORK_TOKEN_CODEXIAN"
DEFAULT_VAULT_FILE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"

usage() {
  cat << EOF
Usage: import-bignetwork-vault.sh [TOKEN_FILE] [VAULT_FILE]

Imports the operator-private BigNetwork Forge/Codexian API token into an
encrypted Ansible Vault file.

Defaults:
  TOKEN_FILE  ${DEFAULT_TOKEN_FILE}
  VAULT_FILE  ${DEFAULT_VAULT_FILE}

Vault variables written:
  vault_bignetwork_codexian_api_token
  vault_bignetwork_codexian_token_name
  vault_bignetwork_codexian_account_name
  vault_bignetwork_codexian_token_owner
  vault_bignetwork_codexian_purpose
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

token_file="${1:-${DEFAULT_TOKEN_FILE}}"
vault_file="${2:-${DEFAULT_VAULT_FILE}}"

if [[ ! -r "${token_file}" ]]; then
  printf 'ERROR: token file is not readable: %s\n' "${token_file}" >&2
  exit 1
fi
if [[ ! -r "${vault_file}" ]]; then
  printf 'ERROR: vault file is not readable: %s\n' "${vault_file}" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT
chmod 700 "${tmpdir}"

plain_vault="${tmpdir}/vault.plain.yml"
merged_vault="${tmpdir}/vault.merged.yml"
encrypted_vault="${tmpdir}/vault.encrypted.yml"
encrypt_vault_id="$(awk -F';' 'NR == 1 && NF >= 4 { print $4 }' "${vault_file}")"
if [[ -z "${encrypt_vault_id}" ]]; then
  encrypt_vault_id="$("${WITH_ENV}" bash -c 'first="${ANSIBLE_VAULT_IDENTITY_LIST%%,*}"; printf "%s" "${first%%@*}"')"
fi

"${WITH_ENV}" ansible-vault view "${vault_file}" > "${plain_vault}"
chmod 600 "${plain_vault}"

export BIGNETWORK_TOKEN_FILE="${token_file}"
export PLAIN_VAULT_FILE="${plain_vault}"
export MERGED_VAULT_FILE="${merged_vault}"

python3 - << 'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

plain_vault = Path(os.environ["PLAIN_VAULT_FILE"])
merged_vault = Path(os.environ["MERGED_VAULT_FILE"])
token_file = Path(os.environ["BIGNETWORK_TOKEN_FILE"])

payload = yaml.safe_load(plain_vault.read_text(encoding="utf-8")) or {}
if not isinstance(payload, dict):
    raise SystemExit("vault payload must be a mapping")

token = token_file.read_text(encoding="utf-8").strip()
if not token:
    raise SystemExit("BigNetwork token file is empty")

payload["vault_bignetwork_codexian_api_token"] = token
payload["vault_bignetwork_codexian_token_name"] = "BIGNETWORK_TOKEN_CODEXIAN"
payload["vault_bignetwork_codexian_account_name"] = "codexian"
payload["vault_bignetwork_codexian_token_owner"] = "Forge"
payload["vault_bignetwork_codexian_purpose"] = (
    "BigNetwork SD-WAN API and bn client onboarding for FMT2/SFO200 transport validation"
)

merged_vault.write_text(
    yaml.safe_dump(payload, default_flow_style=False, explicit_start=True, sort_keys=True),
    encoding="utf-8",
)
PY

chmod 600 "${merged_vault}"
encrypt_args=()
if [[ -n "${encrypt_vault_id}" ]]; then
  encrypt_args+=(--encrypt-vault-id "${encrypt_vault_id}")
fi
"${WITH_ENV}" ansible-vault encrypt "${encrypt_args[@]}" "${merged_vault}" --output "${encrypted_vault}" > /dev/null
chmod 600 "${encrypted_vault}"
mv "${encrypted_vault}" "${vault_file}"
printf 'updated_vault=%s\n' "${vault_file}"
