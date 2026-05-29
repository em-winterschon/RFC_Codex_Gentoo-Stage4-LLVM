#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
RENDER_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${RENDER_ROOT}"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${path}"; then
    fail "did not expect '${needle}' in ${path}"
  fi
}

(
  cd "${ANSIBLE_ROOT}"
  ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACKS_ENABLED=control_flow \
    ansible-playbook -i inventories/examples/hosts.yml playbooks/routeros-rfc99-gateway.yml \
    -e "routeros_rfc99_gateway_render_root=${RENDER_ROOT}" \
    -e "routeros_rfc99_gateway_certificate_source=rfc1918_private_ca" \
    -e "routeros_rfc99_gateway_internal_ca_pkcs12_passphrase=vaulted-routeros-pkcs12-passphrase" > /dev/null
)

rsc="${RENDER_ROOT}/gw_rfc99_mkccr2004_16g_example-rfc99-gateway.rsc"
[[ -s "${rsc}" ]] || fail "expected rendered RouterOS RSC at ${rsc}"

assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_rfc99_gateway/defaults/main.yml" "routeros_rfc99_gateway_certificate_source: self_signed"
assert_file_contains "${rsc}" '# Internal CA certificate import.'
assert_file_contains "${rsc}" '/certificate import file-name="rfc1918-private-ca.crt" passphrase="" trusted=yes'
assert_file_contains "${rsc}" '/certificate import file-name="rfc1918-gw-rfc99-mkccr2004-16g.p12" passphrase="vaulted-routeros-pkcs12-passphrase"'
assert_file_contains "${rsc}" '/certificate set [find where common-name="gw-rfc99-mkccr2004-16g.rfc1918.host"] name="rfc1918-gw-rfc99-mkccr2004-16g" trusted=yes'
assert_file_contains "${rsc}" '/ip service set www-ssl disabled=no port=443 address=172.16.99.0/24,10.9.8.0/24,10.128.128.0/24 certificate=rfc1918-gw-rfc99-mkccr2004-16g tls-version=only-1.2'
assert_file_contains "${rsc}" '/ip service set api-ssl disabled=no port=8729 address=172.16.99.0/24,10.9.8.0/24,10.128.128.0/24 certificate=rfc1918-gw-rfc99-mkccr2004-16g tls-version=only-1.2'
assert_file_not_contains "${rsc}" '/certificate add name="rfc99-gw-selfsigned-template"'
assert_file_not_contains "${rsc}" '/certificate sign "rfc99-gw-selfsigned-template"'
assert_file_contains "${REPO_ROOT}/tests/shell/run-tests.sh" "test_routeros_internal_ca_certificate_import.sh"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
