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
  local file=$1
  local pattern=$2
  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

source_file="${ANSIBLE_ROOT}/identity-source-definitions/local-rfc1918.yml"
inventory="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
validate_playbook="${ANSIBLE_ROOT}/playbooks/forge-floating-home-validate.yml"
apply_playbook="${ANSIBLE_ROOT}/playbooks/forge-floating-home-mount-apply.yml"
docs="${REPO_ROOT}/docs/FREEIPA-FORGE-WORKERS-QNAP-HOMES.md"
admin_host_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/admin_sun99_forge_099070.yml"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

for forge_user in forge1 forge2 forge3 forge4 forge5 forge6; do
  assert_file_contains "${source_file}" "name: ${forge_user}"
  assert_file_contains "${source_file}" "home_directory: /home/${forge_user}"
  assert_file_contains "${source_file}" "vault_identity_${forge_user}_ssh_public_keys"
  assert_file_contains "${source_file}" "/share/CACHEDEV2_DATA/rfc1918-floating-homes/${forge_user}"
done
for operator_user in eva robin verwalterin backups codex-admin ltcol-forge toor; do
  assert_file_contains "${source_file}" "name: ${operator_user}"
  assert_file_contains "${source_file}" "home_directory: /home/${operator_user}"
  assert_file_contains "${source_file}" "/share/CACHEDEV2_DATA/rfc1918-floating-homes/${operator_user}"
done

assert_file_contains "${validate_playbook}" "forge-floating-home-validate"
assert_file_contains "${apply_playbook}" "forge-floating-home-mount-apply"
assert_file_contains "${apply_playbook}" "BEGIN CODEX FORGE QNAP FLOATING HOMES"
assert_file_contains "${apply_playbook}" "net-fs/nfs-utils"
assert_file_contains "${apply_playbook}" "state: mounted"
assert_file_contains "${apply_playbook}" "vers=4.2"
assert_file_contains "${apply_playbook}" "forge_floating_home_local_groups"
assert_file_contains "${apply_playbook}" "name: whee"
assert_file_contains "${validate_playbook}" "forge_floating_home_users"
assert_file_contains "${validate_playbook}" "sss_ssh_authorizedkeys"
assert_file_contains "${validate_playbook}" "findmnt"
assert_file_contains "${validate_playbook}" "su"
assert_file_contains "${validate_playbook}" "forge-floating-home-write-test"
assert_file_contains "${validate_playbook}" "forge_floating_home_local_group_expectations"
assert_file_contains "${docs}" "SUN99 FreeIPA + QNAP Floating Homes"
assert_file_contains "${docs}" "QNAP NFSv4.2"
assert_file_contains "${docs}" "protocol-not-supported"
assert_file_contains "${docs}" "FreeIPA SSH public-key attributes"
assert_file_contains "${admin_host_vars}" "profile_nfs_storage_client"
assert_file_contains "${admin_host_vars}" "172.16.254.28:/rfc1918-floating-homes/forge1"
assert_file_contains "${admin_host_vars}" "172.16.254.28:/rfc1918-floating-homes/ltcol-forge"
assert_file_contains "${admin_host_vars}" "172.16.254.28:/rfc1918-floating-homes/toor"
assert_file_contains "${admin_host_vars}" "vers=4.2"
assert_file_contains "${admin_host_vars}" "nconnect=4"
assert_file_contains "${inventory}" "obs_sun99_kibana_099067:"
assert_file_contains "${inventory}" "boot_sun99_netboot_099088:"
assert_file_contains "${run_tests}" "test_forge_floating_home_contract.sh"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
  cat > "${tmpdir}/hosts.yml" << 'YAML'
---
all:
  hosts:
    localhost:
      ansible_connection: local
YAML
  ansible-playbook --syntax-check -i "${tmpdir}/hosts.yml" "${validate_playbook}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "$0")"
