#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WITH_ENV="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"
VALIDATE="${REPO_ROOT}/scripts/validate-ansible-vaults.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

vault_password_file="${tmpdir}/vault-pass.txt"
vault_env_file="${tmpdir}/ANSIBLE_VARS.ENV"
tilde_vault_env_file="${tmpdir}/ANSIBLE_VARS_TILDE.ENV"
plain_file="${tmpdir}/vault.plain.yml"
vault_file="${tmpdir}/vault.yml"
fake_home="${tmpdir}/home"

printf 'test-vault-password\n' > "${vault_password_file}"
chmod 600 "${vault_password_file}"

cat > "${vault_env_file}" <<EOF
export ANSIBLE_VAULT_PASSWORD_FILE=${vault_password_file}
export ANSIBLE_VAULT_IDENTITY_LIST=test@${vault_password_file}
export ANSIBLE_VAULT_ENCRYPT_IDENTITY=test
export ANSIBLE_VAULT_ID_MATCH=True
EOF

mkdir -p "${fake_home}/.ssh/vault"
cp "${vault_password_file}" "${fake_home}/.ssh/vault/test-vault-pass.txt"
cat > "${tilde_vault_env_file}" <<'EOF'
export ANSIBLE_VAULT_PASSWORD_FILE='~/.ssh/vault/test-vault-pass.txt'
export ANSIBLE_VAULT_IDENTITY_LIST='test@~/.ssh/vault/test-vault-pass.txt'
export ANSIBLE_VAULT_ENCRYPT_IDENTITY=test
export ANSIBLE_VAULT_ID_MATCH=True
EOF

cat > "${plain_file}" <<'EOF'
---
vault_test_secret: example
EOF

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" \
  "${WITH_ENV}" ansible-vault encrypt "${plain_file}" --output "${vault_file}" >/dev/null

head -n 1 "${vault_file}" | grep -q '^\$ANSIBLE_VAULT;' ||
  fail "encrypted vault header missing"

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" \
  "${VALIDATE}" "${vault_file}" >/dev/null

if ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${VALIDATE}" "${plain_file}" >/dev/null 2>&1; then
  fail "plaintext vault validation unexpectedly passed"
fi

HOME="${fake_home}" ANSIBLE_VAULT_ENV_FILE="${tilde_vault_env_file}" \
  "${WITH_ENV}" ansible-vault view "${vault_file}" >/dev/null

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
