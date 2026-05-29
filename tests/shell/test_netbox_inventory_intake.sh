#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

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

validator="${REPO_ROOT}/scripts/validate_netbox_inventory_intake.py"
apply_script="${REPO_ROOT}/scripts/netbox_apply_inventory_intake.py"
example="${ANSIBLE_ROOT}/inventory-intake/sites/local-rfc1918-lab.yml"
rfc99="${ANSIBLE_ROOT}/inventory-intake/sites/rfc99.yml"
sun99="${ANSIBLE_ROOT}/inventory-intake/sites/sun99.yml"
yks99="${ANSIBLE_ROOT}/inventory-intake/sites/yks99.yml"
fmt2="${ANSIBLE_ROOT}/inventory-intake/sites/fmt2.yml"
readme="${ANSIBLE_ROOT}/inventory-intake/README.md"
playbook="${ANSIBLE_ROOT}/playbooks/netbox-inventory-intake-validate.yml"
apply_playbook="${ANSIBLE_ROOT}/playbooks/netbox-inventory-intake-apply.yml"
docs="${REPO_ROOT}/docs/INFRASTRUCTURE-INVENTORY-INTAKE.md"
wiki_docs="${REPO_ROOT}/docs/wiki/Infrastructure-Inventory-Intake.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT
all_sites_json="${temp_dir}/netbox-intake-all-sites-validation.json"
apply_plan_json="${temp_dir}/netbox-intake-apply-plan.json"
invalid_output="${temp_dir}/netbox-intake-invalid.out"
invalid_fixture="${temp_dir}/invalid-intake.yml"

assert_file_contains "${validator}" "class IntakeValidationError"
assert_file_contains "${validator}" "validate_sites"
assert_file_contains "${validator}" "validate_prefixes"
assert_file_contains "${validator}" "validate_devices"
assert_file_contains "${validator}" "validate_service_vips"

assert_file_contains "${apply_script}" "apply_inventory"
assert_file_contains "${apply_script}" "dry_run"
assert_file_contains "${apply_script}" "dcim/sites"
assert_file_contains "${apply_script}" "virtualization/clusters"
assert_file_contains "${apply_script}" "ipam/ip-addresses"
assert_file_contains "${apply_script}" "first_query"
assert_file_contains "${apply_script}" "manufacturer_id"
assert_file_contains "${apply_script}" "apply_device_interfaces"
assert_file_contains "${apply_script}" "apply_interface_cables"
assert_file_contains "${apply_script}" "apply_power_outlets"
assert_file_contains "${apply_script}" "normalize_interface_type"

assert_file_contains "${example}" "inventory_intake_version: 1"
assert_file_contains "${example}" "datacenters:"
assert_file_contains "${example}" "clusters:"
assert_file_contains "${example}" "devices:"
assert_file_contains "${example}" "service_vips:"
assert_file_contains "${example}" "gmktek_nucbox_k10_stage5_candidate"
assert_file_contains "${example}" "admin_sun99_forge_099070"
assert_file_contains "${example}" "pdu_rfc99_corectrl_ap7901"
assert_file_contains "${example}" "obs_sun99_prometheus_099064"
assert_file_contains "${example}" "obs_sun99_vmetrics_099065"
assert_file_contains "${example}" "obs_sun99_grafana_099066"
assert_file_contains "${example}" "vm_mcp_control_plane"
assert_file_contains "${example}" "sched_sun99_slurmctl_099071"
assert_file_contains "${example}" "slurm_worker_node01"
assert_file_contains "${example}" "agx_rfc99_bunnydev"
assert_file_contains "${example}" "m70_canary"
assert_file_contains "${example}" "log-sun99-rsyslog-099093"
assert_file_contains "${example}" "sched-sun99-slurmctl-099071.rfc1918.host"
assert_file_contains "${example}" "sched-sun99-slurmwkr-099072.rfc1918.host"
assert_file_contains "${example}" "172.16.99.93"
assert_file_contains "${example}" "172.16.99.71"
assert_file_contains "${example}" "172.16.99.72"
assert_file_contains "${example}" "log-sun99-rsyslog.rfc1918.host"
assert_file_contains "${example}" "172.16.99.156"
assert_file_contains "${example}" "172.16.99.70"
assert_file_contains "${example}" "172.16.99.64"
assert_file_contains "${example}" "172.16.99.65"
assert_file_contains "${example}" "172.16.99.66"
assert_file_contains "${example}" "172.16.99.68"
assert_file_contains "${example}" "172.16.99.34"
assert_file_contains "${example}" "172.16.99.22"
assert_file_contains "${example}" "172.16.99.241"
assert_file_contains "${example}" "00:07:32:78:65:C6"
assert_file_not_contains "${example}" "172.16.99.108"
assert_file_contains "${example}" "outlet_index: 4"
assert_file_contains "${example}" "admin-sun99-forge"
assert_file_contains "${example}" "host_gmktec_k10"
assert_file_contains "${example}" "power_outlets:"
assert_file_contains "${example}" "outlet_index: 6"
assert_file_contains "${example}" "outlet_index: 7"
assert_file_contains "${example}" "m70-canary"
assert_file_contains "${rfc99}" "gw_rfc99_mkcrs309"
assert_file_contains "${rfc99}" "gw_rfc99_mkccr2004_16g"
assert_file_contains "${rfc99}" "CCR2004-16G-2S+PC"
assert_file_contains "${sun99}" "nanonet-private-cloud"
assert_file_contains "${yks99}" "172.28.0.0/16"
assert_file_contains "${fmt2}" "66.160.146.148/32"
assert_file_contains "${fmt2}" "66.160.146.144/28"
assert_file_contains "${fmt2}" "2001:470:1:43c::/64"
assert_file_contains "${fmt2}" "sw-sfo200-7060cx32s-2010"
assert_file_contains "${fmt2}" "kvm-sfo200-pri-9922"
assert_file_contains "${fmt2}" "fmt2-checkmk"

assert_file_contains "${readme}" "inventory-intake"
assert_file_contains "${playbook}" "Validate NetBox inventory intake definitions"
assert_file_contains "${playbook}" "validate_netbox_inventory_intake.py"
assert_file_contains "${apply_playbook}" "Apply NetBox inventory intake definitions"
assert_file_contains "${apply_playbook}" "netbox_apply_inventory_intake.py"
assert_file_contains "${apply_playbook}" "netbox_inventory_apply"
assert_file_contains "${docs}" "Structured Intake Files"
assert_file_contains "${docs}" "netbox-inventory-intake-apply.yml"
assert_file_contains "${wiki_docs}" "Structured Intake Files"
assert_file_contains "${run_tests}" "test_netbox_inventory_intake.sh"

python3 -m py_compile "${validator}"
python3 -m py_compile "${apply_script}"
python3 "${validator}" "${example}" --format json > /dev/null
python3 "${validator}" "${ANSIBLE_ROOT}/inventory-intake/sites" --format json > "${all_sites_json}"
grep -Fq '"devices": 37' "${all_sites_json}" || fail "all-sites validation did not include expected device count"
python3 "${apply_script}" "${example}" --api-url http://127.0.0.1 --token fake-token --format json > "${apply_plan_json}"
grep -Fq '"dry_run": true' "${apply_plan_json}" || fail "apply plan did not default to dry-run"
grep -Fq 'dcim/sites:local-rfc1918-lab' "${apply_plan_json}" || fail "apply plan did not include site"
grep -Fq 'virtualization/clusters:hasslehoff-proxmox' "${apply_plan_json}" || fail "apply plan did not include cluster"
grep -Fq 'ipam/ip-addresses:172.16.99.93/24' "${apply_plan_json}" || fail "apply plan did not include rsyslog VIP"
grep -Fq 'dcim/devices:gmktek_nucbox_k10_stage5_candidate' "${apply_plan_json}" || fail "apply plan did not include K10 device"
grep -Fq 'dcim/devices:admin_sun99_forge_099070' "${apply_plan_json}" || fail "apply plan did not include M70 Forge automation-admin device"
grep -Fq 'dcim/devices:obs_sun99_prometheus_099064' "${apply_plan_json}" || fail "apply plan did not include Prometheus VM"
grep -Fq 'dcim/devices:obs_sun99_vmetrics_099065' "${apply_plan_json}" || fail "apply plan did not include VictoriaMetrics VM"
grep -Fq 'dcim/devices:obs_sun99_grafana_099066' "${apply_plan_json}" || fail "apply plan did not include Grafana VM"
grep -Fq 'dcim/devices:vm_mcp_control_plane' "${apply_plan_json}" || fail "apply plan did not include MCP control-plane VM"
grep -Fq 'dcim/devices:sched_sun99_slurmctl_099071' "${apply_plan_json}" || fail "apply plan did not include SLURM controller VM"
grep -Fq 'dcim/devices:slurm_worker_node01' "${apply_plan_json}" || fail "apply plan did not include SLURM first worker VM"
grep -Fq 'dcim/devices:agx_rfc99_bunnydev' "${apply_plan_json}" || fail "apply plan did not include Thor AGX device"
grep -Fq 'dcim/devices:m70_canary' "${apply_plan_json}" || fail "apply plan did not include M70 canary"
grep -Fq 'dcim/devices:pdu_rfc99_corectrl_ap7901' "${apply_plan_json}" || fail "apply plan did not include AP7901 PDU device"
grep -Fq 'ipam/ip-addresses:172.16.99.34/24' "${apply_plan_json}" || fail "apply plan did not include Thor AGX management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.22/24' "${apply_plan_json}" || fail "apply plan did not include M70 canary management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.156/24' "${apply_plan_json}" || fail "apply plan did not include K10 management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.70/24' "${apply_plan_json}" || fail "apply plan did not include M70 Forge automation-admin management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.64/24' "${apply_plan_json}" || fail "apply plan did not include Prometheus management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.65/24' "${apply_plan_json}" || fail "apply plan did not include VictoriaMetrics management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.66/24' "${apply_plan_json}" || fail "apply plan did not include Grafana management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.68/24' "${apply_plan_json}" || fail "apply plan did not include MCP control-plane management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.71/24' "${apply_plan_json}" || fail "apply plan did not include SLURM controller management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.72/24' "${apply_plan_json}" || fail "apply plan did not include SLURM first worker management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.241/24' "${apply_plan_json}" || fail "apply plan did not include AP7901 PDU management IP"
grep -Fq 'dcim/interfaces:gmktek_nucbox_k10_stage5_candidate:eth0' "${apply_plan_json}" || fail "apply plan did not include K10 interface"
grep -Fq 'dcim/interfaces:admin_sun99_forge_099070:bond0' "${apply_plan_json}" || fail "apply plan did not include M70 Forge automation-admin bond interface"
grep -Fq 'dcim/interfaces:admin_sun99_forge_099070:netboot0' "${apply_plan_json}" || fail "apply plan did not include M70 Forge netboot0 interface"
grep -Fq 'dcim/interfaces:admin_sun99_forge_099070:enp3s0' "${apply_plan_json}" || fail "apply plan did not include M70 Forge enp3s0 interface"
grep -Fq 'dcim/interfaces:admin_sun99_forge_099070:eno4' "${apply_plan_json}" || fail "apply plan did not include M70 Forge reserved X553 interfaces"
grep -Fq 'dcim/interfaces:sw_mgmt_css326:ge7' "${apply_plan_json}" || fail "apply plan did not include CSS326 ge7 interface"
grep -Fq 'dcim/interfaces:agx_rfc99_bunnydev:enP2p1s0' "${apply_plan_json}" || fail "apply plan did not include Thor AGX management interface"
grep -Fq 'dcim/interfaces:m70_canary:netboot0' "${apply_plan_json}" || fail "apply plan did not include M70 canary netboot0"
grep -Fq 'dcim/interfaces:m70_canary:eno4' "${apply_plan_json}" || fail "apply plan did not include M70 canary eno4"
grep -Fq 'dcim/interfaces:pdu_rfc99_corectrl_ap7901:mgmt' "${apply_plan_json}" || fail "apply plan did not include AP7901 management interface"
grep -Fq 'dcim/power-ports:admin_sun99_forge_099070:power0' "${apply_plan_json}" || fail "apply plan did not include M70 Forge automation-admin power port"
grep -Fq 'dcim/power-ports:gmktek_nucbox_k10_stage5_candidate:power0' "${apply_plan_json}" || fail "apply plan did not include K10 power port"
grep -Fq 'dcim/power-ports:m70_canary:power0' "${apply_plan_json}" || fail "apply plan did not include M70 canary power port"
grep -Fq 'dcim/power-outlets:pdu_rfc99_corectrl_ap7901:outlet4' "${apply_plan_json}" || fail "apply plan did not include AP7901 outlet 4"
grep -Fq 'dcim/power-outlets:pdu_rfc99_corectrl_ap7901:outlet6' "${apply_plan_json}" || fail "apply plan did not include AP7901 outlet 6"
grep -Fq 'dcim/power-outlets:pdu_rfc99_corectrl_ap7901:outlet7' "${apply_plan_json}" || fail "apply plan did not include AP7901 outlet 7"
grep -Fq 'dcim/cables:pdu_rfc99_corectrl_ap7901:outlet4->admin_sun99_forge_099070:power0' "${apply_plan_json}" || fail "apply plan did not include M70 Forge automation-admin PDU cable"
grep -Fq 'dcim/cables:pdu_rfc99_corectrl_ap7901:outlet6->gmktek_nucbox_k10_stage5_candidate:power0' "${apply_plan_json}" || fail "apply plan did not include K10 PDU cable"
grep -Fq 'dcim/cables:pdu_rfc99_corectrl_ap7901:outlet7->m70_canary:power0' "${apply_plan_json}" || fail "apply plan did not include M70 canary PDU cable"
grep -Fq 'dcim/cables:m70_canary:netboot0->sw_mgmt_css326:ge19' "${apply_plan_json}" || fail "apply plan did not include M70 canary data cable"
grep -Fq 'dcim/cables:agx_rfc99_bunnydev:enP2p1s0->sw_mgmt_css326:ge7' "${apply_plan_json}" || fail "apply plan did not include Thor AGX data cable"

python3 - "${apply_script}" << 'PY'
import importlib.util
import pathlib
import sys

script = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(script.parent))
spec = importlib.util.spec_from_file_location("netbox_apply_inventory_intake", script)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)

assert module.normalize_interface_type({"type": "1gbase-t"}) == "1000base-t"
assert module.normalize_interface_type({"type": "10gbase-x-sfpp", "media": "10G-SR"}) == "10gbase-sr"
assert module.normalize_interface_type({"type": "10gbase-x-sfpp", "media": "10G-DAC"}) == "10gbase-cu"
assert module.normalize_interface_type({"type": "40gbase-x-qsfpp"}) == "40gbase-sr4"
assert module.normalize_interface_type({"name": "ge16"}) == "1000base-t"
assert module.primary_ip_update_payload("172.16.99.6/24", 10, interface_bound=False) is None
assert module.primary_ip_update_payload("172.16.99.156/24", 11, interface_bound=True) == {"primary_ip4": 11}
assert module.primary_ip_update_payload("2001:db8::1/64", 12, interface_bound=True) == {"primary_ip6": 12}
assert module.interface_mark_connected({"connected_device": "switch", "connected_interface": "ge7"}) is False
assert module.interface_mark_connected({"connected_device": "switch"}) is True
assert module.ip_assignment_matches_interface(
    {"assigned_object_type": None, "assigned_object_id": None},
    {"id": 74},
)
assert module.ip_object_is_assigned_to_interface(
    {"assigned_object_type": "dcim.interface", "assigned_object_id": 74},
    {"id": 74},
)
assert module.ip_object_is_assigned_to_interface(
    {"assigned_object_type": "dcim.interface", "assigned_object": {"id": 74}},
    {"id": 74},
)
assert not module.ip_object_is_assigned_to_interface(
    {"assigned_object_type": None, "assigned_object_id": None},
    {"id": 74},
)
assert not module.ip_object_is_assigned_to_interface(
    {"assigned_object_type": "dcim.interface", "assigned_object_id": 11},
    {"id": 74},
)
assert module.ip_host("172.16.99.96/24") == "172.16.99.96"
assert module.ip_host("172.16.99.96/32") == "172.16.99.96"
assert module.ip_host("2001:db8::1/64") == "2001:db8::1"
assert module.ip_hosts_match("172.16.99.96/24", "172.16.99.96/32")
assert not module.ip_hosts_match("172.16.99.96/24", "172.16.99.97/24")
assert module.managed_power_intake_cable(
    {
        "label": "pdu_rfc99_corectrl_ap7901:outlet4->admin_sun99_forge_099070:power0",
        "description": "Power-chain cable tracked from inventory intake.",
    }
)
assert not module.managed_power_intake_cable(
    {
        "label": "operator-owned-cable",
        "description": "Do not replace automatically.",
    }
)
PY

cat > "${invalid_fixture}" << 'EOF'
---
inventory_intake_version: 1
datacenters:
  - name: broken-site
    slug: broken-site
    timezone: UTC
    management_prefixes:
      - 10.99.0.0/24
devices:
  - name: bad-device
    site: missing-site
    role: access-switch
    management_ip: 10.99.0.5
prefixes:
  - prefix: not-a-prefix
    site: broken-site
EOF

if python3 "${validator}" "${invalid_fixture}" > "${invalid_output}" 2>&1; then
  fail "invalid intake fixture unexpectedly passed"
fi
grep -Fq "missing-site" "${invalid_output}" || fail "invalid fixture did not report missing site"
grep -Fq "not-a-prefix" "${invalid_output}" || fail "invalid fixture did not report invalid prefix"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="${temp_dir}/hosts.yml"
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
EOF
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${playbook}" > /dev/null
  ansible-playbook --syntax-check -i "${tmp_inventory}" "${apply_playbook}" > /dev/null
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
