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

assert_not_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" != *"${needle}"* ]] || fail "unexpected secret leak: ${needle}"
}

source_file="${ANSIBLE_ROOT}/identity-source-definitions/local-rfc1918.yml"
apply_script="${REPO_ROOT}/scripts/apply_identity_sync_plan.py"
playbook="${ANSIBLE_ROOT}/playbooks/identity-source-apply.yml"
docs="${REPO_ROOT}/docs/IDENTITY-AAA.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${apply_script}" "apply_identity_sync_plan"
assert_file_contains "${apply_script}" "IDENTITY_SYNC_APPLY=1"
assert_file_contains "${playbook}" "Apply identity source-of-truth definitions"
assert_file_contains "${docs}" "Gated Apply"
assert_file_contains "${run_tests}" "test_identity_apply_plan.sh"

python3 -m py_compile "${apply_script}"

leak_secret='super-secret-value-must-not-print'
dry_run="$(
  vault_radius_client_pdu_rfc99_corectrl_ap7901_secret="${leak_secret}" \
    python3 "${apply_script}" "${source_file}" --format json
)"
grep -Fq '"dry_run": true' <<< "${dry_run}" || fail "dry run did not default to dry_run=true"
grep -Fq '"applied": false' <<< "${dry_run}" || fail "dry run unexpectedly applied"
grep -Fq '"freeipa"' <<< "${dry_run}" || fail "dry run missing FreeIPA plan"
grep -Fq '"freeradius"' <<< "${dry_run}" || fail "dry run missing FreeRADIUS plan"
grep -Fq '"vault_radius_client_pdu_rfc99_corectrl_ap7901_secret"' <<< "${dry_run}" ||
  fail "dry run missing RADIUS secret variable reference"
assert_not_contains "${dry_run}" "${leak_secret}"

if python3 "${apply_script}" "${source_file}" --apply --provider freeipa > /tmp/identity-apply-no-global.out 2>&1; then
  fail "apply without global mutation gate unexpectedly passed"
fi
grep -Fq 'IDENTITY_SYNC_APPLY=1 is required' /tmp/identity-apply-no-global.out ||
  fail "missing global apply gate error"

if IDENTITY_SYNC_APPLY=1 \
  python3 "${apply_script}" "${source_file}" --apply --provider freeradius \
  --freeradius-output /tmp/identity-radius-no-provider.conf \
  > /tmp/identity-apply-no-provider.out 2>&1; then
  fail "FreeRADIUS apply without provider gate unexpectedly passed"
fi
grep -Fq 'IDENTITY_SYNC_APPLY_FREERADIUS=1 is required' /tmp/identity-apply-no-provider.out ||
  fail "missing FreeRADIUS provider gate error"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
radius_secret='radius-secret-file-only'
radius_output="${tmpdir}/clients.conf"
audit_log="${tmpdir}/identity-sync-audit.jsonl"
radius_stdout="$(
  IDENTITY_SYNC_APPLY=1 \
    IDENTITY_SYNC_APPLY_FREERADIUS=1 \
    vault_radius_client_pdu_rfc99_corectrl_ap7901_secret="${radius_secret}" \
    python3 "${apply_script}" "${source_file}" \
    --apply \
    --provider freeradius \
    --freeradius-output "${radius_output}" \
    --audit-log "${audit_log}" \
    --format json
)"
grep -Fq '"applied": true' <<< "${radius_stdout}" || fail "FreeRADIUS apply did not report applied"
grep -Fq 'pdu-rfc99-corectrl-099241' "${radius_output}" || fail "FreeRADIUS output missing client shortname"
grep -Fq "${radius_secret}" "${radius_output}" || fail "FreeRADIUS output missing resolved secret"
assert_not_contains "${radius_stdout}" "${radius_secret}"
assert_not_contains "$(cat "${audit_log}")" "${radius_secret}"

fake_ipa="${tmpdir}/fake-ipa"
fake_log="${tmpdir}/fake-ipa.log"
cat > "${fake_ipa}" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_IPA_LOG}"
case "$1" in
  group-show|user-show|host-show|hostgroup-show)
    exit 1
    ;;
esac
exit 0
EOF
chmod +x "${fake_ipa}"

freeipa_stdout="$(
  IDENTITY_SYNC_APPLY=1 \
    IDENTITY_SYNC_APPLY_FREEIPA=1 \
    FAKE_IPA_LOG="${fake_log}" \
    vault_identity_codex_admin_ssh_public_keys='ssh-ed25519 AAAATEST codex-admin' \
    python3 "${apply_script}" "${source_file}" \
    --apply \
    --provider freeipa \
    --freeipa-command "${fake_ipa}" \
    --format json
)"
grep -Fq '"applied": true' <<< "${freeipa_stdout}" || fail "FreeIPA apply did not report applied"
grep -Fq 'group-add linux-admin' "${fake_log}" || fail "FreeIPA fake log missing group-add"
grep -Fq 'user-add codex-admin' "${fake_log}" || fail "FreeIPA fake log missing user-add"
grep -Fq 'group-add-member ci-builder' "${fake_log}" || fail "FreeIPA fake log missing group membership"
grep -Fq 'host-add gmktek-k10-stage5.rfc1918.host' "${fake_log}" || fail "FreeIPA fake log missing host-add"
assert_not_contains "${freeipa_stdout}" 'ssh-ed25519 AAAATEST'

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="${tmpdir}/hosts.yml"
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
