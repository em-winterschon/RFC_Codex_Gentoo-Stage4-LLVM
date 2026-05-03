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

validator="${REPO_ROOT}/scripts/validate_netbox_inventory_intake.py"
apply_script="${REPO_ROOT}/scripts/netbox_apply_inventory_intake.py"
example="${ANSIBLE_ROOT}/inventory-intake/sites/local-rfc1918-lab.yml"
rfc99="${ANSIBLE_ROOT}/inventory-intake/sites/rfc99.yml"
sun99="${ANSIBLE_ROOT}/inventory-intake/sites/sun99.yml"
yks99="${ANSIBLE_ROOT}/inventory-intake/sites/yks99.yml"
fmt2="${ANSIBLE_ROOT}/inventory-intake/sites/fmt2.yml"
readme="${ANSIBLE_ROOT}/inventory-intake/README.md"
playbook="${ANSIBLE_ROOT}/playbooks/netbox-inventory-intake-validate.yml"
apply_playbook="${ANSIBLE_ROOT}/playbooks/netbox-inventory-intake-apply.yml"
docs="${REPO_ROOT}/docs/INFRASTRUCTURE-INVENTORY-INTAKE.md"
wiki_docs="${REPO_ROOT}/docs/wiki/Infrastructure-Inventory-Intake.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${validator}" "class IntakeValidationError"
assert_file_contains "${validator}" "validate_sites"
assert_file_contains "${validator}" "validate_prefixes"
assert_file_contains "${validator}" "validate_devices"
assert_file_contains "${validator}" "validate_service_vips"

assert_file_contains "${apply_script}" "apply_inventory"
assert_file_contains "${apply_script}" "dry_run"
assert_file_contains "${apply_script}" "dcim/sites"
assert_file_contains "${apply_script}" "virtualization/clusters"
assert_file_contains "${apply_script}" "ipam/ip-addresses"

assert_file_contains "${example}" "inventory_intake_version: 1"
assert_file_contains "${example}" "datacenters:"
assert_file_contains "${example}" "clusters:"
assert_file_contains "${example}" "devices:"
assert_file_contains "${example}" "service_vips:"
assert_file_contains "${rfc99}" "gw_rfc99_mkcrs309"
assert_file_contains "${sun99}" "nanonet-private-cloud"
assert_file_contains "${yks99}" "172.28.0.0/16"
assert_file_contains "${fmt2}" "66.160.146.148/32"

assert_file_contains "${readme}" "inventory-intake"
assert_file_contains "${playbook}" "Validate NetBox inventory intake definitions"
assert_file_contains "${playbook}" "validate_netbox_inventory_intake.py"
assert_file_contains "${apply_playbook}" "Apply NetBox inventory intake definitions"
assert_file_contains "${apply_playbook}" "netbox_apply_inventory_intake.py"
assert_file_contains "${apply_playbook}" "netbox_inventory_apply"
assert_file_contains "${docs}" "Structured Intake Files"
assert_file_contains "${docs}" "netbox-inventory-intake-apply.yml"
assert_file_contains "${wiki_docs}" "Structured Intake Files"
assert_file_contains "${run_tests}" "test_netbox_inventory_intake.sh"

python3 -m py_compile "${validator}"
python3 -m py_compile "${apply_script}"
python3 "${validator}" "${example}" --format json >/dev/null
python3 "${validator}" "${ANSIBLE_ROOT}/inventory-intake/sites" --format json >/tmp/netbox-intake-all-sites-validation.json
grep -Fq '"devices": 11' /tmp/netbox-intake-all-sites-validation.json || fail "all-sites validation did not include expected device count"
python3 "${apply_script}" "${example}" --api-url http://127.0.0.1 --token fake-token --format json >/tmp/netbox-intake-apply-plan.json
grep -Fq '"dry_run": true' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not default to dry-run"
grep -Fq 'dcim/sites:local-rfc1918-lab' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include site"
grep -Fq 'virtualization/clusters:hasslehoff-proxmox' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include cluster"
grep -Fq 'ipam/ip-addresses:10.9.8.20/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include rsyslog VIP"

invalid_fixture="$(mktemp --suffix=.yml)"
trap 'rm -f "${invalid_fixture}"' EXIT
cat > "${invalid_fixture}" <<'EOF'
---
inventory_intake_version: 1
datacenters:
  - name: broken-site
    slug: broken-site
    timezone: UTC
    management_prefixes:
      - 10.99.0.0/24
devices:
  - name: bad-device
    site: missing-site
    role: access-switch
    management_ip: 10.99.0.5
prefixes:
  - prefix: not-a-prefix
    site: broken-site
EOF

if python3 "${validator}" "${invalid_fixture}" >/tmp/netbox-intake-invalid.out 2>&1; then
  fail "invalid intake fixture unexpectedly passed"
fi
grep -Fq "missing-site" /tmp/netbox-intake-invalid.out || fail "invalid fixture did not report missing site"
grep -Fq "not-a-prefix" /tmp/netbox-intake-invalid.out || fail "invalid fixture did not report invalid prefix"

if command -v ansible-playbook >/dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -f "${invalid_fixture}" "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" <<'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${playbook}" >/dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${apply_playbook}" >/dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
