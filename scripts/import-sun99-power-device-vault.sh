#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_SOURCE_FILE="/root/operator-private/voltage-ops/ups-ats-pdu.sun99-white-rack-infra.info"
DEFAULT_VAULT_FILE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"

usage() {
  cat << EOF
Usage: import-sun99-power-device-vault.sh [SOURCE_FILE] [VAULT_FILE]

Imports SUN99 white-rack power-device credentials from the operator-private
markdown/key-value source into the encrypted Ansible Vault file.

Defaults:
  SOURCE_FILE ${DEFAULT_SOURCE_FILE}
  VAULT_FILE  ${DEFAULT_VAULT_FILE}

Vault variables written:
  vault_power_devices_sun99_white_rack_primary_ups_username
  vault_power_devices_sun99_white_rack_primary_ups_password
  vault_power_devices_sun99_white_rack_secondary_ups_username
  vault_power_devices_sun99_white_rack_secondary_ups_password
  vault_power_devices_sun99_white_rack_primary_ats_username
  vault_power_devices_sun99_white_rack_primary_ats_password
  vault_power_devices_sun99_white_rack_primary_pdu_username
  vault_power_devices_sun99_white_rack_primary_pdu_password
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

source_file="${1:-${DEFAULT_SOURCE_FILE}}"
vault_file="${2:-${DEFAULT_VAULT_FILE}}"

if [[ ! -r "${source_file}" ]]; then
  printf 'ERROR: power-device credential source is not readable: %s\n' "${source_file}" >&2
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

export SUN99_POWER_DEVICE_SOURCE_FILE="${source_file}"
export PLAIN_VAULT_FILE="${plain_vault}"
export MERGED_VAULT_FILE="${merged_vault}"

python3 - << 'PY'
from __future__ import annotations

import os
import re
from pathlib import Path

import yaml

SECTION_SLUGS = {
    "Primary UPS": "primary_ups",
    "Secondary UPS": "secondary_ups",
    "Primary ATS": "primary_ats",
    "Primary PDU": "primary_pdu",
}

KEY_PATTERN = re.compile(r"^\s*([^#:=]+?)\s*[:=]\s*(.*?)\s*$")


def parse_source(path: Path) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current: str | None = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("##"):
            heading = line.lstrip("#").strip()
            current = SECTION_SLUGS.get(heading)
            if current:
                sections.setdefault(current, {})
            continue
        if line.startswith("#"):
            continue
        if not current:
            continue
        match = KEY_PATTERN.match(line)
        if not match:
            continue
        key = match.group(1).strip().lower().replace("-", "_")
        value = match.group(2).strip().strip('"').strip("'")
        sections[current][key] = value

    return sections


plain_vault = Path(os.environ["PLAIN_VAULT_FILE"])
merged_vault = Path(os.environ["MERGED_VAULT_FILE"])
source_file = Path(os.environ["SUN99_POWER_DEVICE_SOURCE_FILE"])

payload = yaml.safe_load(plain_vault.read_text(encoding="utf-8")) or {}
if not isinstance(payload, dict):
    raise SystemExit("vault payload must be a mapping")

sections = parse_source(source_file)
missing_sections = sorted(set(SECTION_SLUGS.values()) - set(sections))
if missing_sections:
    raise SystemExit(f"missing required sections: {', '.join(missing_sections)}")

imported = 0
for section_slug in SECTION_SLUGS.values():
    values = sections[section_slug]
    for field in ("username", "password"):
        value = values.get(field, "")
        if not value:
            raise SystemExit(f"missing {field} for section {section_slug}")
        payload[f"vault_power_devices_sun99_white_rack_{section_slug}_{field}"] = value
        imported += 1

payload["vault_power_devices_sun99_white_rack_import_note"] = (
    "Imported from operator-private voltage-ops source; do not commit plaintext source."
)
payload["vault_power_devices_sun99_white_rack_imported_device_slugs"] = sorted(
    SECTION_SLUGS.values()
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
