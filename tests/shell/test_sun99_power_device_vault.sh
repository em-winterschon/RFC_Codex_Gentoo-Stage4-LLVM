#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
IMPORTER="${REPO_ROOT}/scripts/import-sun99-power-device-vault.sh"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"
VALIDATE="${REPO_ROOT}/scripts/validate-ansible-vaults.sh"
POWER_VARS="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/power_devices.yml"
FORGE_PROFILE="${ANSIBLE_ROOT}/profile-package-lists/stage5-metal-forge-automation-admin.packages"
VAULT_DOCS="${REPO_ROOT}/docs/ANSIBLE-VAULT.md"
POWER_DOCS="${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_contains "${IMPORTER}" "vault_power_devices_sun99_white_rack_primary_ups_username"
assert_file_contains "${IMPORTER}" "ups-ats-pdu.sun99-white-rack-infra.info"
assert_file_contains "${IMPORTER}" "Primary ATS"
assert_file_contains "${POWER_VARS}" "sun99_white_rack_power_devices:"
assert_file_contains "${POWER_VARS}" "vault_power_devices_sun99_white_rack_primary_ups_password"
assert_file_contains "${FORGE_PROFILE}" "sys-power/nut"
assert_file_contains "${VAULT_DOCS}" "SUN99 Power Device Credentials"
assert_file_contains "${POWER_DOCS}" "SUN99_POWER_EXPECT_CYBERPOWER_USB=1"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

vault_password_file="${tmpdir}/vault-pass.txt"
vault_env_file="${tmpdir}/ANSIBLE_VARS.ENV"
plain_vault="${tmpdir}/vault.plain.yml"
vault_file="${tmpdir}/vault.yml"
source_file="${tmpdir}/ups-ats-pdu.sun99-white-rack-infra.info"

printf 'test-vault-password\n' > "${vault_password_file}"
chmod 600 "${vault_password_file}"

cat > "${vault_env_file}" << EOF
export ANSIBLE_VAULT_PASSWORD_FILE=${vault_password_file}
export ANSIBLE_VAULT_IDENTITY_LIST=test@${vault_password_file}
EOF

cat > "${plain_vault}" << 'EOF'
---
vault_existing_secret: keep-me
EOF

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" \
  "${WITH_ENV}" ansible-vault encrypt --encrypt-vault-id test "${plain_vault}" --output "${vault_file}" > /dev/null

cat > "${source_file}" << 'EOF'
# SUN99 White Rack Power Units

## Primary UPS
type = ups
brand = APC
sku = SRT1500RMXLA
ip-address = 172.16.99.242
hostname = ups-primary
username = primary-ups-user
password = primary-ups-pass

## Secondary UPS
type = ups
brand = CyberPower
sku = CP1500PFCRM2U
hostname = ups-secondary
username = secondary-ups-user
password = secondary-ups-pass

## Primary ATS
type = ats
brand = APC
sku = AP44xx
ip-address = 172.16.99.244
username = primary-ats-user
password = primary-ats-pass

## Primary PDU
type = pdu
brand = APC
sku = AP7901
ip-address = 172.16.99.241
username = primary-pdu-user
password = primary-pdu-pass
EOF
chmod 600 "${source_file}"

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${IMPORTER}" "${source_file}" "${vault_file}" > "${tmpdir}/power-import.out"

grep -Fq 'updated_vault=' "${tmpdir}/power-import.out" || fail "importer did not report updated vault"
head -n 1 "${vault_file}" | grep -q '^\$ANSIBLE_VAULT;' || fail "updated vault is not encrypted"
if grep -Fq 'primary-ups-pass' "${vault_file}"; then
  fail "updated vault contains plaintext power-device password"
fi

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${VALIDATE}" "${vault_file}" > /dev/null
ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${WITH_ENV}" ansible-vault view "${vault_file}" > "${tmpdir}/view.yml"
assert_file_contains "${tmpdir}/view.yml" "vault_existing_secret: keep-me"
assert_file_contains "${tmpdir}/view.yml" "vault_power_devices_sun99_white_rack_primary_ups_username: primary-ups-user"
assert_file_contains "${tmpdir}/view.yml" "vault_power_devices_sun99_white_rack_primary_ups_password: primary-ups-pass"
assert_file_contains "${tmpdir}/view.yml" "vault_power_devices_sun99_white_rack_secondary_ups_username: secondary-ups-user"
assert_file_contains "${tmpdir}/view.yml" "vault_power_devices_sun99_white_rack_primary_ats_password: primary-ats-pass"
assert_file_contains "${tmpdir}/view.yml" "vault_power_devices_sun99_white_rack_primary_pdu_password: primary-pdu-pass"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
