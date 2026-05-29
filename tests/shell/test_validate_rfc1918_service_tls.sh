#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/validate-rfc1918-service-tls.sh"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"

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

assert_file_contains "${VALIDATOR}" "s_client"
assert_file_contains "${VALIDATOR}" "-verify_hostname"
assert_file_contains "${VALIDATOR}" "RFC1918_TLS_AUDIT_PATH"
assert_file_contains "${VALIDATOR}" "RFC1918_TLS_NOTIFY"
assert_file_contains "${VALIDATOR}" "forge-security"
assert_file_contains "${VALIDATOR}" "forge-obs"
assert_file_contains "${RUN_TESTS}" "test_validate_rfc1918_service_tls.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

RFC1918_TLS_DRY_RUN=true \
  RFC1918_TLS_SERVICE_IDS=ntfy_lan \
  RFC1918_TLS_AUDIT_PATH="${tmpdir}/audit.jsonl" \
  "${VALIDATOR}" > "${tmpdir}/validator.out"

grep -Fq 'DRY-RUN ntfy_lan msg-sun99-ntfysys-099096.rfc1918.host:443' "${tmpdir}/validator.out" ||
  fail "dry-run validator output missing ntfy target"

python3 - "${tmpdir}/audit.jsonl" << 'PY'
import json
import sys
from pathlib import Path

rows = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()]
if len(rows) != 1:
    raise SystemExit(f"expected one audit row, got {len(rows)}")
row = rows[0]
expected = {
    "service_id": "ntfy_lan",
    "endpoint_fqdn": "msg-sun99-ntfysys-099096.rfc1918.host",
    "port": 443,
    "result": "dry-run",
}
for key, value in expected.items():
    if row.get(key) != value:
        raise SystemExit(f"unexpected audit {key}: {row.get(key)!r}")
if "timestamp" not in row:
    raise SystemExit("audit row missing timestamp")
PY

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
