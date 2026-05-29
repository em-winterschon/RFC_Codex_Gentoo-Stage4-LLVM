#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKFLOW="${REPO_ROOT}/docs/workflows/fmt2-kolla-deployer-vm.json"

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
if not payload.get("stages"):
    raise SystemExit("workflow must define stages")

stage_ids = {stage["id"] for stage in payload["stages"]}
required = {
    "ter-storage-preflight",
    "deployer-vm-definition",
    "deployer-vm-bootstrap",
    "kolla-ansible-venv-install",
    "kolla-etc-bootstrap",
}
missing = required - stage_ids
if missing:
    raise SystemExit(f"missing required stages: {sorted(missing)}")
PY

assert_file_contains "${WORKFLOW}" 'ops-fmt2-kolla-deployer-9928'
assert_file_contains "${WORKFLOW}" '10.200.99.28'
assert_file_contains "${WORKFLOW}" 'kvm-sfo200-ter-9924'
assert_file_contains "${WORKFLOW}" 'dstore/libvirt/images'
assert_file_contains "${WORKFLOW}" '/srv/libvirt/images'
assert_file_contains "${WORKFLOW}" 'Rocky Linux 10'
assert_file_contains "${WORKFLOW}" 'python3-devel'
assert_file_contains "${WORKFLOW}" 'python3-venv'
assert_file_contains "${WORKFLOW}" 'libffi-devel'
assert_file_contains "${WORKFLOW}" 'openssl-devel'
assert_file_contains "${WORKFLOW}" 'kolla-ansible'
assert_file_contains "${WORKFLOW}" 'kolla-ansible==2026.1.*'
assert_file_contains "${WORKFLOW}" 'podman'
assert_file_contains "${WORKFLOW}" '"container_engine": "podman"'
assert_file_contains "${WORKFLOW}" '"base_distro": "rocky"'
assert_file_contains "${WORKFLOW}" '"openstack_release": "2026.1"'
assert_file_contains "${WORKFLOW}" 'virsh pool-info dstore-images'
assert_file_contains "${WORKFLOW}" 'zfs list dstore/libvirt/images'
assert_file_contains "${WORKFLOW}" '/opt/kolla-ansible-2026.1'
assert_file_contains "${WORKFLOW}" '/etc/kolla'
assert_file_contains "${WORKFLOW}" 'globals.yml'
assert_file_contains "${WORKFLOW}" 'passwords.yml'
assert_file_contains "${WORKFLOW}" 'do not write deployer VM disks to the OS RAID1 mirror'

printf 'PASS: %s\n' "$(basename "$0")"
