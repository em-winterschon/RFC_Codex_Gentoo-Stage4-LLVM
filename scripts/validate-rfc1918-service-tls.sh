#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MATRIX="${RFC1918_TLS_MATRIX:-${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/service_tls_certificates.yml}"
SERVICE_IDS="${RFC1918_TLS_SERVICE_IDS:-}"
AUDIT_PATH="${RFC1918_TLS_AUDIT_PATH:-/var/log/rfc1918-service-tls-audit.jsonl}"
CA_FILE="${RFC1918_TLS_CA_FILE:-}"
DRY_RUN="${RFC1918_TLS_DRY_RUN:-false}"
NOTIFY="${RFC1918_TLS_NOTIFY:-false}"
NTFY_BASE="${RFC1918_TLS_NTFY_BASE:-https://msg-sun99-ntfysys-099096.rfc1918.host}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

write_audit() {
  local service_id="$1"
  local endpoint_fqdn="$2"
  local port="$3"
  local issuer="$4"
  local not_after="$5"
  local days_remaining="$6"
  local result="$7"

  python3 - "${AUDIT_PATH}" "${service_id}" "${endpoint_fqdn}" "${port}" \
    "${issuer}" "${not_after}" "${days_remaining}" "${result}" << 'PY'
import datetime as _dt
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
row = {
    "timestamp": _dt.datetime.now(_dt.UTC).isoformat().replace("+00:00", "Z"),
    "service_id": sys.argv[2],
    "endpoint_fqdn": sys.argv[3],
    "port": int(sys.argv[4]),
    "issuer": sys.argv[5],
    "not_after": sys.argv[6],
    "days_remaining": None if sys.argv[7] == "" else int(sys.argv[7]),
    "result": sys.argv[8],
}
with path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(row, sort_keys=True) + "\n")
PY
}

notify_ntfy() {
  local topic="$1"
  local body="$2"

  if [[ "${NOTIFY}" != "true" ]]; then
    return 0
  fi

  curl --fail --silent --show-error --max-time 10 \
    --data-binary "${body}" \
    "${NTFY_BASE%/}/${topic}" > /dev/null || true
}

[[ -f "${MATRIX}" ]] || fail "missing matrix ${MATRIX}"

mapfile -t tls_targets < <(
  MATRIX="${MATRIX}" SERVICE_IDS="${SERVICE_IDS}" python3 - << 'PY'
import os
import sys
from pathlib import Path

import yaml

matrix = yaml.safe_load(Path(os.environ["MATRIX"]).read_text(encoding="utf-8"))
services = matrix.get("service_tls_certificate_matrix", {})
selected = [item.strip() for item in os.environ.get("SERVICE_IDS", "").split(",") if item.strip()]
service_ids = selected or sorted(services, key=lambda service_id: services[service_id].get("rollout_priority", 999999))

for service_id in service_ids:
    if service_id not in services:
        raise SystemExit(f"unknown service ID: {service_id}")
    entry = services[service_id]
    validation = entry.get("validation", {})
    port = validation.get("tcp_port")
    if port is None:
        for candidate in entry.get("service_ports", []):
            candidate = str(candidate)
            if candidate.endswith("/tcp"):
                port = candidate.split("/", 1)[0]
                break
    if port is None:
        raise SystemExit(f"{service_id} has no TCP validation port")
    fields = [
        service_id,
        entry["endpoint_fqdn"],
        str(port),
        validation.get("openssl_name", entry["endpoint_fqdn"]),
        validation.get("url", ""),
    ]
    print("\t".join(fields))
PY
)

failures=0
handshake_file=""
cert_file=""

cleanup_target() {
  rm -f "${handshake_file:-}" "${cert_file:-}"
}
trap cleanup_target EXIT

for tls_target in "${tls_targets[@]}"; do
  IFS=$'\t' read -r service_id endpoint_fqdn port openssl_name validation_url <<< "${tls_target}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    printf 'DRY-RUN %s %s:%s sni=%s\n' "${service_id}" "${endpoint_fqdn}" "${port}" "${openssl_name}"
    write_audit "${service_id}" "${endpoint_fqdn}" "${port}" "" "" "" "dry-run"
    continue
  fi

  handshake_file="$(mktemp)"
  cert_file="$(mktemp)"

  openssl_args=(
    s_client
    -connect "${endpoint_fqdn}:${port}"
    -servername "${openssl_name}"
    -verify_return_error
    -verify_hostname "${openssl_name}"
    -showcerts
  )
  if [[ -n "${CA_FILE}" ]]; then
    openssl_args+=(-CAfile "${CA_FILE}")
  fi

  if ! timeout 20 openssl "${openssl_args[@]}" < /dev/null > "${handshake_file}" 2>&1; then
    printf 'FAIL %s %s:%s OpenSSL validation failed\n' "${service_id}" "${endpoint_fqdn}" "${port}" >&2
    write_audit "${service_id}" "${endpoint_fqdn}" "${port}" "" "" "" "openssl-failed"
    notify_ntfy forge-security "RFC1918 TLS validation failed for ${service_id}: OpenSSL verification failed"
    failures=$((failures + 1))
    cleanup_target
    continue
  fi

  awk '
    /-----BEGIN CERTIFICATE-----/ { print_cert = 1 }
    print_cert { print }
    /-----END CERTIFICATE-----/ { exit }
  ' "${handshake_file}" > "${cert_file}"

  if [[ ! -s "${cert_file}" ]]; then
    printf 'FAIL %s %s:%s no certificate found\n' "${service_id}" "${endpoint_fqdn}" "${port}" >&2
    write_audit "${service_id}" "${endpoint_fqdn}" "${port}" "" "" "" "missing-certificate"
    notify_ntfy forge-security "RFC1918 TLS validation failed for ${service_id}: no peer certificate found"
    failures=$((failures + 1))
    cleanup_target
    continue
  fi

  issuer="$(openssl x509 -in "${cert_file}" -noout -issuer | sed 's/^issuer=//')"
  not_after="$(openssl x509 -in "${cert_file}" -noout -enddate | sed 's/^notAfter=//')"
  not_after_epoch="$(date -u -d "${not_after}" +%s)"
  now_epoch="$(date -u +%s)"
  days_remaining="$(((not_after_epoch - now_epoch) / 86400))"

  if ((days_remaining < 0)); then
    printf 'FAIL %s %s:%s certificate expired\n' "${service_id}" "${endpoint_fqdn}" "${port}" >&2
    write_audit "${service_id}" "${endpoint_fqdn}" "${port}" "${issuer}" "${not_after}" "${days_remaining}" "expired"
    notify_ntfy forge-security "RFC1918 TLS validation failed for ${service_id}: certificate expired"
    failures=$((failures + 1))
    cleanup_target
    continue
  fi

  if [[ -n "${validation_url}" ]]; then
    curl_args=(--fail --silent --show-error --max-time 20)
    if [[ -n "${CA_FILE}" ]]; then
      curl_args+=(--cacert "${CA_FILE}")
    fi
    if ! curl "${curl_args[@]}" "${validation_url}" > /dev/null; then
      printf 'FAIL %s %s health URL failed\n' "${service_id}" "${validation_url}" >&2
      write_audit "${service_id}" "${endpoint_fqdn}" "${port}" "${issuer}" "${not_after}" "${days_remaining}" "health-url-failed"
      notify_ntfy forge-security "RFC1918 TLS validation failed for ${service_id}: health URL failed"
      failures=$((failures + 1))
      cleanup_target
      continue
    fi
  fi

  printf 'PASS %s %s:%s days_remaining=%s\n' "${service_id}" "${endpoint_fqdn}" "${port}" "${days_remaining}"
  write_audit "${service_id}" "${endpoint_fqdn}" "${port}" "${issuer}" "${not_after}" "${days_remaining}" "pass"
  notify_ntfy forge-obs "RFC1918 TLS validation passed for ${service_id}: ${days_remaining} days remaining"
  cleanup_target
done

if ((failures > 0)); then
  exit 1
fi
