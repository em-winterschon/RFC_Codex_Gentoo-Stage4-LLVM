#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
EXPORTER="${REPO_ROOT}/scripts/export-netbox-provisioning-inventory.py"

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

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  if grep -Fq "${pattern}" "${file}"; then
    fail "expected ${file} not to contain ${pattern}"
  fi
}

export_playbook="${ANSIBLE_ROOT}/playbooks/netbox-provisioning-inventory-export.yml"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"
plan="${REPO_ROOT}/docs/superpowers/plans/2026-05-03-netbox-driven-provisioning-and-container-services.md"

assert_file_contains "${EXPORTER}" "export_provisioning_inventory"
assert_file_contains "${export_playbook}" "export-netbox-provisioning-inventory.py"
assert_file_contains "${run_tests}" "test_export_netbox_provisioning_inventory.sh"
assert_file_contains "${plan}" "scripts/export-netbox-provisioning-inventory.py"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

cat > "${tmpdir}/virtual-machines.json" <<'EOF'
{
  "results": [
    {
      "name": "container-services",
      "status": {"value": "planned"},
      "primary_ip4": {
        "address": "10.9.8.89/24",
        "dns_name": "container-services.rfc1918.host"
      },
      "cluster": {"name": "hasslehoff"},
      "role": {"name": "container-services"},
      "tags": [{"name": "codex-managed"}, {"name": "stage4-stage5"}],
      "custom_fields": {
        "stage5_role": "container-services",
        "proxmox_vmid": 1089,
        "profile": "vm-container-services"
      }
    },
    {
      "name": "manual-host",
      "status": {"value": "active"},
      "primary_ip4": {"address": "172.16.99.99/24"},
      "cluster": {"name": "hasslehoff"},
      "tags": [{"name": "manual"}],
      "custom_fields": {}
    }
  ]
}
EOF

cat > "${tmpdir}/devices.json" <<'EOF'
{
  "results": [
    {
      "name": "sw-xgs-1250-pri",
      "status": {"value": "active"},
      "primary_ip4": {
        "address": "172.16.99.250/24",
        "dns_name": "sw-xgs-1250-pri.rfc1918.io"
      },
      "site": {"name": "rfc99"},
      "role": {"name": "administrative-switch"},
      "tags": [{"name": "codex-managed"}],
      "custom_fields": {
        "stage5_role": "network-device"
      }
    }
  ]
}
EOF

cat > "${tmpdir}/ip-addresses.json" <<'EOF'
{
  "results": [
    {
      "address": "10.9.8.89/24",
      "dns_name": "container-services.rfc1918.host",
      "status": {"value": "active"},
      "tags": [{"name": "codex-managed"}],
      "custom_fields": {
        "service_ports": [
          {"name": "container-services-haproxy-http", "port": 80, "protocol": "tcp"},
          {"name": "container-services-nginx", "port": 8080, "protocol": "tcp"}
        ]
      }
    },
    {
      "address": "172.16.99.62/24",
      "dns_name": "netbox-http.rfc1918.host",
      "status": {"value": "active"},
      "tags": [{"name": "codex-managed"}],
      "custom_fields": {
        "stage5_role": "netbox-service",
        "service_ports": [
          {"name": "netbox-http", "port": 80, "protocol": "tcp"}
        ]
      }
    },
    {
      "address": "172.16.99.250/24",
      "dns_name": "sw-xgs-1250-pri.rfc1918.io",
      "status": {"value": "active"},
      "tags": [{"name": "codex-managed"}],
      "custom_fields": {}
    },
    {
      "address": "172.16.99.99/24",
      "dns_name": "manual-host.rfc1918.io",
      "status": {"value": "active"},
      "tags": [{"name": "manual"}],
      "custom_fields": {}
    }
  ]
}
EOF

python3 -m py_compile "${EXPORTER}"
python3 "${EXPORTER}" \
  --virtual-machines-file "${tmpdir}/virtual-machines.json" \
  --devices-file "${tmpdir}/devices.json" \
  --ip-addresses-file "${tmpdir}/ip-addresses.json" \
  --tag codex-managed \
  --inventory-output "${tmpdir}/hosts.yml" \
  --ipam-output "${tmpdir}/ipam.json" \
  --service-targets-output "${tmpdir}/service-targets.json"

assert_file_contains "${tmpdir}/hosts.yml" "container_services:"
assert_file_contains "${tmpdir}/hosts.yml" "ansible_host: 10.9.8.89"
assert_file_contains "${tmpdir}/hosts.yml" "install_hostname: container-services"
assert_file_contains "${tmpdir}/hosts.yml" "stage5_role: container-services"
assert_file_contains "${tmpdir}/hosts.yml" "proxmox_vmid: 1089"
assert_file_contains "${tmpdir}/hosts.yml" "netbox_http:"
assert_file_contains "${tmpdir}/hosts.yml" "stage5_role: netbox-service"
assert_file_contains "${tmpdir}/hosts.yml" "sw_xgs_1250_pri:"
assert_file_not_contains "${tmpdir}/hosts.yml" "manual-host"

python3 - "${tmpdir}/ipam.json" "${tmpdir}/service-targets.json" <<'PY'
import json
import sys
from pathlib import Path

ipam = json.loads(Path(sys.argv[1]).read_text())
targets = json.loads(Path(sys.argv[2]).read_text())

assert ipam["summary"] == {"devices": 1, "ip_addresses": 3, "standalone_ip_hosts": 1, "virtual_machines": 1}
assert ipam["records"][0]["name"] == "container-services"
assert ipam["records"][0]["ip_address"] == "10.9.8.89"
assert ipam["records"][0]["dns_name"] == "container-services.rfc1918.host"
assert ipam["records"][1]["name"] == "sw-xgs-1250-pri"
assert ipam["records"][1]["ip_address"] == "172.16.99.250"
assert ipam["records"][2]["name"] == "netbox-http"
assert ipam["records"][2]["ip_address"] == "172.16.99.62"

assert targets["summary"]["targets"] == 3
target_names = {target["service_name"] for target in targets["targets"]}
assert target_names == {"container-services-haproxy-http", "container-services-nginx", "netbox-http"}
serialized = json.dumps({"ipam": ipam, "targets": targets})
assert "api_token" not in serialized
assert "Token " not in serialized
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
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${export_playbook}" >/dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
