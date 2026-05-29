#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
INVENTORY="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
WORKFLOW="${REPO_ROOT}/docs/workflows/fmt2-sec-rdma-positive-control.json"
DOC="${REPO_ROOT}/docs/RDMA-STORAGE-FABRIC-PLAN.md"

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

assert_file_contains "${INVENTORY}" 'kvm_sfo200_sec_9923:'
assert_file_contains "${INVENTORY}" 'ansible_host: 10.200.99.23'
assert_file_contains "${INVENTORY}" 'fmt2_roce_role: positive-control'
assert_file_contains "${INVENTORY}" 'fmt2_roce_peer: kvm_sfo200_ter_9924'
assert_file_contains "${INVENTORY}" 'kvm_sfo200_ter_9924:'
assert_file_contains "${INVENTORY}" 'ansible_host: 10.200.99.24'
assert_file_contains "${INVENTORY}" 'fmt2_roce_role: pairwise-peer'
assert_file_contains "${INVENTORY}" 'fmt2_ansible_execution_host: admin_sun99_forge_099070'
assert_file_contains "${INVENTORY}" 'nvidia_doca_ofed_enabled: true'
assert_file_contains "${INVENTORY}" 'nvidia_doca_ofed_apply: false'
assert_file_contains "${INVENTORY}" 'nvidia_doca_ofed_skip_device_detection: false'
assert_file_contains "${INVENTORY}" 'nvidia_doca_ofed_allow_custom_kernel: false'
assert_file_contains "${INVENTORY}" 'fmt2_transport_required: openvpn-fmt2-on-m70'
assert_file_contains "${WORKFLOW}" 'ansible-playbook'
assert_file_contains "${WORKFLOW}" 'nvidia-doca-ofed.yml'
assert_file_contains "${DOC}" 'Ansible DOCA/OFED preflight for `sec` and `ter` must run from M70'

python3 - "${INVENTORY}" << 'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    raise SystemExit(f"PyYAML missing: {exc}") from exc

inventory = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
hosts = inventory["all"]["children"]["roce_hosts"]["hosts"]
expected = {
    "kvm_sfo200_sec_9923": "10.200.99.23",
    "kvm_sfo200_ter_9924": "10.200.99.24",
}
for name, address in expected.items():
    host = hosts[name]
    assert host["ansible_host"] == address
    assert host["ansible_user"] == "verwalterin"
    assert host["ansible_become"] is True
    assert host["nvidia_doca_ofed_enabled"] is True
    assert host["nvidia_doca_ofed_apply"] is False
    assert host["nvidia_doca_ofed_skip_device_detection"] is False
    assert host["fmt2_ansible_execution_host"] == "admin_sun99_forge_099070"
PY

printf 'PASS: %s\n' "$(basename "$0")"
