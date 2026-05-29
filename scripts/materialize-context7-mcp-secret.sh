#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_VAULT_FILE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml"
DEFAULT_OUTPUT_FILE="/root/.codex/secrets/context7_api_key"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"

usage() {
  cat << EOF
Usage: materialize-context7-mcp-secret.sh [VAULT_FILE] [OUTPUT_FILE]

Writes vault_context7_api_token from encrypted Ansible Vault to a root-only
runtime token file for the Codex Context7 MCP wrapper. The token value is never
printed.

Defaults:
  VAULT_FILE   ${DEFAULT_VAULT_FILE}
  OUTPUT_FILE  ${DEFAULT_OUTPUT_FILE}
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

vault_file="${1:-${DEFAULT_VAULT_FILE}}"
output_file="${2:-${DEFAULT_OUTPUT_FILE}}"

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
token_file="${tmpdir}/context7_api_key"

"${WITH_ENV}" ansible-vault view "${vault_file}" > "${plain_vault}"
chmod 600 "${plain_vault}"

export PLAIN_VAULT_FILE="${plain_vault}"
export CONTEXT7_MATERIALIZED_TOKEN_FILE="${token_file}"

python3 - << 'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

plain_vault = Path(os.environ["PLAIN_VAULT_FILE"])
token_file = Path(os.environ["CONTEXT7_MATERIALIZED_TOKEN_FILE"])

payload = yaml.safe_load(plain_vault.read_text(encoding="utf-8")) or {}
if not isinstance(payload, dict):
    raise SystemExit("vault payload must be a mapping")

token = str(payload.get("vault_context7_api_token", "")).strip()
if not token:
    raise SystemExit("vault_context7_api_token is missing or empty")

token_file.write_text(token + "\n", encoding="utf-8")
PY

chmod 600 "${token_file}"
install -d -m 700 "$(dirname "${output_file}")"
install -m 600 "${token_file}" "${output_file}"
printf 'materialized_context7_token=%s\n' "${output_file}"
