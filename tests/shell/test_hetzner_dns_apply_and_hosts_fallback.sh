#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PLANNER="${REPO_ROOT}/scripts/plan-hetzner-dns-from-inventory.py"
APPLIER="${REPO_ROOT}/scripts/apply-hetzner-dns-plan.py"

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
plan_playbook="${ANSIBLE_ROOT}/playbooks/hetzner-dns-plan-from-inventory.yml"
apply_playbook="${ANSIBLE_ROOT}/playbooks/hetzner-dns-apply.yml"
hosts_playbook="${ANSIBLE_ROOT}/playbooks/local-hosts-fallback.yml"
docs="${REPO_ROOT}/docs/HETZNER-DNS-AUTOMATION.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${PLANNER}" "generate_dns_plan"
assert_file_contains "${APPLIER}" "apply_dns_plan"
assert_file_contains "${dns_vars}" "dns_hetzner_cloud_required_domains"
assert_file_contains "${dns_vars}" "dns_hetzner_cloud_inventory_managed_domains"
assert_file_contains "${dns_vars}" "obs-sun99-prometheus-099064"
assert_file_contains "${dns_vars}" "obs-sun99-prometheus.rfc1918.host"
assert_file_contains "${dns_vars}" "obs-sun99-vmetrics-099065"
assert_file_contains "${dns_vars}" "obs-sun99-vmetrics.rfc1918.host"
assert_file_contains "${dns_vars}" "obs-sun99-grafana-099066"
assert_file_contains "${dns_vars}" "obs-sun99-grafana.rfc1918.host"
assert_file_contains "${dns_vars}" "obs-sun99-kibana-099067"
assert_file_contains "${dns_vars}" "obs-sun99-kibana.rfc1918.host"
assert_file_contains "${dns_vars}" "log-sun99-rsyslog-099093"
assert_file_contains "${dns_vars}" "log-sun99-rsyslog.rfc1918.host"
assert_file_contains "${dns_vars}" "admin-sun99-forge-099070"
assert_file_contains "${dns_vars}" "admin-sun99-forge.rfc1918.host"
assert_file_contains "${plan_playbook}" "plan-hetzner-dns-from-inventory.py"
assert_file_contains "${apply_playbook}" "apply-hetzner-dns-plan.py"
assert_file_contains "${apply_playbook}" "dns_hetzner_cloud_apply_enabled"
assert_file_contains "${hosts_playbook}" "RFC1918 automated DNS fallback"
assert_file_contains "${docs}" "hetzner-dns-apply.yml"
assert_file_contains "${docs}" "dns_hetzner_cloud_apply_enabled=true"
assert_file_contains "${run_tests}" "test_hetzner_dns_apply_and_hosts_fallback.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

cat > "${tmpdir}/inventory.yml" << 'EOF'
---
inventory_intake_version: 1
datacenters:
  - name: local-rfc1918-lab
    slug: local-rfc1918-lab
    timezone: UTC
    management_prefixes:
      - 172.16.99.0/24
devices:
  - name: svc_identity_ipa01
    site: local-rfc1918-lab
    role: identity-controller
    management_ip: 172.16.99.63
    fqdn: ipa01.rfc1918.host
  - name: hasslehoff
    site: local-rfc1918-lab
    role: proxmox-hypervisor
    management_ip: 172.16.99.9
    fqdn: cls0-rfc99-hasslehoff-099009.rfc1918.host
    dns_aliases:
      - hasslehoff.rfc1918.host
  - name: svc_container_services_safe_move_01
    site: local-rfc1918-lab
    role: container-services-staging
    management_ip: 172.16.99.89
    fqdn: svc-container-services-safe-move-01.rfc1918.host
service_vips:
  - name: identity-ldap-radius
    site: local-rfc1918-lab
    address: 172.16.99.63
    fqdn: identity-ldap-radius.rfc1918.host
  - name: msg-sun99-ntfysys
    site: local-rfc1918-lab
    address: 172.16.99.96
    fqdn: msg-sun99-ntfysys-099096.rfc1918.host
    aliases:
      - msg-sun99-ntfysys.rfc1918.host
  - name: netbox-http
    site: local-rfc1918-lab
    address: 172.16.99.62
EOF

cat > "${tmpdir}/zone-groups.json" << 'EOF'
[
  {
    "name": "rfc1918",
    "zones": ["rfc1918.host"]
  }
]
EOF

python3 -m py_compile "${PLANNER}" "${APPLIER}"
python3 "${PLANNER}" \
  "${tmpdir}/inventory.yml" \
  --zone-groups-file "${tmpdir}/zone-groups.json" \
  --required-domain rfc1918.host \
  --default-domain rfc1918.host \
  --default-ttl 300 \
  --format json \
  --hosts-output "${tmpdir}/hosts.generated" > "${tmpdir}/plan.json"

python3 - "${tmpdir}/plan.json" "${tmpdir}/hosts.generated" << 'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text())
hosts = Path(sys.argv[2]).read_text()

assert plan["summary"]["records"] == 8, plan["summary"]
assert plan["summary"]["required_domain_errors"] == 0, plan["summary"]
records = {(row["fqdn"], row["type"]): row for row in plan["records"]}
assert records[("ipa01.rfc1918.host", "A")]["values"] == ["172.16.99.63"]
assert records[("identity-ldap-radius.rfc1918.host", "A")]["values"] == ["172.16.99.63"]
assert records[("cls0-rfc99-hasslehoff-099009.rfc1918.host", "A")]["values"] == ["172.16.99.9"]
assert records[("hasslehoff.rfc1918.host", "CNAME")]["values"] == [
    "cls0-rfc99-hasslehoff-099009.rfc1918.host."
]
assert records[("svc-container-services-safe-move-01.rfc1918.host", "A")]["values"] == ["172.16.99.89"]
assert records[("msg-sun99-ntfysys-099096.rfc1918.host", "A")]["values"] == ["172.16.99.96"]
assert records[("msg-sun99-ntfysys.rfc1918.host", "CNAME")]["values"] == [
    "msg-sun99-ntfysys-099096.rfc1918.host."
]
assert records[("netbox-http.rfc1918.host", "A")]["values"] == ["172.16.99.62"]
skipped = {(row["fqdn"], row["reason"]) for row in plan["skipped"]}
assert "172.16.99.63 ipa01.rfc1918.host ipa01 identity-ldap-radius.rfc1918.host identity-ldap-radius" in hosts
assert "172.16.99.96 msg-sun99-ntfysys-099096.rfc1918.host" in hosts
assert "msg-sun99-ntfysys.rfc1918.host" in hosts
assert "api_token" not in json.dumps(plan)
PY

cat > "${tmpdir}/bad-inventory.yml" << 'EOF'
---
inventory_intake_version: 1
devices:
  - name: broken_identity
    management_ip: 172.16.99.63
    fqdn: ipa01.rfc1918.host
  - name: duplicate_identity
    management_ip: 172.16.99.64
    fqdn: ipa01.rfc1918.host
EOF

if python3 "${PLANNER}" \
  "${tmpdir}/bad-inventory.yml" \
  --zone-groups-file "${tmpdir}/zone-groups.json" \
  --required-domain rfc1918.host \
  --format json > "${tmpdir}/bad-plan.json" 2> "${tmpdir}/bad-plan.err"; then
  fail "conflicting required-domain DNS plan unexpectedly succeeded"
fi
grep -Fq "conflicting_rrset_values" "${tmpdir}/bad-plan.err" || fail "missing conflict diagnostic"

cat > "${tmpdir}/token-groups.json" << 'EOF'
[
  {
    "name": "rfc1918",
    "token_name": "fixture-token",
    "api_token": "fixture-secret",
    "zones": ["rfc1918.host"]
  }
]
EOF

cat > "${tmpdir}/provider-fixture.json" << 'EOF'
{
  "token_groups": [
    {
      "name": "rfc1918",
      "zones": [
        {"id": "zone-host", "name": "rfc1918.host"}
      ],
      "records_by_zone_id": {
        "zone-host": {
          "rrsets": [
            {"id": "rr-ipa", "type": "A", "name": "ipa01", "records": ["172.16.99.60"], "ttl": 300},
            {"id": "rr-stale", "type": "A", "name": "stale", "records": ["172.16.99.250"], "ttl": 300}
          ]
        }
      }
    }
  ]
}
EOF

python3 - "${tmpdir}/plan.json" << 'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
plan = json.loads(path.read_text())
plan["records"].append(
    {
        "action": "delete",
        "token_group": "rfc1918",
        "zone": "rfc1918.host",
        "fqdn": "stale.rfc1918.host",
        "relative_name": "stale",
        "type": "A",
        "ttl": 300,
        "values": [],
    }
)
path.write_text(json.dumps(plan), encoding="utf-8")
PY

python3 "${APPLIER}" \
  --plan-file "${tmpdir}/plan.json" \
  --token-groups-file "${tmpdir}/token-groups.json" \
  --fixture-file "${tmpdir}/provider-fixture.json" \
  --allow-delete \
  --apply \
  --format json > "${tmpdir}/apply-result.json"

python3 - "${tmpdir}/apply-result.json" << 'PY'
import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text())
action_results = {action["result"] for action in result["actions"]}
assert "created" in action_results, result
assert "updated" in action_results, result
assert "deleted" in action_results, result
assert result["summary"]["planned"] >= 1, result
assert "fixture-secret" not in json.dumps(result)
assert "api_token" not in json.dumps(result)
PY

cat > "${tmpdir}/provider-conflict-fixture.json" << 'EOF'
{
  "token_groups": [
    {
      "name": "rfc1918",
      "zones": [
        {"id": "zone-host", "name": "rfc1918.host"}
      ],
      "records_by_zone_id": {
        "zone-host": {
          "rrsets": [
            {"id": "rr-conflict", "type": "CNAME", "name": "ipa01", "records": [{"value": "old-target.rfc1918.host."}], "ttl": 300}
          ]
        }
      }
    }
  ]
}
EOF

python3 "${APPLIER}" \
  --plan-file "${tmpdir}/plan.json" \
  --token-groups-file "${tmpdir}/token-groups.json" \
  --fixture-file "${tmpdir}/provider-conflict-fixture.json" \
  --apply \
  --format json > "${tmpdir}/conflict-result.json" || true

python3 - "${tmpdir}/conflict-result.json" << 'PY'
import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text())
conflicts = [
    action for action in result["actions"]
    if action.get("reason") == "existing_rrset_type_conflict"
]
assert conflicts, result
assert conflicts[0]["name"] == "ipa01"
assert result["summary"]["errors"] >= 1
PY

python3 - "${APPLIER}" << 'PY'
import importlib.util
import pathlib
import sys
from urllib import parse

script = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("hetzner_apply", script)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)

calls = []

def fake_request_json(method, url, token, payload=None):
    calls.append(url)
    page = parse.parse_qs(parse.urlsplit(url).query).get("page", ["1"])[0]
    if page == "1":
        return {
            "rrsets": [{"id": "p1", "type": "A", "name": "first", "records": [{"value": "192.0.2.1"}]}],
            "pagination": {"page": 1, "last_page": 2, "next_page": 2},
        }
    return {
        "rrsets": [{"id": "p2", "type": "A", "name": "second", "records": [{"value": "192.0.2.2"}]}],
        "pagination": {"page": 2, "last_page": 2, "next_page": None},
    }

module.request_json = fake_request_json
records = module.fetch_zone_records("https://api.example", "redacted", "zone")
assert [row["name"] for row in records] == ["first", "second"]
assert any("per_page=100" in url for url in calls)
PY

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -rf "${tmpdir}" "${tmp_inventory}"' EXIT
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${plan_playbook}" > /dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${apply_playbook}" > /dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${hosts_playbook}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
