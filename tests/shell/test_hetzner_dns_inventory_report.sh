#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
REPORTER="${REPO_ROOT}/scripts/report-hetzner-dns-inventory.py"

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

dns_vars="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/dns_hetzner_cloud.yml"
report_playbook="${ANSIBLE_ROOT}/playbooks/hetzner-dns-inventory-report.yml"
docs="${REPO_ROOT}/docs/HETZNER-DNS-AUTOMATION.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${REPORTER}" "generate_dns_inventory_report"
assert_file_contains "${dns_vars}" "dns_hetzner_cloud_token_groups"
assert_file_contains "${report_playbook}" "report-hetzner-dns-inventory.py"
assert_file_contains "${docs}" "hetzner-dns-inventory-report.yml"
assert_file_contains "${run_tests}" "test_hetzner_dns_inventory_report.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

cat > "${tmpdir}/token-groups.json" <<'EOF'
[
  {
    "name": "rfc1918",
    "token_name": "fixture-token",
    "api_token": "fixture-secret",
    "zones": ["rfc1918.io", "rfc1918.host"]
  }
]
EOF

cat > "${tmpdir}/hetzner-fixture.json" <<'EOF'
{
  "token_groups": [
    {
      "name": "rfc1918",
      "zones": [
        {"id": "zone-io", "name": "rfc1918.io"},
        {"id": "zone-host", "name": "rfc1918.host"}
      ],
      "records_by_zone_id": {
        "zone-io": [
          {"id": "a1", "type": "A", "name": "sw-xgs-1250-pri", "value": "172.16.99.250", "ttl": 300},
          {"id": "a2", "type": "A", "name": "sw-xgs-1250-pri", "value": "172.16.99.250", "ttl": 300},
          {"id": "aaaa1", "type": "AAAA", "name": "sw-xgs-1250-pri", "value": "2001:db8::250", "ttl": 300},
          {"id": "c1", "type": "CNAME", "name": "switch-alias", "value": "sw-xgs-1250-pri.rfc1918.io.", "ttl": 300},
          {"id": "txt1", "type": "TXT", "name": "@", "value": "site-verification", "ttl": 300},
          {"id": "mx1", "type": "MX", "name": "@", "value": "10 mail.rfc1918.io.", "ttl": 300}
        ],
        "zone-host": {
          "rrsets": [
            {"id": "rr-a3", "type": "A", "name": "rsyslog-ingest-vip", "records": ["10.9.8.20"], "ttl": 300},
            {"id": "rr-bad1", "type": "A", "name": "bad-ip", "records": ["not-an-ip"], "ttl": 300}
          ]
        }
      }
    }
  ]
}
EOF

python3 -m py_compile "${REPORTER}"
python3 "${REPORTER}" \
  --token-groups-file "${tmpdir}/token-groups.json" \
  --fixture-file "${tmpdir}/hetzner-fixture.json" \
  --format json > "${tmpdir}/report.json"

python3 - "${tmpdir}/report.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
assert report["summary"]["zones_configured"] == 2
assert report["summary"]["zones_readable"] == 2
assert report["summary"]["records_total"] == 8
assert report["summary"]["records_by_type"] == {"A": 4, "AAAA": 1, "CNAME": 1, "MX": 1, "TXT": 1}
assert report["summary"]["connectivity_hosts"] == 2

zones = {zone["zone"]: zone for zone in report["zones"]}
assert zones["rfc1918.io"]["records_total"] == 6
assert zones["rfc1918.io"]["records_by_type"] == {"A": 2, "AAAA": 1, "CNAME": 1, "MX": 1, "TXT": 1}
assert zones["rfc1918.host"]["records_by_type"] == {"A": 2}

hosts_by_zone = report["connectivity_targets"]["hosts_by_zone"]
io_hosts = {host["fqdn"]: host for host in hosts_by_zone["rfc1918.io"]}
assert io_hosts["sw-xgs-1250-pri.rfc1918.io"]["addresses"]["A"] == ["172.16.99.250"]
assert io_hosts["sw-xgs-1250-pri.rfc1918.io"]["addresses"]["AAAA"] == ["2001:db8::250"]
assert io_hosts["sw-xgs-1250-pri.rfc1918.io"]["validation_targets"] == [
    {"mode": "hostname", "target": "sw-xgs-1250-pri.rfc1918.io"},
    {"mode": "ip", "target": "172.16.99.250"},
    {"mode": "ip", "target": "2001:db8::250"},
]

flat_hosts = {host["fqdn"]: host for host in report["connectivity_targets"]["flat_hosts"]}
assert "rsyslog-ingest-vip.rfc1918.host" in flat_hosts
skipped_reasons = {row["reason"] for row in report["skipped_records"]}
assert "non_connectivity_record_type" in skipped_reasons
assert "invalid_ip_value" in skipped_reasons

serialized = json.dumps(report)
assert "fixture-secret" not in serialized
assert "api_token" not in serialized
PY

if command -v ansible-playbook >/dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -rf "${tmpdir}" "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" <<'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${report_playbook}" >/dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
