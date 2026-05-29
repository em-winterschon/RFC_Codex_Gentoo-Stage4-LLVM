#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IMPORTER="${REPO_ROOT}/scripts/import-context7-vault.sh"
MATERIALIZER="${REPO_ROOT}/scripts/materialize-context7-mcp-secret.sh"
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

vault_docs="${REPO_ROOT}/docs/ANSIBLE-VAULT.md"

assert_file_contains "${IMPORTER}" "vault_context7_api_token"
assert_file_contains "${IMPORTER}" "CONTEXT7_API_KEY"
assert_file_contains "${MATERIALIZER}" "vault_context7_api_token"
assert_file_contains "${MATERIALIZER}" "materialized_context7_token="
assert_file_contains "${vault_docs}" "Context7 MCP Token"
assert_file_contains "${vault_docs}" "scripts/import-context7-vault.sh"
assert_file_contains "${vault_docs}" "scripts/materialize-context7-mcp-secret.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

vault_password_file="${tmpdir}/vault-pass.txt"
vault_env_file="${tmpdir}/ANSIBLE_VARS.ENV"
plain_vault="${tmpdir}/vault.plain.yml"
vault_file="${tmpdir}/vault.yml"
token_file="${tmpdir}/context7_api_key"
materialized_file="${tmpdir}/runtime/context7_api_key"

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

printf 'fixture-context7-token\n' > "${token_file}"
chmod 600 "${token_file}"

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${IMPORTER}" "${token_file}" "${vault_file}" > "${tmpdir}/context7-import.out"

grep -Fq 'updated_vault=' "${tmpdir}/context7-import.out" || fail "importer did not report updated vault"
head -n 1 "${vault_file}" | grep -q '^\$ANSIBLE_VAULT;' || fail "updated vault is not encrypted"
if grep -Fq 'fixture-context7-token' "${vault_file}"; then
  fail "updated vault contains plaintext token"
fi

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${VALIDATE}" "${vault_file}" > /dev/null
ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${WITH_ENV}" ansible-vault view "${vault_file}" > "${tmpdir}/view.yml"
assert_file_contains "${tmpdir}/view.yml" "vault_existing_secret: keep-me"
assert_file_contains "${tmpdir}/view.yml" "vault_context7_api_token: fixture-context7-token"
assert_file_contains "${tmpdir}/view.yml" "vault_context7_token_name: CONTEXT7_API_KEY"

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${MATERIALIZER}" "${vault_file}" "${materialized_file}" > "${tmpdir}/context7-materialize.out"
grep -Fq "materialized_context7_token=${materialized_file}" "${tmpdir}/context7-materialize.out" ||
  fail "materializer did not report output path"
[[ "$(cat "${materialized_file}")" == "fixture-context7-token" ]] ||
  fail "materialized token mismatch"
[[ "$(stat -c '%a' "${materialized_file}")" == "600" ]] ||
  fail "materialized token mode is not 600"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
