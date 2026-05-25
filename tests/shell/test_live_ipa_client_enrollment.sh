#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2
  ! grep -q -- "${pattern}" "${file}"
}

inventory="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
host_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/gmktek_nucbox_k10_stage5_candidate.yml"
apply_playbook="${ANSIBLE_ROOT}/playbooks/ipa-client-live-apply.yml"
validate_playbook="${ANSIBLE_ROOT}/playbooks/ipa-client-live-validate.yml"
profile_definition="${ANSIBLE_ROOT}/profile-definitions/aaa-domain-client.yml"
sssd_template="${ANSIBLE_ROOT}/roles/ipa_client/templates/sssd.conf.j2"
netboot_manifest="${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml"
identity_doc="${REPO_ROOT}/docs/IDENTITY-AAA.md"
roadmap_doc="${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"

assert_file_contains "${inventory}" 'aaa_domain_clients:'
assert_file_contains "${inventory}" 'gmktek_nucbox_k10_stage5_candidate:'
test -f "${host_vars}"
assert_file_contains "${host_vars}" 'ansible_host: 172.16.99.156'
assert_file_contains "${host_vars}" 'profile-definitions/aaa-domain-client.yml'
assert_file_contains "${host_vars}" 'profile-definitions/secure-firstboot-enrollment.yml'
assert_file_contains "${host_vars}" 'freeipa_client_fqdn: gmktek-k10-stage5.rfc1918.host'
assert_file_contains "${host_vars}" 'freeipa_client_controller_inventory_host: svc_identity_ipa01'

test -f "${apply_playbook}"
assert_file_contains "${apply_playbook}" 'hosts: aaa_domain_clients'
assert_file_contains "${apply_playbook}" 'ipa_client_live_apply'
assert_file_contains "${apply_playbook}" 'ipa-getkeytab'
assert_file_contains "${apply_playbook}" 'no_log: true'
assert_file_contains "${apply_playbook}" 'check_mode: false'
assert_file_contains "${apply_playbook}" 'delegate_to: "{{ ipa_client_live_controller_inventory_host }}"'
assert_file_contains "${apply_playbook}" 'owner: sssd'
assert_file_contains "${apply_playbook}" 'group: sssd'
assert_file_contains "${apply_playbook}" '--buildpkg=y'
assert_file_contains "${apply_playbook}" 'AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys'
assert_file_contains "${apply_playbook}" 'sys-auth/sssd samba'
assert_file_contains "${apply_playbook}" 'net-fs/samba winbind'
assert_file_not_contains "${apply_playbook}" 'config_file_version = 2'

assert_file_contains "${profile_definition}" 'sys-auth/sssd samba'
assert_file_contains "${profile_definition}" 'net-fs/samba winbind'
assert_file_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-domain-client.packages" 'net-fs/samba'
assert_file_not_contains "${sssd_template}" 'config_file_version = 2'
assert_file_contains "${netboot_manifest}" 'profile-definitions/aaa-domain-client.yml'
assert_file_contains "${netboot_manifest}" 'profile-definitions/secure-firstboot-enrollment.yml'
assert_file_contains "${netboot_manifest}" 'profile-package-lists/stage5-domain-client.packages'
assert_file_contains "${netboot_manifest}" 'profile-package-lists/stage5-secure-firstboot-enrollment.packages'
assert_file_contains "${netboot_manifest}" 'reboot_durable_aaa_gate: blocked on disk install or secure first-boot age-encrypted FreeIPA OTP bundle apply'
assert_file_contains "${identity_doc}" 'Secure First-Boot Enrollment'
assert_file_contains "${identity_doc}" 'ipa host-add --random'
assert_file_contains "${roadmap_doc}" '| `AAA-007` | active |'

test -f "${validate_playbook}"
assert_file_contains "${validate_playbook}" 'sssctl'
assert_file_contains "${validate_playbook}" 'domain-status'
assert_file_contains "${validate_playbook}" 'failed_when: false'
assert_file_contains "${validate_playbook}" 'Unable to connect to system bus'
assert_file_contains "${validate_playbook}" '/usr/lib64/sssd/libsss_ipa.so'
assert_file_contains "${validate_playbook}" 'config-check'
assert_file_contains "${validate_playbook}" 'getent'
assert_file_contains "${validate_playbook}" 'passwd'
assert_file_contains "${validate_playbook}" 'codex-admin'
assert_file_contains "${validate_playbook}" 'sss_ssh_authorizedkeys'
assert_file_contains "${validate_playbook}" 'su'
assert_file_contains "${validate_playbook}" '/bin/true'

printf 'PASS: %s\n' "$(basename "$0")"
