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

identity_validate="${ANSIBLE_ROOT}/playbooks/identity-controller-validate.yml"
netbox_seed="${ANSIBLE_ROOT}/playbooks/netbox-local-fabric-seed.yml"
intake_doc="${REPO_ROOT}/docs/INFRASTRUCTURE-INVENTORY-INTAKE.md"
wiki_intake_doc="${REPO_ROOT}/docs/wiki/Infrastructure-Inventory-Intake.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${identity_validate}" "Validate identity controller services"
assert_file_contains "${identity_validate}" "identity_controller_required_services"
assert_file_contains "${identity_validate}" "radius_validation_enabled"
assert_file_contains "${identity_validate}" "no_log: true"

assert_file_contains "${netbox_seed}" "Seed NetBox from local network fabric"
assert_file_contains "${netbox_seed}" "scripts/netbox_seed_local_network.py"
assert_file_contains "${netbox_seed}" "netbox_seed_apply"
assert_file_contains "${netbox_seed}" "no_log: true"

assert_file_contains "${intake_doc}" "Required Intake Data"
assert_file_contains "${intake_doc}" "Datacenter"
assert_file_contains "${intake_doc}" "Cluster"
assert_file_contains "${intake_doc}" "IPAM"
assert_file_contains "${wiki_intake_doc}" "Required Intake Data"
assert_file_contains "${run_tests}" "test_operational_validation_playbooks.sh"

if command -v ansible-playbook >/dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -f "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" <<'EOF'
---
all:
  children:
    identity_controllers:
      hosts:
        syntax_identity:
          ansible_connection: local
          identity_realm: RFC1918.HOST
    netbox_services:
      hosts:
        syntax_netbox:
          ansible_connection: local
          netbox_api_url: http://127.0.0.1
          netbox_api_token: syntax-token
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${identity_validate}" >/dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${netbox_seed}" >/dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
