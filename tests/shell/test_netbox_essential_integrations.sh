#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

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

role_defaults="${ANSIBLE_ROOT}/roles/netbox_essentials/defaults/main.yml"
role_tasks="${ANSIBLE_ROOT}/roles/netbox_essentials/tasks/main.yml"
role_template="${ANSIBLE_ROOT}/roles/netbox_essentials/templates/netbox-essentials.yml.j2"
profile="${ANSIBLE_ROOT}/profile-definitions/vm-netbox-service.yml"
metadata="${ANSIBLE_ROOT}/profile-definitions/vm-netbox-service.metadata.yml"
install_playbook="${ANSIBLE_ROOT}/playbooks/install.yml"
seed_script="${REPO_ROOT}/scripts/netbox_seed_local_network.py"
freeipa_create="${REPO_ROOT}/scripts/proxmox-create-freeipa-rocky-vm.sh"
freeipa_bootstrap="${REPO_ROOT}/scripts/bootstrap-freeipa-rocky.sh"
freeradius_configure="${REPO_ROOT}/scripts/configure-freeradius-freeipa.sh"

assert_file_contains "${role_defaults}" "netbox_essentials_default_enabled: false"
assert_file_contains "${role_defaults}" "pynetbox"
assert_file_contains "${role_defaults}" "netbox-agent"
assert_file_contains "${role_defaults}" "netbox-sync"
assert_file_contains "${role_defaults}" "netbox-tools"
assert_file_contains "${role_defaults}" "devicetype-library"
assert_file_contains "${role_defaults}" "Device-Type-Library-Import"
assert_file_contains "${role_defaults}" "netbox_essentials_default_device_type_import:"
assert_file_contains "${role_defaults}" "CyberPower"

assert_file_contains "${role_tasks}" "resolved_profile_netbox_essentials"
assert_file_contains "${role_tasks}" "netbox_essentials.repositories"
assert_file_contains "${role_tasks}" "device_type_import"
assert_file_contains "${role_tasks}" "netbox-essentials.yml"
assert_file_contains "${role_template}" "python_packages"
assert_file_contains "${role_template}" "repositories"
assert_file_contains "${role_template}" "device_type_import"

assert_file_contains "${profile}" "netbox_essentials:"
assert_file_contains "${profile}" "enabled: true"
assert_file_contains "${profile}" "https://github.com/netbox-community/devicetype-library.git"
assert_file_contains "${profile}" "Opengear"
assert_file_contains "${metadata}" "devicetype-library"
assert_file_contains "${install_playbook}" "netbox_essentials"

assert_file_contains "${seed_script}" "network_fabric_vlan_plan"
assert_file_contains "${seed_script}" "ipam/prefixes"
assert_file_contains "${seed_script}" "dcim/devices"
assert_file_contains "${freeipa_create}" "Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
assert_file_contains "${freeipa_bootstrap}" "freeipa-server"
assert_file_contains "${freeipa_bootstrap}" "network-admin"
assert_file_contains "${freeradius_configure}" "uid=radiusd,cn=sysaccounts"
assert_file_contains "${freeradius_configure}" "codex-admin"
assert_file_contains "${freeradius_configure}" "radtest"
assert_file_contains "${freeradius_configure}" "Access-Accept"

python3 -m py_compile "${seed_script}"
bash -n "${freeipa_create}" "${freeipa_bootstrap}" "${freeradius_configure}"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
