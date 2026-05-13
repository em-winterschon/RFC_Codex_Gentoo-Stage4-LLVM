#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DOC="${REPO_ROOT}/docs/SLURM-PILOT-BRINGUP.md"
WIKI="${REPO_ROOT}/docs/wiki/SLURM-Pilot-Bringup.md"
PLAN="${REPO_ROOT}/docs/superpowers/plans/2026-05-13-slurm-pilot-control-plane.md"
WORKFLOW="${REPO_ROOT}/docs/workflows/stage5-slurm-pilot-bringup.json"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

for file in "${DOC}" "${WIKI}" "${PLAN}" "${WORKFLOW}"; do
  test -f "${file}"
done

for file in "${DOC}" "${WIKI}" "${PLAN}"; do
  assert_file_contains "${file}" 'sched-sun99-slurmctl-099071'
  assert_file_contains "${file}" '172.16.99.71'
  assert_file_contains "${file}" 'MUNGE'
  assert_file_contains "${file}" 'slurmdbd'
  assert_file_contains "${file}" 'NetBox'
  assert_file_contains "${file}" 'DNS'
  assert_file_contains "${file}" 'Prometheus'
  assert_file_contains "${file}" 'VictoriaMetrics'
  assert_file_contains "${file}" 'Grafana'
  assert_file_contains "${file}" 'rsyslog'
  assert_file_contains "${file}" 'Elasticsearch'
  assert_file_contains "${file}" 'sinfo'
  assert_file_contains "${file}" 'srun hostname'
  assert_file_contains "${file}" 'Project Coherent Flash'
  assert_file_contains "${file}" 'X12AGAIN'
done

assert_file_contains "${DOC}" 'Do not block SLURM on X12AGAIN reimage'
assert_file_contains "${DOC}" 'first worker'
assert_file_contains "${DOC}" 'build'
assert_file_contains "${DOC}" 'validation'
assert_file_contains "${DOC}" 'gpu-test'
assert_file_contains "${DOC}" 'rdma-test'
assert_file_contains "${DOC}" 'Backout'

python3 - "${WORKFLOW}" << 'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
if payload["metadata"]["name"] != "stage5-slurm-pilot-bringup":
    raise SystemExit("unexpected workflow name")

stage_ids = [stage["id"] for stage in payload["stages"]]
required = [
    "preflight-no-x12again-dependency",
    "dns-netbox-preflight",
    "vault-secret-preflight",
    "controller-profile-render",
    "first-worker-profile-render",
    "observability-readiness",
    "slurm-runtime-smoke",
    "project-coherent-flash-model-gate",
]
missing = [stage for stage in required if stage not in stage_ids]
if missing:
    raise SystemExit(f"missing workflow stages: {missing}")

text = json.dumps(payload, sort_keys=True)
for needle in (
    "sched-sun99-slurmctl-099071",
    "172.16.99.71",
    "slurmctld",
    "slurmd",
    "slurmdbd",
    "sinfo",
    "srun hostname",
    "Project Coherent Flash",
):
    if needle not in text:
        raise SystemExit(f"workflow missing {needle}")

print("workflow-ok")
PY

printf 'PASS: %s\n' "$(basename "$0")"
