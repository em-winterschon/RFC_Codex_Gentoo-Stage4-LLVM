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
  grep -Fq -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

role_dir="${ANSIBLE_ROOT}/roles/freeipa_server_certificate"
defaults="${role_dir}/defaults/main.yml"
tasks="${role_dir}/tasks/main.yml"
playbook="${ANSIBLE_ROOT}/playbooks/freeipa-server-cert-migration.yml"
matrix="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/service_tls_certificates.yml"
vault_docs="${REPO_ROOT}/docs/ANSIBLE-VAULT.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

for path in "${defaults}" "${tasks}" "${playbook}" "${matrix}" "${vault_docs}"; do
  [[ -f "${path}" ]] || fail "missing file ${path}"
done

assert_file_contains "${defaults}" "freeipa_server_certificate_enabled: false"
assert_file_contains "${defaults}" "freeipa_server_certificate_apply: false"
assert_file_contains "${defaults}" "freeipa_server_certificate_install_kdc: false"
assert_file_contains "${tasks}" "Refuse FreeIPA server certificate migration without explicit apply gate"
assert_file_contains "${tasks}" "freeipa_server_certificate_apply | bool"
assert_file_contains "${tasks}" "freeipa_server_certificate_directory_manager_password"
assert_file_contains "${tasks}" "no_log: true"
assert_file_contains "${tasks}" "ipa-cacert-manage"
assert_file_contains "${tasks}" "ipa-certupdate"
assert_file_contains "${tasks}" "ipa-server-certinstall"
assert_file_contains "${tasks}" "ipactl"
assert_file_contains "${tasks}" "base64 -d"
assert_file_contains "${tasks}" "timeout 20 openssl s_client"
assert_file_contains "${playbook}" "freeipa_server_certificate_target_hosts"
assert_file_contains "${playbook}" "freeipa_server_certificate"
assert_file_contains "${matrix}" "vault_service_tls_certificates.freeipa_ipa01.pkcs12_base64"
assert_file_contains "${matrix}" "vault_service_tls_certificates.freeipa_ipa01.pkcs12_password"
assert_file_contains "${matrix}" "vault_freeipa_ipa01_directory_manager_password"
assert_file_contains "${matrix}" "install_kdc_certificate: false"
assert_file_contains "${vault_docs}" "vault_freeipa_ipa01_directory_manager_password"
assert_file_contains "${vault_docs}" "cn=Directory Manager"
assert_file_contains "${vault_docs}" "freeipa-server-cert-migration.yml"
assert_file_contains "${run_tests}" "test_freeipa_server_certificate_role.sh"

if grep -Eq 'BEGIN (RSA |EC |OPENSSH |)?PRIVATE KEY|BEGIN CERTIFICATE|END CERTIFICATE|END (RSA |EC |OPENSSH |)?PRIVATE KEY' "${tasks}" "${defaults}" "${playbook}"; then
  fail "FreeIPA cert migration files must not contain literal PEM material"
fi

MATRIX="${matrix}" python3 - << 'PY'
import os
from pathlib import Path

import yaml

data = yaml.safe_load(Path(os.environ["MATRIX"]).read_text(encoding="utf-8"))
entry = data["service_tls_certificate_matrix"]["freeipa_ipa01"]
refs = entry["secret_refs"]
for key in ("fullchain_pem", "private_key_pem", "pkcs12_base64", "pkcs12_password", "directory_manager_password"):
    if key not in refs:
        raise SystemExit(f"freeipa_ipa01 missing secret ref {key}")
if refs["directory_manager_password"] != "vault_freeipa_ipa01_directory_manager_password":
    raise SystemExit("FreeIPA Directory Manager password must use the approved vault var")
options = entry.get("deploy_options", {})
if options.get("install_http_certificate") is not True:
    raise SystemExit("FreeIPA HTTP certificate install must be enabled")
if options.get("install_dirsrv_certificate") is not True:
    raise SystemExit("FreeIPA Directory Server certificate install must be enabled")
if options.get("install_kdc_certificate") is not False:
    raise SystemExit("FreeIPA KDC certificate install must default disabled")
if options.get("cert_name") != "ipa01-rfc1918-2026":
    raise SystemExit("FreeIPA cert_name must be deterministic")
PY

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
