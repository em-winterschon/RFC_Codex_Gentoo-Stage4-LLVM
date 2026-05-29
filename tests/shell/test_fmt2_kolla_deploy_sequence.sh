#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKFLOW="${REPO_ROOT}/docs/workflows/fmt2-kolla-deploy-sequence.json"

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
    "generate-passwords",
    "bootstrap-servers",
    "prechecks",
    "validate-config",
    "deploy",
    "post-deploy",
    "api-smoke",
    "instance-smoke",
}
missing = required - stage_ids
if missing:
    raise SystemExit(f"missing required stages: {sorted(missing)}")
PY

assert_file_contains "${WORKFLOW}" 'ops-fmt2-kolla-deployer-9928'
assert_file_contains "${WORKFLOW}" '/opt/kolla-ansible-2026.1/bin/activate'
assert_file_contains "${WORKFLOW}" 'cd /etc/kolla'
assert_file_contains "${WORKFLOW}" 'kolla-genpwd'
assert_file_contains "${WORKFLOW}" 'kolla-ansible -i /etc/kolla/multinode bootstrap-servers'
assert_file_contains "${WORKFLOW}" 'kolla-ansible -i /etc/kolla/multinode prechecks'
assert_file_contains "${WORKFLOW}" 'kolla-ansible -i /etc/kolla/multinode validate-config'
assert_file_contains "${WORKFLOW}" 'kolla-ansible -i /etc/kolla/multinode deploy'
assert_file_contains "${WORKFLOW}" 'kolla-ansible -i /etc/kolla/multinode post-deploy'
assert_file_contains "${WORKFLOW}" 'If prechecks fail, stop and capture'
assert_file_contains "${WORKFLOW}" 'source /etc/kolla/admin-openrc.sh'
assert_file_contains "${WORKFLOW}" 'openstack endpoint list'
assert_file_contains "${WORKFLOW}" 'openstack service list'
assert_file_contains "${WORKFLOW}" 'openstack hypervisor list'
assert_file_contains "${WORKFLOW}" 'openstack network agent list'
assert_file_contains "${WORKFLOW}" 'openstack flavor create --ram 512 --disk 1 --vcpus 1 rfc1918.smoke.tiny'
assert_file_contains "${WORKFLOW}" 'openstack network create rfc1918-smoke-net'
assert_file_contains "${WORKFLOW}" 'openstack subnet create --network rfc1918-smoke-net --subnet-range 192.0.2.0/24 rfc1918-smoke-subnet'
assert_file_contains "${WORKFLOW}" 'openstack server create --flavor rfc1918.smoke.tiny --image cirros --network rfc1918-smoke-net rfc1918-smoke-001'
assert_file_contains "${WORKFLOW}" 'openstack server show rfc1918-smoke-001'
assert_file_contains "${WORKFLOW}" 'Nova, Neutron, libvirt, and Podman logs'

printf 'PASS: %s\n' "$(basename "$0")"
