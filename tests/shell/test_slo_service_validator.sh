#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/slo_service_validator.py"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

free_port() {
  python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

test -f "${VALIDATOR}"
python3 -m py_compile "${VALIDATOR}"

temp_dir="$(mktemp -d)"
trap 'kill "${http_pid:-}" >/dev/null 2>&1 || true; rm -rf "${temp_dir}"' EXIT

mkdir -p "${temp_dir}/www"
printf 'ok\n' > "${temp_dir}/www/healthz"
http_port="$(free_port)"
python3 -m http.server "${http_port}" --bind 127.0.0.1 --directory "${temp_dir}/www" >/dev/null 2>&1 &
http_pid=$!
sleep 1

cat > "${temp_dir}/slo.json" <<EOF
{
  "name": "test-slo",
  "services": [
    {
      "name": "test-http",
      "checks": [
        {
          "name": "healthz",
          "protocol": "http",
          "target": "127.0.0.1",
          "port": ${http_port},
          "path": "/healthz",
          "expected_status": [200],
          "latency_budget_ms": 2000,
          "timeout_seconds": 2
        },
        {
          "name": "tcp-open",
          "protocol": "tcp",
          "target": "127.0.0.1",
          "port": ${http_port},
          "latency_budget_ms": 2000,
          "timeout_seconds": 2
        }
      ]
    }
  ]
}
EOF

output="$("${VALIDATOR}" --manifest "${temp_dir}/slo.json" --phase post-move --json)"
assert_contains "${output}" '"manifest_name": "test-slo"'
assert_contains "${output}" '"slo_met": true'
assert_contains "${output}" '"checks_successful": 2'

cat > "${temp_dir}/failed-slo.json" <<'EOF'
{
  "name": "failed-slo",
  "services": [
    {
      "name": "closed-port",
      "checks": [
        {
          "name": "tcp-closed",
          "protocol": "tcp",
          "target": "127.0.0.1",
          "port": 9,
          "timeout_seconds": 1
        }
      ]
    }
  ]
}
EOF

if "${VALIDATOR}" --manifest "${temp_dir}/failed-slo.json" --json >/tmp/slo-validator-closed.out 2>&1; then
  fail 'closed TCP port unexpectedly passed SLO validation'
fi
assert_contains "$(cat /tmp/slo-validator-closed.out)" '"slo_met": false'

printf 'PASS: %s\n' "$(basename "$0")"
