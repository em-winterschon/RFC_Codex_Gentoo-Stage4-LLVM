#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
MATRIX="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/service_tls_certificates.yml"
PLAN="${REPO_ROOT}/docs/superpowers/plans/2026-05-16-rfc1918-ca-tls-deployment.md"
DOC="${REPO_ROOT}/docs/RFC1918-CA-TLS-DEPLOYMENT.md"
WIKI="${REPO_ROOT}/docs/wiki/ITIL-ADR-RFC1918-CA-TLS-Deployment.md"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"
VAULT_DOCS="${REPO_ROOT}/docs/ANSIBLE-VAULT.md"

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

for file in "${MATRIX}" "${PLAN}" "${DOC}" "${WIKI}"; do
  [[ -f "${file}" ]] || fail "missing file ${file}"
done

assert_file_contains "${MATRIX}" "service_tls_certificate_policy:"
assert_file_contains "${MATRIX}" "service_tls_certificate_matrix:"
assert_file_contains "${MATRIX}" "vault_service_tls_certificates.ntfy_lan.fullchain_pem"
assert_file_contains "${MATRIX}" "vault_service_tls_certificates.routeros_ccr2004_gateway.pkcs12_base64"
assert_file_contains "${MATRIX}" "msg-sun99-ntfysys-099096.rfc1918.host"
assert_file_contains "${MATRIX}" "log-sun99-rsyslog-099093.rfc1918.host"
assert_file_contains "${MATRIX}" "obs-sun99-esvip-099092.rfc1918.host"
assert_file_contains "${MATRIX}" "app-sfo200-monitoring-9927.vernetzen.io"
assert_file_contains "${MATRIX}" "gw-rfc99-mkccr2004-16g.rfc1918.host"
assert_file_contains "${MATRIX}" "pdu-rfc99-corectrl-p08-099241.rfc1918.host"
assert_file_contains "${MATRIX}" "pdu-rfc99-corectrl-099241.rfc1918.host"
assert_file_contains "${PLAN}" "# RFC1918 CA TLS Deployment Implementation Plan"
assert_file_contains "${PLAN}" "REQUIRED SUB-SKILL"
assert_file_contains "${PLAN}" "service_tls_certificates.yml"
assert_file_contains "${DOC}" "RFC1918 private CA"
assert_file_contains "${WIKI}" "ITIL ADR: RFC1918 CA And TLS Deployment"
assert_file_contains "${VAULT_DOCS}" "vault_service_tls_certificates"
assert_file_contains "${RUN_TESTS}" "test_rfc1918_ca_tls_deployment.sh"

if grep -Eq 'BEGIN (RSA |EC |OPENSSH |)?PRIVATE KEY|BEGIN CERTIFICATE|END CERTIFICATE|END (RSA |EC |OPENSSH |)?PRIVATE KEY' "${MATRIX}"; then
  fail "matrix must not contain literal PEM material"
fi

MATRIX="${MATRIX}" python3 - <<'PY'
import os
from pathlib import Path

import yaml

matrix_path = Path(os.environ["MATRIX"])
data = yaml.safe_load(matrix_path.read_text(encoding="utf-8"))

policy = data.get("service_tls_certificate_policy", {})
if policy.get("secret_namespace") != "vault_service_tls_certificates":
    raise SystemExit("unexpected secret namespace")
if policy.get("deploy_enabled_default") is not False:
    raise SystemExit("TLS deployment must default disabled")
if policy.get("mutation_required") is not True:
    raise SystemExit("TLS deployment must require mutation gate")

required_services = [
    "ntfy_lan",
    "rsyslog_tls_vip",
    "elasticsearch_sun99_vip",
    "netbox_stage4",
    "freeipa_ipa01",
    "prometheus_sun99",
    "victoriametrics_sun99",
    "grafana_sun99",
    "kibana_sun99",
    "checkmk_fmt2",
    "mcp_control_plane",
    "routeros_ccr2004_gateway",
    "proxmox_hasslehoff",
    "pdu_rfc99_corectrl",
]

services = data.get("service_tls_certificate_matrix", {})
missing = sorted(set(required_services) - set(services))
if missing:
    raise SystemExit(f"missing TLS service matrix entries: {missing}")

for service_id in required_services:
    entry = services[service_id]
    for key in (
        "rollout_priority",
        "lifecycle_state",
        "service_class",
        "owner_inventory_host",
        "termination_owner",
        "endpoint_fqdn",
        "endpoint_ips",
        "service_ports",
        "certificate_profile",
        "certificate_authority",
        "deploy_paths",
        "secret_refs",
        "validation",
    ):
        if key not in entry:
            raise SystemExit(f"{service_id} missing required key {key}")
    if entry["certificate_authority"] != "rfc1918_private_ca":
        raise SystemExit(f"{service_id} does not use rfc1918_private_ca")
    if not entry["endpoint_ips"]:
        raise SystemExit(f"{service_id} must have at least one endpoint IP")
    if not entry["service_ports"]:
        raise SystemExit(f"{service_id} must have at least one service port")
    refs = entry["secret_refs"]
    for ref_key, ref_value in refs.items():
        if not str(ref_value).startswith(f"vault_service_tls_certificates.{service_id}."):
            raise SystemExit(f"{service_id} secret ref {ref_key} is not service-scoped")

device_services = {"routeros_ccr2004_gateway", "pdu_rfc99_corectrl"}
for service_id in device_services:
    refs = services[service_id]["secret_refs"]
    if "pkcs12_base64" not in refs or "pkcs12_password" not in refs:
        raise SystemExit(f"{service_id} must track PKCS#12 secret refs")
PY

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
