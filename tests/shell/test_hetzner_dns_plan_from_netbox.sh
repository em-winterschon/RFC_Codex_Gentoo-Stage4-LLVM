#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PLANNER="${REPO_ROOT}/scripts/plan-hetzner-dns-from-netbox.py"

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
plan_playbook="${ANSIBLE_ROOT}/playbooks/hetzner-dns-plan-from-netbox.yml"
docs="${REPO_ROOT}/docs/HETZNER-DNS-AUTOMATION.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${PLANNER}" "generate_dns_plan"
assert_file_contains "${dns_vars}" "dns_hetzner_cloud_zone_groups"
assert_file_contains "${plan_playbook}" "plan-hetzner-dns-from-netbox.py"
assert_file_contains "${docs}" "hetzner-dns-plan-from-netbox.yml"
assert_file_contains "${run_tests}" "test_hetzner_dns_plan_from_netbox.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

cat > "${tmpdir}/netbox-ip-addresses.json" <<'EOF'
{
  "results": [
    {
      "address": "172.16.99.250/24",
      "dns_name": "sw-xgs-1250-pri.rfc1918.io"
    },
    {
      "address": "192.168.1.254/24",
      "dns_name": "gw-xgs-pon-att5ge.rfc1918.io."
    },
    {
      "address": "10.9.8.20/24",
      "dns_name": "rsyslog-ingest-vip.rfc1918.host"
    },
    {
      "address": "2001:db8::10/64",
      "dns_name": "ipv6-test.rfc1918.io"
    },
    {
      "address": "10.1.2.3/24",
      "dns_name": "outside.example.net"
    },
    {
      "address": "10.1.2.4/24",
      "dns_name": ""
    }
  ]
}
EOF

cat > "${tmpdir}/zone-groups.json" <<'EOF'
[
  {
    "name": "rfc1918",
    "zones": ["rfc1918.io", "rfc1918.host"]
  },
  {
    "name": "yukon",
    "zones": ["yukon.example"]
  }
]
EOF

python3 -m py_compile "${PLANNER}"
python3 "${PLANNER}" \
  --netbox-ip-addresses-file "${tmpdir}/netbox-ip-addresses.json" \
  --zone-groups-file "${tmpdir}/zone-groups.json" \
  --default-ttl 300 \
  --format json > "${tmpdir}/plan.json"

python3 - "${tmpdir}/plan.json" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text())
assert plan["apply"] is False
assert plan["allow_delete"] is False
assert plan["summary"]["records"] == 4
assert plan["summary"]["skipped"] == 2
records = {(row["fqdn"], row["type"]): row for row in plan["records"]}
assert records[("sw-xgs-1250-pri.rfc1918.io", "A")]["values"] == ["172.16.99.250"]
assert records[("gw-xgs-pon-att5ge.rfc1918.io", "A")]["relative_name"] == "gw-xgs-pon-att5ge"
assert records[("rsyslog-ingest-vip.rfc1918.host", "A")]["zone"] == "rfc1918.host"
assert records[("ipv6-test.rfc1918.io", "AAAA")]["values"] == ["2001:db8::10"]
reasons = {row["reason"] for row in plan["skipped"]}
assert "no_matching_zone" in reasons
assert "missing_dns_name" in reasons
serialized = json.dumps(plan)
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
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${plan_playbook}" >/dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
