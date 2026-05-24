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
validator="${REPO_ROOT}/scripts/validate_identity_source.py"
renderer="${REPO_ROOT}/scripts/render_identity_sync_plan.py"
playbook="${ANSIBLE_ROOT}/playbooks/identity-source-validate.yml"
docs="${REPO_ROOT}/docs/IDENTITY-AAA.md"
wiki_docs="${REPO_ROOT}/docs/wiki/Identity-AAA.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT
validation_json="${temp_dir}/identity-source-validation.json"
sync_plan_json="${temp_dir}/identity-sync-plan.json"
invalid_output="${temp_dir}/identity-source-invalid.out"
invalid_fixture="${temp_dir}/invalid-identity-source.yml"

assert_file_contains "${source_file}" "identity_source_definition:"
assert_file_contains "${source_file}" "realm: RFC1918.HOST"
assert_file_contains "${source_file}" "codex-admin"
assert_file_contains "${source_file}" "linux-admin"
assert_file_contains "${source_file}" "network-readonly"
assert_file_contains "${source_file}" "pdu_rfc99_corectrl_ap7901"
assert_file_contains "${source_file}" "gmktek_nucbox_k10_stage5_candidate"
assert_file_contains "${source_file}" "vault_radius_client_pdu_rfc99_corectrl_ap7901_secret"
assert_file_contains "${source_file}" "freeipa_local_idrange"
assert_file_contains "${source_file}" "RFC1918.HOST_low_id_range"
assert_file_contains "${source_file}" "admin_sun99_forge_099070"
assert_file_contains "${source_file}" "vault_identity_m70_ipa_enrollment_secret"

assert_file_contains "${validator}" "class IdentitySourceValidationError"
assert_file_contains "${validator}" "validate_identity_source"
assert_file_contains "${renderer}" "render_identity_sync_plan"
assert_file_contains "${playbook}" "Validate identity source-of-truth definitions"
assert_file_contains "${docs}" "Identity Source Of Truth"
assert_file_contains "${wiki_docs}" "Identity Source Of Truth"
assert_file_contains "${run_tests}" "test_identity_source_of_truth.sh"

python3 -m py_compile "${validator}" "${renderer}"
python3 "${validator}" "${source_file}" --format json > "${validation_json}"
grep -Fq '"ok": true' "${validation_json}" || fail "identity source validation did not pass"
grep -Fq '"users": 2' "${validation_json}" || fail "identity source user count mismatch"
grep -Fq '"radius_clients": 1' "${validation_json}" || fail "identity source RADIUS client count mismatch"
grep -Fq '"host_enrollments": 2' "${validation_json}" || fail "identity source host enrollment count mismatch"

python3 "${renderer}" "${source_file}" --format json > "${sync_plan_json}"
grep -Fq '"freeipa_groups"' "${sync_plan_json}" || fail "sync plan missing FreeIPA groups"
grep -Fq '"freeipa_local_idrange"' "${sync_plan_json}" || fail "sync plan missing FreeIPA local ID range"
grep -Fq '"freeipa_users"' "${sync_plan_json}" || fail "sync plan missing FreeIPA users"
grep -Fq '"freeradius_clients"' "${sync_plan_json}" || fail "sync plan missing FreeRADIUS clients"
grep -Fq '"vault_radius_client_pdu_rfc99_corectrl_ap7901_secret"' "${sync_plan_json}" || fail "sync plan missing PDU secret var reference"
grep -Fq '"gmktek_nucbox_k10_stage5_candidate"' "${sync_plan_json}" || fail "sync plan missing K10 host enrollment"
grep -Fq '"admin_sun99_forge_099070"' "${sync_plan_json}" || fail "sync plan missing M70 host enrollment"

cat > "${invalid_fixture}" << 'EOF'
---
identity_source_definition:
  version: 1
  realm: RFC1918.HOST
  domain: rfc1918.host
  groups:
    - name: linux-admin
      gid: 200100
    - name: duplicate-gid
      gid: 200100
  users:
    - name: bad-user
      uid: 200100
      primary_group: missing-group
  radius_clients:
    - name: bad-radius
      ipaddr: 172.16.99.10
      shared_secret: plaintext-secret
EOF

if python3 "${validator}" "${invalid_fixture}" > "${invalid_output}" 2>&1; then
  fail "invalid identity source unexpectedly passed"
fi
grep -Fq "duplicate gid" "${invalid_output}" || fail "invalid fixture did not report duplicate gid"
grep -Fq "unknown primary_group" "${invalid_output}" || fail "invalid fixture did not report missing group"
grep -Fq "must use shared_secret_var" "${invalid_output}" || fail "invalid fixture did not reject plaintext secret"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="${temp_dir}/hosts.yml"
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${playbook}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "$0")"
