#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_CA_FILE="/root/.ssh/vault/private-ca/RFC1918_PRIVATE_CA.env"
DEFAULT_VAULT_FILE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"

usage() {
  cat << EOF
Usage: import-private-ca-vault.sh [CA_ENV_FILE] [VAULT_FILE]

Imports private CA material references or PEM/PKCS#12 payloads into the
encrypted local-network Ansible Vault.

Accepted source keys:
  RFC1918_PRIVATE_CA_NAME
  RFC1918_PRIVATE_CA_CERT_PEM
  RFC1918_PRIVATE_CA_KEY_PEM
  RFC1918_PRIVATE_CA_CHAIN_PEM
  RFC1918_PRIVATE_CA_PKCS12_BASE64
  RFC1918_PRIVATE_CA_PKCS12_PASSWORD
  RFC1918_PRIVATE_CA_CERT_PATH
  RFC1918_PRIVATE_CA_KEY_PATH
  RFC1918_PRIVATE_CA_CHAIN_PATH
  RFC1918_PRIVATE_CA_PKCS12_PATH

Defaults:
  CA_ENV_FILE ${DEFAULT_CA_FILE}
  VAULT_FILE  ${DEFAULT_VAULT_FILE}

Vault variables written:
  vault_private_ca_rfc1918_*
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

ca_file="${1:-${DEFAULT_CA_FILE}}"
vault_file="${2:-${DEFAULT_VAULT_FILE}}"

if [[ ! -r "${ca_file}" ]]; then
  printf 'ERROR: private CA source file is not readable: %s\n' "${ca_file}" >&2
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

export PRIVATE_CA_SOURCE_FILE="${ca_file}"
export PLAIN_VAULT_FILE="${plain_vault}"
export MERGED_VAULT_FILE="${merged_vault}"

python3 - << 'PY'
from __future__ import annotations

import os
import shlex
from pathlib import Path

import yaml

plain_vault = Path(os.environ["PLAIN_VAULT_FILE"])
merged_vault = Path(os.environ["MERGED_VAULT_FILE"])
source_file = Path(os.environ["PRIVATE_CA_SOURCE_FILE"])

payload = yaml.safe_load(plain_vault.read_text(encoding="utf-8")) or {}
if not isinstance(payload, dict):
    raise SystemExit("vault payload must be a mapping")


def parse_env(path: Path) -> dict[str, str]:
    parsed: dict[str, str] = {}
    pending_key = ""
    pending_lines: list[str] = []
    quote_char = ""

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip("\n")
        stripped = line.strip()
        if not pending_key and (not stripped or stripped.startswith("#")):
            continue

        if pending_key:
            if stripped.endswith(quote_char):
                pending_lines.append(line[: line.rfind(quote_char)])
                parsed[pending_key] = "\n".join(pending_lines)
                pending_key = ""
                pending_lines = []
                quote_char = ""
            else:
                pending_lines.append(line)
            continue

        if "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key.startswith("RFC1918_PRIVATE_CA_"):
            continue

        if value.startswith(("'", '"')):
            quote_char = value[0]
            remainder = value[1:]
            if remainder.endswith(quote_char):
                parsed[key] = remainder[:-1]
                quote_char = ""
            else:
                pending_key = key
                pending_lines = [remainder]
            continue

        parsed[key] = shlex.split(value)[0] if value else ""

    if pending_key:
        raise SystemExit(f"unterminated quoted value for {pending_key}")
    return parsed


source = parse_env(source_file)
if not source:
    raise SystemExit("no RFC1918_PRIVATE_CA_* keys found in private CA source file")

mapping = {
    "RFC1918_PRIVATE_CA_NAME": "vault_private_ca_rfc1918_name",
    "RFC1918_PRIVATE_CA_CERT_PEM": "vault_private_ca_rfc1918_cert_pem",
    "RFC1918_PRIVATE_CA_KEY_PEM": "vault_private_ca_rfc1918_key_pem",
    "RFC1918_PRIVATE_CA_CHAIN_PEM": "vault_private_ca_rfc1918_chain_pem",
    "RFC1918_PRIVATE_CA_PKCS12_BASE64": "vault_private_ca_rfc1918_pkcs12_base64",
    "RFC1918_PRIVATE_CA_PKCS12_PASSWORD": "vault_private_ca_rfc1918_pkcs12_password",
    "RFC1918_PRIVATE_CA_CERT_PATH": "vault_private_ca_rfc1918_cert_path",
    "RFC1918_PRIVATE_CA_KEY_PATH": "vault_private_ca_rfc1918_key_path",
    "RFC1918_PRIVATE_CA_CHAIN_PATH": "vault_private_ca_rfc1918_chain_path",
    "RFC1918_PRIVATE_CA_PKCS12_PATH": "vault_private_ca_rfc1918_pkcs12_path",
}

imported = 0
for source_key, vault_key in mapping.items():
    value = source.get(source_key, "").strip()
    if not value:
        continue
    payload[vault_key] = value
    imported += 1

if imported == 0:
    raise SystemExit("no populated RFC1918_PRIVATE_CA_* values found")

payload.setdefault("vault_private_ca_rfc1918_name", "rfc1918_private_ca")
payload["vault_private_ca_rfc1918_import_note"] = (
    "Imported from operator-private CA source; do not commit plaintext CA material."
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
