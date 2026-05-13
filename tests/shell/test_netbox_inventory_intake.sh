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
assert_file_contains "${apply_script}" "apply_power_outlets"
assert_file_contains "${apply_script}" "normalize_interface_type"

assert_file_contains "${example}" "inventory_intake_version: 1"
assert_file_contains "${example}" "datacenters:"
assert_file_contains "${example}" "clusters:"
assert_file_contains "${example}" "devices:"
assert_file_contains "${example}" "service_vips:"
assert_file_contains "${example}" "gmktek_nucbox_k10_stage5_candidate"
assert_file_contains "${example}" "pdu_rfc99_corectrl_ap7901"
assert_file_contains "${example}" "lap_sun99_chonkers"
assert_file_contains "${example}" "obs_sun99_prometheus_099064"
assert_file_contains "${example}" "obs_sun99_vmetrics_099065"
assert_file_contains "${example}" "obs_sun99_grafana_099066"
assert_file_contains "${example}" "sched_sun99_slurmctl_099071"
assert_file_contains "${example}" "slurm_worker_node01"
assert_file_contains "${example}" "log-sun99-rsyslog-099093"
assert_file_contains "${example}" "sched-sun99-slurmctl-099071.rfc1918.host"
assert_file_contains "${example}" "sched-sun99-slurmwkr-099072.rfc1918.host"
assert_file_contains "${example}" "172.16.99.93"
assert_file_contains "${example}" "172.16.99.71"
assert_file_contains "${example}" "172.16.99.72"
assert_file_contains "${example}" "log-sun99-rsyslog.rfc1918.host"
assert_file_contains "${example}" "172.16.99.156"
assert_file_contains "${example}" "172.16.99.157"
assert_file_contains "${example}" "172.16.99.64"
assert_file_contains "${example}" "172.16.99.65"
assert_file_contains "${example}" "172.16.99.66"
assert_file_contains "${example}" "172.16.99.241"
assert_file_contains "${example}" "84:5C:31:A5:CF:51"
assert_file_contains "${example}" "ipxe-httpv4-with-pxe-fallback"
assert_file_not_contains "${example}" "172.16.99.108"
assert_file_contains "${example}" "outlet_index: 4"
assert_file_contains "${example}" "host_gmktec_k10"
assert_file_contains "${example}" "power_outlets:"
assert_file_contains "${example}" "outlet_index: 6"
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
python3 "${validator}" "${ANSIBLE_ROOT}/inventory-intake/sites" --format json > /tmp/netbox-intake-all-sites-validation.json
grep -Fq '"devices": 33' /tmp/netbox-intake-all-sites-validation.json || fail "all-sites validation did not include expected device count"
python3 "${apply_script}" "${example}" --api-url http://127.0.0.1 --token fake-token --format json > /tmp/netbox-intake-apply-plan.json
grep -Fq '"dry_run": true' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not default to dry-run"
grep -Fq 'dcim/sites:local-rfc1918-lab' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include site"
grep -Fq 'virtualization/clusters:hasslehoff-proxmox' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include cluster"
grep -Fq 'ipam/ip-addresses:172.16.99.93/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include rsyslog VIP"
grep -Fq 'dcim/devices:gmktek_nucbox_k10_stage5_candidate' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include K10 device"
grep -Fq 'dcim/devices:lap_sun99_chonkers' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Chonkers laptop device"
grep -Fq 'dcim/devices:obs_sun99_prometheus_099064' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Prometheus VM"
grep -Fq 'dcim/devices:obs_sun99_vmetrics_099065' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include VictoriaMetrics VM"
grep -Fq 'dcim/devices:obs_sun99_grafana_099066' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Grafana VM"
grep -Fq 'dcim/devices:sched_sun99_slurmctl_099071' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include SLURM controller VM"
grep -Fq 'dcim/devices:slurm_worker_node01' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include SLURM first worker VM"
grep -Fq 'dcim/devices:pdu_rfc99_corectrl_ap7901' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include AP7901 PDU device"
grep -Fq 'ipam/ip-addresses:172.16.99.156/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include K10 management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.157/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Chonkers management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.64/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Prometheus management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.65/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include VictoriaMetrics management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.66/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Grafana management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.71/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include SLURM controller management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.72/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include SLURM first worker management IP"
grep -Fq 'ipam/ip-addresses:172.16.99.241/24' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include AP7901 PDU management IP"
grep -Fq 'dcim/interfaces:gmktek_nucbox_k10_stage5_candidate:eth0' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include K10 interface"
grep -Fq 'dcim/interfaces:lap_sun99_chonkers:LOM' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Chonkers LOM interface"
grep -Fq 'dcim/interfaces:pdu_rfc99_corectrl_ap7901:mgmt' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include AP7901 management interface"
grep -Fq 'dcim/power-ports:lap_sun99_chonkers:power0' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Chonkers power port"
grep -Fq 'dcim/power-ports:gmktek_nucbox_k10_stage5_candidate:power0' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include K10 power port"
grep -Fq 'dcim/power-outlets:pdu_rfc99_corectrl_ap7901:outlet4' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include AP7901 outlet 4"
grep -Fq 'dcim/power-outlets:pdu_rfc99_corectrl_ap7901:outlet6' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include AP7901 outlet 6"
grep -Fq 'dcim/cables:pdu_rfc99_corectrl_ap7901:outlet4->lap_sun99_chonkers:power0' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include Chonkers PDU cable"
grep -Fq 'dcim/cables:pdu_rfc99_corectrl_ap7901:outlet6->gmktek_nucbox_k10_stage5_candidate:power0' /tmp/netbox-intake-apply-plan.json || fail "apply plan did not include K10 PDU cable"

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
PY

invalid_fixture="$(mktemp --suffix=.yml)"
trap 'rm -f "${invalid_fixture}"' EXIT
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

if python3 "${validator}" "${invalid_fixture}" > /tmp/netbox-intake-invalid.out 2>&1; then
  fail "invalid intake fixture unexpectedly passed"
fi
grep -Fq "missing-site" /tmp/netbox-intake-invalid.out || fail "invalid fixture did not report missing site"
grep -Fq "not-a-prefix" /tmp/netbox-intake-invalid.out || fail "invalid fixture did not report invalid prefix"

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  trap 'rm -f "${invalid_fixture}" "${tmp_inventory}"' EXIT
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
