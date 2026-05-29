#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/vault_ssh_ca_pilot"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/vault-ssh-ca-pilot.yml"
DOCS="${ROOT_DIR}/docs/IDENTITY-AAA.md"
WIKI_DOCS="${ROOT_DIR}/docs/wiki/Identity-AAA.md"
RUN_TESTS="${ROOT_DIR}/tests/shell/run-tests.sh"

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

assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_enabled: false"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_apply: false"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_ca_public_key:"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_trusted_user_ca_path: /etc/ssh/rfc1918_user_ca.pub"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_sshd_config_path: /etc/ssh/sshd_config"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_service_name: sshd"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_validation_user: codex-admin"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_expected_vault_mount: ssh-client-signer"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" "vault_ssh_ca_pilot_expected_vault_role: rfc1918-operator-codex-admin"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "Refuse Vault SSH CA pilot mutation without explicit apply gate"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "vault_ssh_ca_pilot_apply | bool"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "vault_ssh_ca_pilot_ca_public_key | length > 0"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "TrustedUserCAKeys {{ vault_ssh_ca_pilot_trusted_user_ca_path }}"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "ansible.builtin.lineinfile:"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "validate: \"sshd -t -f %s\""
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "sshd -T"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "trustedusercakeys"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "getent passwd {{ vault_ssh_ca_pilot_validation_user }}"
assert_file_contains "${ROLE_DIR}/tasks/main.yml" "no_log: true"
assert_file_contains "${ROLE_DIR}/handlers/main.yml" "Restart Vault SSH CA pilot sshd service"
assert_file_contains "${PLAYBOOK}" "Apply or validate Vault SSH CA pilot host trust"
assert_file_contains "${PLAYBOOK}" "vault_ssh_ca_pilot"
assert_file_contains "${DOCS}" "Vault SSH CA Pilot"
assert_file_contains "${DOCS}" "TrustedUserCAKeys"
assert_file_contains "${DOCS}" "ssh-client-signer"
assert_file_contains "${WIKI_DOCS}" "Vault SSH CA Pilot"
assert_file_contains "${RUN_TESTS}" "test_vault_ssh_ca_pilot_role.sh"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -f "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  children:
    vault_ssh_ca_pilot_hosts:
      hosts:
        localhost:
          ansible_connection: local
EOF
  ANSIBLE_CONFIG="${ANSIBLE_ROOT}/ansible.cfg" \
    ANSIBLE_ROLES_PATH="${ANSIBLE_ROOT}/roles" \
    ansible-playbook --syntax-check -i "${tmp_inventory}" "${PLAYBOOK}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
