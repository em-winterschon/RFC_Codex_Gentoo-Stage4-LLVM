#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
IMPORTER="${REPO_ROOT}/scripts/import-bignetwork-vault.sh"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"
VALIDATE="${REPO_ROOT}/scripts/validate-ansible-vaults.sh"

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

bignetwork_vars="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/bignetwork.yml"
vault_docs="${REPO_ROOT}/docs/ANSIBLE-VAULT.md"
smoketest_docs="${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md"
transport_docs="${REPO_ROOT}/docs/FMT2-CHECKMK-TRANSPORT.md"
wiki_smoketest_docs="${REPO_ROOT}/docs/wiki/BigNetwork-FMT2-Smoke-Test.md"

assert_file_contains "${IMPORTER}" "vault_bignetwork_codexian_api_token"
assert_file_contains "${IMPORTER}" "BIGNETWORK_TOKEN_CODEXIAN"
assert_file_contains "${bignetwork_vars}" "vault_bignetwork_codexian_api_token"
assert_file_contains "${vault_docs}" "BigNetwork Token"
assert_file_contains "${smoketest_docs}" "BIGNETWORK_TOKEN_CODEXIAN"
assert_file_contains "${transport_docs}" "NanoPi R6S"
assert_file_contains "${wiki_smoketest_docs}" "BIGNETWORK_TOKEN_CODEXIAN"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

vault_password_file="${tmpdir}/vault-pass.txt"
vault_env_file="${tmpdir}/ANSIBLE_VARS.ENV"
plain_vault="${tmpdir}/vault.plain.yml"
vault_file="${tmpdir}/vault.yml"
token_file="${tmpdir}/BIGNETWORK_TOKEN_CODEXIAN"
import_output="${tmpdir}/bignetwork-import.out"

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

printf 'fixture-bignetwork-token\n' > "${token_file}"
chmod 600 "${token_file}"

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${IMPORTER}" "${token_file}" "${vault_file}" > "${import_output}"

grep -Fq 'updated_vault=' "${import_output}" || fail "importer did not report updated vault"
head -n 1 "${vault_file}" | grep -q '^\$ANSIBLE_VAULT;' || fail "updated vault is not encrypted"
if grep -Fq 'fixture-bignetwork-token' "${vault_file}"; then
  fail "updated vault contains plaintext token"
fi

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${VALIDATE}" "${vault_file}" > /dev/null
ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${WITH_ENV}" ansible-vault view "${vault_file}" > "${tmpdir}/view.yml"
assert_file_contains "${tmpdir}/view.yml" "vault_existing_secret: keep-me"
assert_file_contains "${tmpdir}/view.yml" "vault_bignetwork_codexian_api_token: fixture-bignetwork-token"
assert_file_contains "${tmpdir}/view.yml" "vault_bignetwork_codexian_token_name: BIGNETWORK_TOKEN_CODEXIAN"
assert_file_contains "${tmpdir}/view.yml" "vault_bignetwork_codexian_account_name: codexian"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
