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

inventory="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
hasslehoff_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/hasslehoff.yml"
network_fabric="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/network_fabric.yml"
vault_file="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/vault.yml"
playbook="${ANSIBLE_ROOT}/playbooks/local-network-inventory.yml"
proxmox_api_playbook="${ANSIBLE_ROOT}/playbooks/proxmox-api-validate.yml"
netbox_api_playbook="${ANSIBLE_ROOT}/playbooks/netbox-api-validate.yml"

assert_file_contains "${inventory}" "hasslehoff:"
assert_file_contains "${inventory}" "netbox_jail:"
assert_file_contains "${inventory}" "netbox_api_url: https://172.16.99.62"
assert_file_contains "${inventory}" "proxmox_api_token_secret: \"{{ vault_hasslehoff_proxmox_api_token_secret }}\""
assert_file_contains "${inventory}" "sw_mgmt_mkcrs354:"
assert_file_contains "${inventory}" "rtr_mgmt_ccr2004:"
assert_file_contains "${inventory}" "sw_mgmt_css326:"

assert_file_contains "${hasslehoff_vars}" "local_inventory_observed:"
assert_file_contains "${hasslehoff_vars}" "proxmox_observed_vms:"
assert_file_contains "${hasslehoff_vars}" "gw-rfc99-vyos-routeprime"
assert_file_contains "${hasslehoff_vars}" "FreeBSD jail host for NetBox"

assert_file_contains "${network_fabric}" "hasslehoff-bond0"
assert_file_contains "${network_fabric}" "netbox_jail"
assert_file_contains "${network_fabric}" "parent_host: ctbsd_rfc99_jailerprime_099099"
assert_file_contains "${network_fabric}" "api_url: https://172.16.99.62"
assert_file_contains "${network_fabric}" "llm-rag-service-control"
assert_file_contains "${network_fabric}" "llm-rag-inference-data"

head -n 1 "${vault_file}" | grep -q '^\$ANSIBLE_VAULT;' ||
  fail "local-network vault is not encrypted"

assert_file_contains "${playbook}" "Capture local network inventory snapshots"
assert_file_contains "${playbook}" "pvesh"
assert_file_contains "${playbook}" "local_network_snapshot_root"

assert_file_contains "${proxmox_api_playbook}" "Validate Proxmox API access"
assert_file_contains "${proxmox_api_playbook}" "PVEAPIToken={{ proxmox_api_token_id }}={{ proxmox_api_token_secret }}"
assert_file_contains "${proxmox_api_playbook}" "no_log: true"

assert_file_contains "${netbox_api_playbook}" "Validate NetBox API reachability"
assert_file_contains "${netbox_api_playbook}" "Token {{ netbox_api_token }}"
assert_file_contains "${netbox_api_playbook}" "no_log: true"

if command -v ansible-playbook >/dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -f "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" <<'EOF'
---
all:
  children:
    proxmox_hypervisors:
      hosts:
        syntax_hasslehoff:
          ansible_connection: local
    netbox_services:
      hosts:
        syntax_netbox:
          ansible_connection: local
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${playbook}" >/dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${proxmox_api_playbook}" >/dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${netbox_api_playbook}" >/dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
