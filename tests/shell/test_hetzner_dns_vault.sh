#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
IMPORTER="${REPO_ROOT}/scripts/import-hetzner-dns-vault.sh"
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

dns_vars="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/dns_hetzner_cloud.yml"
validate_playbook="${ANSIBLE_ROOT}/playbooks/hetzner-dns-api-validate.yml"
requirements="${ANSIBLE_ROOT}/collections/requirements.yml"
docs="${REPO_ROOT}/docs/HETZNER-DNS-AUTOMATION.md"
vault_docs="${REPO_ROOT}/docs/ANSIBLE-VAULT.md"
wiki_docs="${REPO_ROOT}/docs/wiki/Hetzner-DNS-Automation.md"
wiki_home="${REPO_ROOT}/docs/wiki/Home.md"
wiki_sidebar="${REPO_ROOT}/docs/wiki/_Sidebar.md"

assert_file_contains "${IMPORTER}" "vault_hetzner_dns_"
assert_file_contains "${IMPORTER}" "_api_token"
assert_file_contains "${dns_vars}" "dns_hetzner_cloud_token_groups"
assert_file_contains "${dns_vars}" "vault_hetzner_dns_rfc1918_api_token"
assert_file_contains "${dns_vars}" "allow_delete: false"
assert_file_contains "${validate_playbook}" "Hetzner Cloud DNS API token"
assert_file_contains "${validate_playbook}" "/zones"
assert_file_contains "${requirements}" "hetzner.hcloud"
assert_file_contains "${docs}" "Hetzner DNS Automation"
assert_file_contains "${docs}" "scripts/import-hetzner-dns-vault.sh"
assert_file_contains "${vault_docs}" "Hetzner DNS Tokens"
assert_file_contains "${wiki_docs}" "Hetzner DNS Automation"
assert_file_contains "${wiki_home}" "Hetzner DNS Automation"
assert_file_contains "${wiki_sidebar}" "Hetzner DNS Automation"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

vault_password_file="${tmpdir}/vault-pass.txt"
vault_env_file="${tmpdir}/ANSIBLE_VARS.ENV"
plain_vault="${tmpdir}/vault.plain.yml"
vault_file="${tmpdir}/vault.yml"
token_cfg="${tmpdir}/dns-api-info.cfg"

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

cat > "${token_cfg}" << 'EOF'
RFC1918_DOMAINS_TLD_LIST="rfc1918.io rfc1918.host"
RFC1918_DOMAINS_TLD_DNS_API_TOKEN_NAME="rfc1918-token"
RFC1918_DOMAINS_TLD_DNS_API_TOKEN_KEY="rfc1918-secret"
VERNETZEN_DOMAINS_TLD_LIST="vernetzen.example"
VERNETZEN_DOMAINS_TLD_DNS_API_TOKEN_NAME="vernetzen-token"
VERNETZEN_DOMAINS_TLD_DNS_API_TOKEN_KEY="vernetzen-secret"
YUKON_DOMAINS_TLD_LIST="yukon.example"
YUKON_DOMAINS_TLD_DNS_API_TOKEN_NAME="yukon-token"
YUKON_DOMAINS_TLD_DNS_API_TOKEN_KEY="yukon-secret"
EOF
chmod 600 "${token_cfg}"

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${IMPORTER}" "${token_cfg}" "${vault_file}" > /tmp/hetzner-dns-import.out

grep -Fq 'updated_vault=' /tmp/hetzner-dns-import.out || fail "importer did not report updated vault"
head -n 1 "${vault_file}" | grep -q '^\$ANSIBLE_VAULT;' || fail "updated vault is not encrypted"
if grep -Fq 'rfc1918-secret' "${vault_file}"; then
  fail "updated vault contains plaintext token"
fi

ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${VALIDATE}" "${vault_file}" > /dev/null
ANSIBLE_VAULT_ENV_FILE="${vault_env_file}" "${WITH_ENV}" ansible-vault view "${vault_file}" > "${tmpdir}/view.yml"
assert_file_contains "${tmpdir}/view.yml" "vault_existing_secret: keep-me"
assert_file_contains "${tmpdir}/view.yml" "vault_hetzner_dns_rfc1918_api_token: rfc1918-secret"
assert_file_contains "${tmpdir}/view.yml" "vault_hetzner_dns_vernetzen_token_name: vernetzen-token"
assert_file_contains "${tmpdir}/view.yml" "vault_hetzner_dns_yukon_zones:"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -rf "${tmpdir}" "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${validate_playbook}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
