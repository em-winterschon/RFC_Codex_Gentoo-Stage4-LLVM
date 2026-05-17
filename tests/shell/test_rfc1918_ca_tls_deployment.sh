#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
MATRIX="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/service_tls_certificates.yml"
LEGACY_OOB="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/legacy_oob_devices.yml"
TLS_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/rfc1918_tls_deploy.yml"
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

for file in "${MATRIX}" "${LEGACY_OOB}" "${TLS_PLAYBOOK}" "${PLAN}" "${DOC}" "${WIKI}"; do
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
assert_file_contains "${MATRIX}" "unsafe_writes: true"
assert_file_contains "${MATRIX}" "manage_file_modes: false"
assert_file_contains "${LEGACY_OOB}" "legacy_oob_device_policy:"
assert_file_contains "${LEGACY_OOB}" "pdu_rfc99_corectrl_ap7901:"
assert_file_contains "${LEGACY_OOB}" "tls_supported: false"
assert_file_contains "${LEGACY_OOB}" "http_legacy"
assert_file_contains "${LEGACY_OOB}" "openssl_validation_allowed: false"
assert_file_contains "${TLS_PLAYBOOK}" "rfc1918_tls_target_hosts"
assert_file_contains "${TLS_PLAYBOOK}" "rfc1918_ca_trust"
assert_file_contains "${TLS_PLAYBOOK}" "rfc1918_service_tls"
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

MATRIX="${MATRIX}" LEGACY_OOB="${LEGACY_OOB}" python3 - << 'PY'
import os
from pathlib import Path

import yaml

matrix_path = Path(os.environ["MATRIX"])
data = yaml.safe_load(matrix_path.read_text(encoding="utf-8"))
legacy_path = Path(os.environ["LEGACY_OOB"])
legacy = yaml.safe_load(legacy_path.read_text(encoding="utf-8"))

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
]

services = data.get("service_tls_certificate_matrix", {})
missing = sorted(set(required_services) - set(services))
if missing:
    raise SystemExit(f"missing TLS service matrix entries: {missing}")
if "pdu_rfc99_corectrl" in services:
    raise SystemExit("legacy AP7901 PDU must not be tracked as an RFC1918 TLS target")

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
        if service_id == "freeipa_ipa01" and ref_key == "directory_manager_password":
            if ref_value != "vault_freeipa_ipa01_directory_manager_password":
                raise SystemExit("freeipa_ipa01 Directory Manager secret ref must use the approved vault key")
            continue
        if not str(ref_value).startswith(f"vault_service_tls_certificates.{service_id}."):
            raise SystemExit(f"{service_id} secret ref {ref_key} is not service-scoped")

device_services = {"routeros_ccr2004_gateway"}
for service_id in device_services:
    refs = services[service_id]["secret_refs"]
    if "pkcs12_base64" not in refs or "pkcs12_password" not in refs:
        raise SystemExit(f"{service_id} must track PKCS#12 secret refs")

legacy_policy = legacy.get("legacy_oob_device_policy", {})
if legacy_policy.get("tls_compliance_state") != "exempt-legacy-firmware":
    raise SystemExit("legacy OOB policy must mark TLS-exempt firmware state")
legacy_devices = legacy.get("legacy_oob_devices", {})
pdu = legacy_devices.get("pdu_rfc99_corectrl_ap7901", {})
if pdu.get("tls_supported") is not False:
    raise SystemExit("AP7901 PDU must explicitly disable TLS support")
allowed_protocols = pdu.get("allowed_protocols", {})
for protocol in ("snmpv3", "serial", "http_legacy"):
    if protocol not in allowed_protocols:
        raise SystemExit(f"AP7901 PDU missing allowed protocol {protocol}")
if "https" not in pdu.get("forbidden_protocols", []):
    raise SystemExit("AP7901 PDU must forbid HTTPS automation")
if pdu.get("validation", {}).get("openssl_validation_allowed") is not False:
    raise SystemExit("AP7901 PDU must opt out of OpenSSL TLS validation")

if services["netbox_stage4"]["validation"].get("url") != "https://svc-netbox-stage4.rfc1918.host/":
    raise SystemExit("netbox_stage4 validation URL must not require API authentication")

if services["proxmox_hasslehoff"]["validation"].get("url") != "https://hasslehoff.rfc1918.host:8006/":
    raise SystemExit("proxmox_hasslehoff validation URL must not require API authentication")

proxmox_options = services["proxmox_hasslehoff"].get("deploy_options", {})
if proxmox_options.get("unsafe_writes") is not True:
    raise SystemExit("proxmox_hasslehoff must enable unsafe_writes for pmxcfs")
if proxmox_options.get("manage_file_modes") is not False:
    raise SystemExit("proxmox_hasslehoff must not chmod pmxcfs certificate files")
PY

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
