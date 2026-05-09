#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_TOKEN_FILE="/root/.ssh/codex.d/tokens/PDU_RFC99_CORECTRL"
DEFAULT_VAULT_FILE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"

usage() {
  cat << EOF
Usage: import-pdu-rfc99-corectrl-vault.sh [PDU_FILE] [VAULT_FILE]

Imports operator-private APC AP7901 PDU credentials into an encrypted Ansible
Vault file. The source file is colon-separated shell-ish text, not YAML.

Defaults:
  PDU_FILE    ${DEFAULT_TOKEN_FILE}
  VAULT_FILE  ${DEFAULT_VAULT_FILE}

Vault variables written:
  vault_pdu_rfc99_corecontrol_*
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

pdu_file="${1:-${DEFAULT_TOKEN_FILE}}"
vault_file="${2:-${DEFAULT_VAULT_FILE}}"

if [[ ! -r "${pdu_file}" ]]; then
  printf 'ERROR: PDU credential file is not readable: %s\n' "${pdu_file}" >&2
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

export PDU_TOKEN_FILE="${pdu_file}"
export PLAIN_VAULT_FILE="${plain_vault}"
export MERGED_VAULT_FILE="${merged_vault}"

python3 - << 'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

plain_vault = Path(os.environ["PLAIN_VAULT_FILE"])
merged_vault = Path(os.environ["MERGED_VAULT_FILE"])
pdu_file = Path(os.environ["PDU_TOKEN_FILE"])

payload = yaml.safe_load(plain_vault.read_text(encoding="utf-8")) or {}
if not isinstance(payload, dict):
    raise SystemExit("vault payload must be a mapping")

imported = 0
for raw_line in pdu_file.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or ":" not in line:
        continue
    key, value = line.split(":", 1)
    key = key.strip()
    if not key.startswith("vault_pdu_"):
        continue
    payload[key] = value.strip().strip('"')
    imported += 1

if imported == 0:
    raise SystemExit("no vault_pdu_* keys found in PDU credential file")

payload["vault_pdu_rfc99_corecontrol_import_note"] = (
    "Imported from operator-private PDU_RFC99_CORECTRL; do not commit plaintext source."
)

merged_vault.write_text(
    yaml.safe_dump(payload, default_flow_style=False, explicit_start=True, sort_keys=True),
    encoding="utf-8",
)
print(f"imported_keys={imported}")
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
