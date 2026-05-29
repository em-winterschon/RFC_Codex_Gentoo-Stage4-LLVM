#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
POLICY="${REPO_ROOT}/docs/fabric-policies/fmt2-r630-arista7060-fabric-policy.yml"
FMT2_DOC="${REPO_ROOT}/docs/FMT2-R630-HCI-STAGED-REBUILD.md"
RDMA_DOC="${REPO_ROOT}/docs/RDMA-STORAGE-FABRIC-PLAN.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  test -f "${file}" || fail "missing file ${file}"
  grep -q -- "${pattern}" "${file}" || fail "expected '${pattern}' in ${file}"
}

test -f "${POLICY}" || fail "missing fabric policy ${POLICY}"

python3 - "${POLICY}" << 'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    raise SystemExit(f"PyYAML missing: {exc}") from exc

policy = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))

assert policy["policy_id"] == "fmt2-r630-arista7060-fabric-policy"
assert policy["issue"] == 130
assert policy["mutation_default"] == "blocked"
assert policy["switch"]["hostname"] == "sw-sfo200-7060cx32s-2010"
assert policy["switch"]["management_ip"] == "172.18.20.10"
assert policy["switch"]["access_path"]["preferred"] == "ssh-proxyjump-checkmk"
assert policy["switch"]["access_path"]["direct_m70_ssh"] == "blocked-by-mgmt-acl"

hosts = policy["hosts"]
expected_hosts = {
    "kvm-sfo200-pri-9922",
    "kvm-sfo200-sec-9923",
    "kvm-sfo200-ter-9924",
}
assert set(hosts) == expected_hosts

expected_ports = {
    "kvm-sfo200-pri-9922": {
        "x710": ["Et3/1", "Et3/2", "Et3/3", "Et3/4"],
        "connectx": ["Et6/1", "Et6/3"],
        "blocked": True,
    },
    "kvm-sfo200-sec-9923": {
        "x710": ["Et4/1", "Et4/2", "Et4/3", "Et4/4"],
        "connectx": ["Et7/1", "Et7/3"],
        "blocked": True,
    },
    "kvm-sfo200-ter-9924": {
        "x710": ["Et5/1", "Et5/2", "Et5/3", "Et5/4"],
        "connectx": ["Et8/1", "Et8/3"],
        "blocked": True,
    },
}

for host, expected in expected_ports.items():
    entry = hosts[host]
    assert entry["arista_ports"]["x710"] == expected["x710"]
    assert entry["arista_ports"]["connectx4"] == expected["connectx"]
    assert entry["rdma_admission"]["blocked"] is expected["blocked"]
    assert entry["intended_host_network"]["management"] == ["eno1", "eno2"]
    assert entry["intended_host_network"]["vm_frontend"] == ["eno3", "eno4"]
    assert entry["intended_host_network"]["rdma"] == ["enp130s0f0np0", "enp130s0f1np1"]

pri_blockers = hosts["kvm-sfo200-pri-9922"]["rdma_admission"]["blockers"]
assert "missing-linux-connectx-enumeration" in pri_blockers
assert "missing-idrac-connectx-inventory" in pri_blockers
assert "missing-arista-lldp-neighbor" in pri_blockers

sec_blockers = hosts["kvm-sfo200-sec-9923"]["rdma_admission"]["blockers"]
assert "vendor-ofed-doca-not-installed" in sec_blockers
assert "ibverbs-perftest-tooling-absent" in sec_blockers
assert "placeholder-connectx-macs" in sec_blockers

fabric = policy["fabric_classes"]["rocev2_storage"]
assert fabric["vlan"] == 50
assert fabric["mtu"] == 9214
assert fabric["first_pass_topology"] == "independent-50g-paths"
assert fabric["pfc"] == "required-storage-class-only"
assert fabric["ecn_wred"] == "required-explicit-profile-before-mutation"
assert fabric["dscp_pcp_mapping"] == "required-before-mutation"
assert fabric["lacp_promotion"] == "blocked-until-pairwise-rdma-and-one-path-failure-pass"

gates = {gate["id"]: gate for gate in policy["acceptance_gates"]}
required_gates = {
    "arista-config-snapshot",
    "lldp-port-map-confirmed",
    "bios-sriov-iommu-confirmed",
    "nic-firmware-inventory",
    "sec-placeholder-macs-resolved",
    "rocev2-qos-profile-defined",
    "rollback-commands-generated",
    "pairwise-rdma-smoke",
    "one-path-failure",
}
missing = required_gates - set(gates)
assert not missing, sorted(missing)
for gate in required_gates:
    assert gates[gate]["required_before"] in {"switch-mutation", "rdma-admission"}

rollback = policy["rollback"]
assert rollback["required_before_apply"] is True
assert "copy running-config startup-config" not in rollback["forbidden_commands"]
assert any("configure replace" in cmd for cmd in rollback["candidate_commands"])
assert any("reload" in cmd for cmd in rollback["candidate_commands"])

live_commands = policy["read_only_validation_commands"]
for required in (
    'ssh 7060 "show running-config"',
    'ssh 7060 "show lldp neighbors"',
    'ssh 7060 "show interfaces status"',
    'ssh 7060 "show interfaces counters errors"',
):
    assert required in live_commands
PY

assert_file_contains "${POLICY}" 'Do not mutate Arista, pri, sec, ter, or storage paths from this policy artifact alone.'
assert_file_contains "${POLICY}" 'Po613'
assert_file_contains "${POLICY}" 'Po713'
assert_file_contains "${POLICY}" 'Po813'
assert_file_contains "${FMT2_DOC}" 'fmt2-r630-arista7060-fabric-policy.yml'
assert_file_contains "${RDMA_DOC}" 'fmt2-r630-arista7060-fabric-policy.yml'

printf 'PASS: %s\n' "$(basename "$0")"
