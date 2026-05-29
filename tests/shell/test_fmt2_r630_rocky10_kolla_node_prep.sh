#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKFLOW="${REPO_ROOT}/docs/workflows/fmt2-r630-rocky10-kolla-node-prep.json"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

test -f "${WORKFLOW}"

python3 - "${WORKFLOW}" << 'PY'
import json
import sys
from pathlib import Path

workflow = Path(sys.argv[1])
payload = json.loads(workflow.read_text(encoding="utf-8"))

if payload.get("kind") != "WorkflowManifest":
    raise SystemExit("workflow kind must be WorkflowManifest")

stage_ids = {stage["id"] for stage in payload.get("stages", [])}
required = {
    "rocky10-install-contract",
    "kolla-network-contract",
    "base-services-contract",
    "read-only-kolla-preflight",
    "node-prep-closeout-report",
}
missing = required - stage_ids
if missing:
    raise SystemExit(f"missing required stages: {sorted(missing)}")
PY

assert_file_contains "${WORKFLOW}" 'Rocky Linux 10'
assert_file_contains "${WORKFLOW}" 'OS mirror only'
assert_file_contains "${WORKFLOW}" 'preserve IDSDM EFI handoff'
assert_file_contains "${WORKFLOW}" 'exclude SAS hot-swap bays'
assert_file_contains "${WORKFLOW}" 'bond0'
assert_file_contains "${WORKFLOW}" 'bond1'
assert_file_contains "${WORKFLOW}" 'eno1+eno2'
assert_file_contains "${WORKFLOW}" 'eno3+eno4'
assert_file_contains "${WORKFLOW}" 'Neutron external/provider traffic with no host IP'
assert_file_contains "${WORKFLOW}" 'ConnectX ports independent'
assert_file_contains "${WORKFLOW}" 'RoCEv2 validation'
assert_file_contains "${WORKFLOW}" 'podman'
assert_file_contains "${WORKFLOW}" 'Kolla host dependencies'
assert_file_contains "${WORKFLOW}" 'chrony'
assert_file_contains "${WORKFLOW}" 'RFC1918 time sources'
assert_file_contains "${WORKFLOW}" 'sssd'
assert_file_contains "${WORKFLOW}" 'FreeIPA'
assert_file_contains "${WORKFLOW}" 'node_exporter'
assert_file_contains "${WORKFLOW}" 'Check_MK agent'
assert_file_contains "${WORKFLOW}" 'rsyslog'
assert_file_contains "${WORKFLOW}" 'RFC1918 syslog VIP'
assert_file_contains "${WORKFLOW}" 'RFC1918 internal CA'
assert_file_contains "${WORKFLOW}" 'ansible-playbook'
assert_file_contains "${WORKFLOW}" 'inventories/fmt2-openstack-kolla/hosts.yml'
assert_file_contains "${WORKFLOW}" 'playbooks/fmt2-kolla-rocky10-preflight.yml'
assert_file_contains "${WORKFLOW}" 'kvm_sfo200_pri_9922,kvm_sfo200_sec_9923'
assert_file_contains "${WORKFLOW}" 'expectedExitCodes'
assert_file_contains "${WORKFLOW}" '2'

printf 'PASS: %s\n' "$(basename "$0")"
