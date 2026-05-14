#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/defaults/main.yml" "bignetwork_edge_default_extracted_root:"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/defaults/main.yml" "bignetwork_edge_default_orbit_worlds:"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/defaults/main.yml" "bignetwork_edge_default_join_networks:"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/tasks/main.yml" "Install BigNetwork edge binary"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/tasks/main.yml" "Orbit BigNetwork vendor root set"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/tasks/main.yml" "Join BigNetwork managed networks"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/templates/bn.openrc.j2" "command=\"/usr/sbin/bn\""
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/templates/bn.sysvinit.j2" "BigNetwork virtualization service"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/templates/bignetwork-smoketest.sh.j2" "bn -q"
assert_file_contains "${ANSIBLE_ROOT}/roles/bignetwork_edge/templates/bignetwork-smoketest.sh.j2" "listnetworks"

assert_file_contains "${ANSIBLE_ROOT}/roles/devuan_netboot_assets/defaults/main.yml" "devuan_netboot_default_release:"
assert_file_contains "${ANSIBLE_ROOT}/roles/devuan_netboot_assets/tasks/main.yml" "Render Devuan BigNetwork smoke-test iPXE script"
assert_file_contains "${ANSIBLE_ROOT}/roles/devuan_netboot_assets/templates/devuan-bignetwork-smoketest.ipxe.j2" "debian-installer/amd64/linux"
assert_file_contains "${ANSIBLE_ROOT}/roles/devuan_netboot_assets/templates/devuan-bignetwork-smoketest.preseed.j2" "pkgsel/include"
assert_file_contains "${ANSIBLE_ROOT}/playbooks/devuan-bignetwork-smoketest-netboot.yml" "hosts: netboot_publishers"
assert_file_contains "${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md" "Devuan smoke-test first"
assert_file_contains "${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md" "Issue #114 Readiness Runbook"
assert_file_contains "${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md" "No live BigNetwork, RouterOS, NetBox, or Check_MK mutation while X12AGAIN off-host backup is active."
assert_file_contains "${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md" "Evidence bundle for issue #114"
assert_file_contains "${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md" "Live M70 Smoke-Test: 2026-05-14"
assert_file_contains "${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md" "bn-cli orbit 6aaf7fee5a 6aaf7fee5a"
assert_file_contains "${REPO_ROOT}/docs/BIGNETWORK-FMT2-SMOKETEST.md" "607daa3a01933028"
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/bignetwork.yml" "607daa3a01933028"
assert_file_contains "${REPO_ROOT}/docs/wiki/BigNetwork-FMT2-Smoke-Test.md" "Issue #114 Readiness Runbook"
assert_file_contains "${REPO_ROOT}/docs/wiki/BigNetwork-FMT2-Smoke-Test.md" "Evidence bundle for issue #114"
assert_file_contains "${REPO_ROOT}/docs/wiki/BigNetwork-FMT2-Smoke-Test.md" "Live M70 Smoke-Test: 2026-05-14"

(
  cd "${ANSIBLE_ROOT}"
  ansible-playbook -i inventories/examples/hosts.yml playbooks/devuan-bignetwork-smoketest-netboot.yml --syntax-check > /dev/null
)

printf 'PASS: %s\n' "$(basename "$0")"
