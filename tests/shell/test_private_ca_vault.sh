#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IMPORTER="${REPO_ROOT}/scripts/import-private-ca-vault.sh"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"
VALIDATE="${REPO_ROOT}/scripts/validate-ansible-vaults.sh"
VAULT_DOCS="${REPO_ROOT}/docs/ANSIBLE-VAULT.md"
PRIVATE_CA_VARS="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/private_ca.yml"

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

assert_file_contains "${IMPORTER}" "vault_private_ca_rfc1918_cert_pem"
assert_file_contains "${IMPORTER}" "RFC1918_PRIVATE_CA_PKCS12_BASE64"
assert_file_contains "${VAULT_DOCS}" "Private CA"
assert_file_contains "${PRIVATE_CA_VARS}" "private_certificate_authorities:"
assert_file_contains "${PRIVATE_CA_VARS}" "vault_private_ca_rfc1918_cert_pem"
assert_file_contains "${PRIVATE_CA_VARS}" "service_tls_certificate_authority_default: rfc1918_private_ca"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

vault_password_file="${tmpdir}/vault-pass.txt"
vault_env_file="${tmpdir}/ANSIBLE_VARS.ENV"
plain_vault="${tmpdir}/vault.plain.yml"
vault_file="${tmpdir}/vault.yml"
ca_file="${tmpdir}/RFC1918_PRIVATE_CA.env"

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

cat > "${ca_file}" << 'EOF'
RFC1918_PRIVATE_CA_NAME="rfc1918_private_ca"
RFC1918_PRIVATE_CA_CERT_PEM="-----BEGIN CERTIFICATE-----
fixture-ca-cert
-----END CERTIFICATE-----"
RFC1918_PRIVATE_CA_KEY_PEM="-----BEGIN PRIVATE KEY-----
fixture-ca-key
-----END PRIVATE KEY-----"
RFC1918_PRIVATE_CA_PKCS12_BASE64="ZmFrZS1wa2NzMTI="
RFC1918_PRIVATE_CA_PKCS12_PASSWORD="fixture-pkcs12-password"
EOF
chmod 600 "${ca_file}"

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${IMPORTER}" "${ca_file}" "${vault_file}" > "${tmpdir}/private-ca-import.out"

grep -Fq 'updated_vault=' "${tmpdir}/private-ca-import.out" || fail "importer did not report updated vault"
head -n 1 "${vault_file}" | grep -q '^\$ANSIBLE_VAULT;' || fail "updated vault is not encrypted"
if grep -Fq 'fixture-ca-key' "${vault_file}"; then
  fail "updated vault contains plaintext CA key"
fi

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${VALIDATE}" "${vault_file}" > /dev/null
ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${WITH_ENV}" ansible-vault view "${vault_file}" > "${tmpdir}/view.yml"
assert_file_contains "${tmpdir}/view.yml" "vault_existing_secret: keep-me"
assert_file_contains "${tmpdir}/view.yml" "vault_private_ca_rfc1918_name: rfc1918_private_ca"
assert_file_contains "${tmpdir}/view.yml" "vault_private_ca_rfc1918_cert_pem:"
assert_file_contains "${tmpdir}/view.yml" "fixture-ca-cert"
assert_file_contains "${tmpdir}/view.yml" "vault_private_ca_rfc1918_key_pem:"
assert_file_contains "${tmpdir}/view.yml" "fixture-ca-key"
assert_file_contains "${tmpdir}/view.yml" "vault_private_ca_rfc1918_pkcs12_base64: ZmFrZS1wa2NzMTI="

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
