#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

assert_file() {
  local path="$1"
  if [[ ! -f "${ROOT_DIR}/${path}" ]]; then
    echo "missing file: ${path}" >&2
    exit 1
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${ROOT_DIR}/${path}"; then
    echo "missing '${needle}' in ${path}" >&2
    exit 1
  fi
}

assert_file "${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.yml"
assert_file "${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.metadata.yml"
assert_file "${ANSIBLE_ROOT}/profile-package-lists/stage5-metal-forge-automation-admin.packages"
assert_file "${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml"
assert_file "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
assert_file "${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/dns_hetzner_cloud.yml"
assert_file "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml"
assert_file "${ANSIBLE_ROOT}/inventories/local-network/host_vars/gw_rfc99_mkccr2004_16g.yml"
assert_file "docs/M70-FORGE-AUTOMATION-ADMIN.md"
assert_file "docs/wiki/M70-Forge-Automation-Admin.md"

assert_contains "${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.yml" "profile_id: metal-forge-automation-admin"
assert_contains "${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.yml" "stage5_profile: metal-forge-automation-admin"
assert_contains "${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.yml" "automation_admin:"
assert_contains "${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.yml" "x12again_sol_wrapper_path: /root/.ssh/codex.d/ipmi.d/ipmi-prinzessin"
assert_contains "${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.yml" "forge_memory_spool_path: /var/lib/forge-memory/spool"
assert_contains "${ANSIBLE_ROOT}/profile-definitions/metal-forge-automation-admin.metadata.yml" "id: metal-forge-automation-admin"

assert_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-metal-forge-automation-admin.packages" "app-admin/ansible"
assert_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-metal-forge-automation-admin.packages" "dev-vcs/git"
assert_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-metal-forge-automation-admin.packages" "net-analyzer/nmap"
assert_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-metal-forge-automation-admin.packages" "net-analyzer/tcpdump"
assert_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-metal-forge-automation-admin.packages" "sys-apps/ipmitool"
assert_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-metal-forge-automation-admin.packages" "sys-fs/zfs"

assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "automation_admin_hosts:"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "admin_sun99_forge_099070:"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "ansible_host: 172.16.99.70"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "fqdn: admin-sun99-forge-099070.rfc1918.host"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "stage5_profile: metal-forge-automation-admin"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "primary_nic_mac: \"00:07:32:78:65:C6\""
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "connected_switch_port: ge14"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "pdu_outlet: \"4\""
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "observed_memory_gib: 32"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "serial_console_current_tty: /dev/ttyUSB3"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "automation_admin_migration_source: x12again"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_protocol_flow: pxe-to-ipxe"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_bootfile_name: m70-forge-ipxe.efi"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_interface_name: netboot0"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/hosts.yml" "netboot_operational_bootstrap: local-esp-ipxe-chainloader"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/dns_hetzner_cloud.yml" "admin-sun99-forge-099070.rfc1918.host"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/dns_hetzner_cloud.yml" "admin-sun99-forge.rfc1918.host"

assert_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "dest: m70-forge-ipxe.efi"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "src: /opt/gentoo-netboot/path-b/m70-forge-ipxe-172.16.99.88-ipxe.efi"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "forge-automation-admin:"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "bootdev=netboot0"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "ifname=netboot0:00:07:32:78:65:c6"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/netboot_publishers.yml" "ip=172.16.99.70::172.16.99.1:255.255.255.0:admin-sun99-forge-099070:netboot0:none"

assert_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/gw_rfc99_mkccr2004_16g.yml" "admin-sun99-forge-099070.rfc1918.host"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/gw_rfc99_mkccr2004_16g.yml" "admin-sun99-forge.rfc1918.host"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/gw_rfc99_mkccr2004_16g.yml" "m70-forge-pxe-bootfile"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/gw_rfc99_mkccr2004_16g.yml" "m70-forge-ipxe.efi"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/gw_rfc99_mkccr2004_16g.yml" "00:07:32:78:65:C6"
assert_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/gw_rfc99_mkccr2004_16g.yml" "172.16.99.70"
assert_contains "${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml" "metal-forge-automation-admin:"
assert_contains "${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml" "forge-control-plane"

assert_contains "tests/shell/run-tests.sh" "test_m70_forge_admin_provisioning.sh"

echo "M70 Forge automation-admin provisioning checks passed."
