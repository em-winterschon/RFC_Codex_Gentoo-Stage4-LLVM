#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
GAP_SCRIPT="${REPO_ROOT}/scripts/netbox-dns-gap-analysis.py"
GAP_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/netbox-dns-gap-analysis.yml"
DNS_VARS="${ANSIBLE_ROOT}/inventories/local-network/group_vars/all/dns_hetzner_cloud.yml"
RUN_TESTS="${SCRIPT_DIR}/run-tests.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

for file in "${GAP_SCRIPT}" "${GAP_PLAYBOOK}" "${DNS_VARS}"; do
  [[ -f "${file}" ]] || fail "missing expected implementation file ${file}"
done

assert_file_contains "${GAP_SCRIPT}" "generate_gap_analysis"
assert_file_contains "${GAP_SCRIPT}" "NetBox is authoritative"
assert_file_contains "${GAP_PLAYBOOK}" "netbox-dns-gap-analysis.py"
assert_file_contains "${DNS_VARS}" "dns_hetzner_cloud_audit_domains"
assert_file_contains "${DNS_VARS}" "rfc1918.systems"
assert_file_contains "${DNS_VARS}" "vernetzen.io"
assert_file_contains "${DNS_VARS}" "yukon.systems"
assert_file_contains "${RUN_TESTS}" "test_netbox_dns_gap_analysis.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

cat > "${tmpdir}/netbox-ip-addresses.json" << 'JSON'
{
  "results": [
    {
      "address": "172.16.99.71/24",
      "dns_name": "sched-sun99-slurmctl-099071.rfc1918.host",
      "custom_fields": {
        "dns_aliases": ["sched-sun99-slurmctl.rfc1918.host"]
      }
    },
    {
      "address": "172.16.99.22/24",
      "dns_name": "sbsoc-accel-int64-m70n2.rfc1918.host",
      "custom_fields": {
        "dns_aliases": ["m70n2.rfc1918.host", "m70-canary.rfc1918.host"]
      }
    },
    {
      "address": "172.16.99.72/24",
      "dns_name": "sched-sun99-slurmwkr-099072.rfc1918.host"
    },
    {
      "address": "172.16.99.51/24",
      "dns_name": "mismatch.rfc1918.host"
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
JSON

cat > "${tmpdir}/ansible-inventory.json" << 'JSON'
{
  "_meta": {
    "hostvars": {
      "sched_sun99_slurmctl_099071": {
        "ansible_host": "172.16.99.71",
        "fqdn": "sched-sun99-slurmctl-099071.rfc1918.host",
        "dns_aliases": ["sched-sun99-slurmctl.rfc1918.host"],
        "observed_service_ip": "172.16.99.71"
      },
      "m70_canary": {
        "ansible_host": "172.16.99.22",
        "fqdn": "sbsoc-accel-int64-m70n2.rfc1918.host",
        "dns_aliases": ["m70n2.rfc1918.host", "m70-canary.rfc1918.host"],
        "observed_service_ip": "172.16.99.22"
      },
      "mismatch_host": {
        "ansible_host": "172.16.99.50",
        "fqdn": "mismatch.rfc1918.host",
        "observed_service_ip": "172.16.99.50"
      },
      "orphan_inventory": {
        "ansible_host": "172.16.99.99",
        "fqdn": "orphan.rfc1918.host",
        "observed_service_ip": "172.16.99.99"
      }
    }
  },
  "all": {
    "hosts": ["sched_sun99_slurmctl_099071", "m70_canary", "mismatch_host", "orphan_inventory"]
  }
}
JSON

cat > "${tmpdir}/token-groups.json" << 'JSON'
[
  {
    "name": "rfc1918",
    "token_name": "fixture-token",
    "api_token": "fixture-secret",
    "zones": ["rfc1918.host", "rfc1918.dev", "rfc1918.ai", "rfc1918.io", "rfc1918.sh", "rfc1918.systems", "rfc1918.org"]
  },
  {
    "name": "vernetzen",
    "token_name": "fixture-token",
    "api_token": "fixture-secret",
    "zones": ["vernetzen.io"]
  },
  {
    "name": "yukon",
    "token_name": "fixture-token",
    "api_token": "fixture-secret",
    "zones": ["yukon.systems"]
  }
]
JSON

cat > "${tmpdir}/hetzner-fixture.json" << 'JSON'
{
  "token_groups": [
    {
      "name": "rfc1918",
      "zones": [
        {"id": "zone-host", "name": "rfc1918.host"},
        {"id": "zone-dev", "name": "rfc1918.dev"},
        {"id": "zone-ai", "name": "rfc1918.ai"},
        {"id": "zone-io", "name": "rfc1918.io"},
        {"id": "zone-sh", "name": "rfc1918.sh"},
        {"id": "zone-systems", "name": "rfc1918.systems"},
        {"id": "zone-org", "name": "rfc1918.org"}
      ],
      "records_by_zone_id": {
        "zone-host": [
          {"id": "ctl-a", "type": "A", "name": "sched-sun99-slurmctl-099071", "value": "172.16.99.71", "ttl": 300},
          {"id": "ctl-c", "type": "CNAME", "name": "sched-sun99-slurmctl", "value": "sched-sun99-slurmctl-099071.rfc1918.host.", "ttl": 300},
          {"id": "m70-a", "type": "A", "name": "sbsoc-accel-int64-m70n2", "value": "172.16.99.23", "ttl": 300},
          {"id": "stale-a", "type": "A", "name": "stale", "value": "172.16.99.250", "ttl": 300}
        ]
      }
    },
    {"name": "vernetzen", "zones": [{"id": "zone-vernetzen", "name": "vernetzen.io"}], "records_by_zone_id": {"zone-vernetzen": []}},
    {"name": "yukon", "zones": [{"id": "zone-yukon", "name": "yukon.systems"}], "records_by_zone_id": {"zone-yukon": []}}
  ]
}
JSON

python3 -m py_compile "${GAP_SCRIPT}"
python3 "${GAP_SCRIPT}" \
  --netbox-ip-addresses-file "${tmpdir}/netbox-ip-addresses.json" \
  --ansible-inventory-json "${tmpdir}/ansible-inventory.json" \
  --hetzner-token-groups-file "${tmpdir}/token-groups.json" \
  --hetzner-fixture-file "${tmpdir}/hetzner-fixture.json" \
  --format json \
  --output "${tmpdir}/gap.json" \
  --markdown-output "${tmpdir}/gap.md"

python3 - "${tmpdir}/gap.json" "${tmpdir}/gap.md" << 'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
markdown = Path(sys.argv[2]).read_text()
summary = report["summary"]
assert report["source_of_truth"] == "netbox"
assert summary["netbox_dns_records"] == 7, summary
assert summary["ansible_dns_records"] == 7, summary
assert summary["hetzner_dns_records"] == 4, summary
assert summary["invalid_dns_names"] >= 1, summary
assert summary["ansible_missing_from_netbox"] == 1, summary
assert summary["netbox_missing_from_ansible"] == 1, summary
assert summary["netbox_ansible_value_mismatches"] == 1, summary
assert summary["hetzner_missing_records"] >= 3, summary
assert summary["hetzner_value_mismatches"] == 1, summary
assert summary["hetzner_extra_records"] == 1, summary

invalid_names = {row["name"]: row for row in report["gaps"]["invalid_dns_names"]}
assert "sched_sun99_slurmctl_099071.rfc1918.host" in invalid_names
assert invalid_names["sched_sun99_slurmctl_099071.rfc1918.host"]["canonical"] == "sched-sun99-slurmctl-099071.rfc1918.host"

ansible_only = {row["fqdn"] for row in report["gaps"]["ansible_missing_from_netbox"]}
assert "orphan.rfc1918.host" in ansible_only
netbox_only = {row["fqdn"] for row in report["gaps"]["netbox_missing_from_ansible"]}
assert "sched-sun99-slurmwkr-099072.rfc1918.host" in netbox_only
mismatches = {row["fqdn"]: row for row in report["gaps"]["netbox_ansible_value_mismatches"]}
assert mismatches["mismatch.rfc1918.host"]["netbox_values"] == ["172.16.99.51"]
assert mismatches["mismatch.rfc1918.host"]["ansible_values"] == ["172.16.99.50"]
hetzner_mismatches = {row["fqdn"]: row for row in report["gaps"]["hetzner_value_mismatches"]}
assert hetzner_mismatches["sbsoc-accel-int64-m70n2.rfc1918.host"]["hetzner_values"] == ["172.16.99.23"]
hetzner_extra = {row["fqdn"] for row in report["gaps"]["hetzner_extra_records"]}
assert "stale.rfc1918.host" in hetzner_extra
assert "NetBox DNS GAP Analysis" in markdown
serialized = json.dumps(report)
assert "fixture-secret" not in serialized
assert "api_token" not in serialized
PY

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -rf "${tmpdir}" "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" << 'YAML'
---
all:
  hosts:
    localhost:
      ansible_connection: local
YAML
  ANSIBLE_CACHE_PLUGIN=memory ansible-playbook --syntax-check -i "${tmp_inventory}" "${GAP_PLAYBOOK}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "$0")"
