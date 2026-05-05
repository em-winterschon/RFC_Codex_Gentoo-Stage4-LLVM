#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_VAULT_FILE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"

usage() {
  cat <<EOF
Usage: import-hetzner-dns-vault.sh TOKEN_CFG [VAULT_FILE]

Imports Hetzner Cloud DNS token metadata from an operator-private shell config
into an encrypted Ansible Vault file.

Expected TOKEN_CFG keys:
  RFC1918_DOMAINS_TLD_LIST
  RFC1918_DOMAINS_TLD_DNS_API_TOKEN_NAME
  RFC1918_DOMAINS_TLD_DNS_API_TOKEN_KEY
  VERNETZEN_DOMAINS_TLD_LIST
  VERNETZEN_DOMAINS_TLD_DNS_API_TOKEN_NAME
  VERNETZEN_DOMAINS_TLD_DNS_API_TOKEN_KEY
  YUKON_DOMAINS_TLD_LIST
  YUKON_DOMAINS_TLD_DNS_API_TOKEN_NAME
  YUKON_DOMAINS_TLD_DNS_API_TOKEN_KEY
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

token_cfg="${1:-}"
vault_file="${2:-${DEFAULT_VAULT_FILE}}"

if [[ -z "${token_cfg}" ]]; then
  usage >&2
  exit 2
fi
if [[ ! -r "${token_cfg}" ]]; then
  printf 'ERROR: token config is not readable: %s\n' "${token_cfg}" >&2
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

set -a
# shellcheck disable=SC1090
source "${token_cfg}"
set +a

export PLAIN_VAULT_FILE="${plain_vault}"
export MERGED_VAULT_FILE="${merged_vault}"

python3 - <<'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

import yaml

plain_vault = Path(os.environ["PLAIN_VAULT_FILE"])
merged_vault = Path(os.environ["MERGED_VAULT_FILE"])

payload = yaml.safe_load(plain_vault.read_text(encoding="utf-8")) or {}
if not isinstance(payload, dict):
    raise SystemExit("vault payload must be a mapping")


def split_domains(value: str) -> list[str]:
    return [item for item in re.split(r"[\s,]+", value.strip()) if item]


scopes = {
    "rfc1918": "RFC1918",
    "vernetzen": "VERNETZEN",
    "yukon": "YUKON",
}

for scope, prefix in scopes.items():
    zones = os.environ.get(f"{prefix}_DOMAINS_TLD_LIST", "")
    token_name = os.environ.get(f"{prefix}_DOMAINS_TLD_DNS_API_TOKEN_NAME", "")
    api_token = os.environ.get(f"{prefix}_DOMAINS_TLD_DNS_API_TOKEN_KEY", "")
    missing = [
        name
        for name, value in (
            (f"{prefix}_DOMAINS_TLD_LIST", zones),
            (f"{prefix}_DOMAINS_TLD_DNS_API_TOKEN_NAME", token_name),
            (f"{prefix}_DOMAINS_TLD_DNS_API_TOKEN_KEY", api_token),
        )
        if not value.strip()
    ]
    if missing:
        raise SystemExit(f"missing required token config keys: {', '.join(missing)}")
    payload[f"vault_hetzner_dns_{scope}_zones"] = split_domains(zones)
    payload[f"vault_hetzner_dns_{scope}_token_name"] = token_name.strip()
    payload[f"vault_hetzner_dns_{scope}_api_token"] = api_token.strip()

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
"${WITH_ENV}" ansible-vault encrypt "${encrypt_args[@]}" "${merged_vault}" --output "${encrypted_vault}" >/dev/null
chmod 600 "${encrypted_vault}"
mv "${encrypted_vault}" "${vault_file}"
printf 'updated_vault=%s\n' "${vault_file}"
