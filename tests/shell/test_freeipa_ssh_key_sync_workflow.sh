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
renderer="${REPO_ROOT}/scripts/render_freeipa_ssh_sync_checks.py"
playbook="${ANSIBLE_ROOT}/playbooks/freeipa-ssh-key-sync.yml"
docs="${REPO_ROOT}/docs/IDENTITY-AAA.md"
wiki_docs="${REPO_ROOT}/docs/wiki/Identity-AAA.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${renderer}" "render_freeipa_ssh_sync_checks"
assert_file_contains "${renderer}" "sss_ssh_authorizedkeys"
assert_file_contains "${renderer}" "hbactest"
assert_file_contains "${playbook}" "Sync FreeIPA SSH keys and access metadata"
assert_file_contains "${playbook}" "identity_freeipa_ssh_sync_enabled"
assert_file_contains "${playbook}" "IDENTITY_SYNC_APPLY_FREEIPA"
assert_file_contains "${playbook}" "render_freeipa_ssh_sync_checks.py"
assert_file_contains "${playbook}" "Run live FreeIPA controller validation checks"
assert_file_contains "${docs}" "FreeIPA SSH Key Sync Workflow"
assert_file_contains "${wiki_docs}" "FreeIPA SSH Key Sync Workflow"
assert_file_contains "${run_tests}" "test_freeipa_ssh_key_sync_workflow.sh"

python3 -m py_compile "${renderer}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
checks_json="${tmpdir}/freeipa-ssh-sync-checks.json"
python3 "${renderer}" "${source_file}" --format json > "${checks_json}"

grep -Fq '"requires_vars"' "${checks_json}" || fail "validation plan missing required vault vars"
grep -Fq 'vault_identity_codex_admin_ssh_public_keys' "${checks_json}" ||
  fail "validation plan missing codex-admin SSH key vault var"
grep -Fq '"freeipa_controller_checks"' "${checks_json}" || fail "validation plan missing controller checks"
grep -Fq '"linux_client_checks"' "${checks_json}" || fail "validation plan missing Linux client checks"
grep -Fq 'sss_ssh_authorizedkeys' "${checks_json}" || fail "validation plan missing SSSD SSH lookup"
grep -Fq 'hbactest' "${checks_json}" || fail "validation plan missing FreeIPA HBAC checks"
grep -Fq 'codex-admin' "${checks_json}" || fail "validation plan missing codex-admin"
grep -Fq 'gmktek-k10-stage5.rfc1918.host' "${checks_json}" || fail "validation plan missing K10 host"
grep -Fq 'admin-sun99-forge-099070.rfc1918.host' "${checks_json}" ||
  fail "validation plan missing M70 Forge host"

python3 - "${checks_json}" << 'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
if not data["freeipa_controller_checks"]:
    raise SystemExit("missing controller checks")
if not data["linux_client_checks"]:
    raise SystemExit("missing client checks")
for check in data["freeipa_controller_checks"]:
    if not isinstance(check.get("argv"), list):
        raise SystemExit(f"controller check lacks argv list: {check}")
for user in data["linux_client_checks"]:
    for command in user["commands"]:
        if not isinstance(command.get("argv"), list):
            raise SystemExit(f"client check lacks argv list: {command}")
rendered = json.dumps(data)
for forbidden in ("private_key", "shared_secret", "password"):
    if forbidden in rendered:
        raise SystemExit(f"validation plan leaked secret-shaped field: {forbidden}")
PY

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="${tmpdir}/hosts.yml"
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  children:
    identity_controllers:
      hosts:
        localhost:
          ansible_connection: local
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${playbook}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "$0")"
