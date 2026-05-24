#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${ROOT_DIR}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
CLIENT_ROLE="${ANSIBLE_ROOT}/roles/ssh_client_policy"
BASTION_ROLE="${ANSIBLE_ROOT}/roles/ssh_bastion_host"
CLIENT_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/ssh-client-policy.yml"
BASTION_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/ssh-bastion-host.yml"
PLAN="${ROOT_DIR}/docs/superpowers/plans/2026-05-24-ssh-bastion-policy.md"
RUNBOOK="${ROOT_DIR}/docs/SSH-BASTION-POLICY-RUNBOOK.md"
WIKI_DOC="${ROOT_DIR}/docs/wiki/SSH-Bastion-Policy-Runbook.md"
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

assert_file_absent_pattern() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  if grep -Fq "${pattern}" "${file}"; then
    fail "unexpected ${pattern} in ${file}"
  fi
}

assert_file_contains "${CLIENT_ROLE}/defaults/main.yml" "ssh_client_policy_enabled: false"
assert_file_contains "${CLIENT_ROLE}/defaults/main.yml" "ssh_client_policy_apply: false"
assert_file_contains "${CLIENT_ROLE}/defaults/main.yml" "ssh_client_policy_control_path: \"%d/.ssh/controlmasters/%C\""
assert_file_contains "${CLIENT_ROLE}/defaults/main.yml" "ssh_client_policy_manage_bastion_routing: false"
assert_file_contains "${CLIENT_ROLE}/tasks/main.yml" "Refuse SSH client policy mutation without explicit apply gate"
assert_file_contains "${CLIENT_ROLE}/tasks/main.yml" "ssh_client_policy_apply | bool"
assert_file_contains "${CLIENT_ROLE}/tasks/main.yml" "ssh -G {{ ssh_client_policy_validation_target }}"
assert_file_contains "${CLIENT_ROLE}/templates/ssh-client-controlmaster.conf.j2" "ControlPath {{ ssh_client_policy_control_path }}"
assert_file_contains "${CLIENT_ROLE}/templates/ssh-client-bastion-routing.conf.j2" "ProxyJump none"
assert_file_contains "${CLIENT_ROLE}/templates/ssh-client-bastion-routing.conf.j2" "Host {{ ssh_client_policy_bastion_host }}"
assert_file_contains "${CLIENT_ROLE}/templates/ssh-client-bastion-routing.conf.j2" "ProxyJump {{ ssh_client_policy_bastion_user }}@{{ ssh_client_policy_bastion_host }}"
assert_file_absent_pattern "${CLIENT_ROLE}/defaults/main.yml" "/tmp/.cm"
assert_file_absent_pattern "${CLIENT_ROLE}/templates/ssh-client-controlmaster.conf.j2" "/tmp/.cm"

assert_file_contains "${BASTION_ROLE}/defaults/main.yml" "ssh_bastion_host_enabled: false"
assert_file_contains "${BASTION_ROLE}/defaults/main.yml" "ssh_bastion_host_apply: false"
assert_file_contains "${BASTION_ROLE}/defaults/main.yml" "ssh_bastion_host_authorized_keys_command: /usr/bin/sss_ssh_authorizedkeys"
assert_file_contains "${BASTION_ROLE}/tasks/main.yml" "Refuse SSH bastion host mutation without explicit apply gate"
assert_file_contains "${BASTION_ROLE}/tasks/main.yml" "sshd -t -f {{ ssh_bastion_host_sshd_config_path }}"
assert_file_contains "${BASTION_ROLE}/handlers/main.yml" "ansible.builtin.service:"
assert_file_contains "${BASTION_ROLE}/templates/sshd-bastion.conf.j2" "AllowTcpForwarding"
assert_file_contains "${BASTION_ROLE}/templates/sshd-bastion.conf.j2" "AuthorizedKeysCommand"
assert_file_absent_pattern "${BASTION_ROLE}/tasks/main.yml" "systemctl"
assert_file_absent_pattern "${BASTION_ROLE}/handlers/main.yml" "systemctl"

assert_file_contains "${CLIENT_PLAYBOOK}" "Apply or validate centralized SSH client policy"
assert_file_contains "${CLIENT_PLAYBOOK}" "ssh_client_policy"
assert_file_contains "${BASTION_PLAYBOOK}" "Apply or validate SSH bastion host policy"
assert_file_contains "${BASTION_PLAYBOOK}" "ssh_bastion_host"

assert_file_contains "${PLAN}" "SSH Bastion Policy Implementation Plan"
assert_file_contains "${PLAN}" "OpenSSH uses first-value-wins precedence"
assert_file_contains "${RUNBOOK}" "Required Backout Commands"
assert_file_contains "${RUNBOOK}" "ssh -G root@agx-rfc99-bunnydev.rfc1918.host"
assert_file_contains "${RUNBOOK}" "sudo rm -f /etc/ssh/ssh_config.d/20-yukon-controlmaster.conf"
assert_file_contains "${RUNBOOK}" "sudo rm -f /etc/ssh/sshd_config.d/30-yukon-bastion.conf"
assert_file_contains "${RUNBOOK}" "ssh -o ProxyJump=none -o ControlMaster=no -o ControlPath=none"
assert_file_contains "${RUNBOOK}" "does not require systemd-specific commands"
assert_file_contains "${WIKI_DOC}" "SSH Bastion Policy Runbook"
assert_file_contains "${RUN_TESTS}" "test_ssh_bastion_policy.sh"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -f "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  children:
    ssh_client_policy_targets:
      hosts:
        localhost:
          ansible_connection: local
    ssh_bastion_hosts:
      hosts:
        localhost:
          ansible_connection: local
EOF
  ANSIBLE_CONFIG="${ANSIBLE_ROOT}/ansible.cfg" \
    ANSIBLE_ROLES_PATH="${ANSIBLE_ROOT}/roles" \
    ansible-playbook --syntax-check -i "${tmp_inventory}" "${CLIENT_PLAYBOOK}" > /dev/null
  ANSIBLE_CONFIG="${ANSIBLE_ROOT}/ansible.cfg" \
    ANSIBLE_ROLES_PATH="${ANSIBLE_ROOT}/roles" \
    ansible-playbook --syntax-check -i "${tmp_inventory}" "${BASTION_PLAYBOOK}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
