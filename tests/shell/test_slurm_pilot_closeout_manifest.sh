#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${REPO_ROOT}/docs/closeouts/HPC-002-slurm-pilot-closeout.yml"
DOC="${REPO_ROOT}/docs/SLURM-PILOT-BRINGUP.md"
WIKI="${REPO_ROOT}/docs/wiki/SLURM-Pilot-Bringup.md"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"

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

test -f "${MANIFEST}" || fail "missing closeout manifest ${MANIFEST}"

python3 - "${MANIFEST}" << 'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    raise SystemExit(f"PyYAML missing: {exc}") from exc

manifest = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))

assert manifest["roadmap_id"] == "HPC-002"
assert manifest["issue"] == 116
assert manifest["closeout_status"] == "ready-to-close"
assert manifest["pilot_scope"] == "non-production"
assert manifest["controller"]["hostname"] == "sched-sun99-slurmctl-099071.rfc1918.host"
assert manifest["controller"]["ip"] == "172.16.99.71"
assert manifest["worker"]["hostname"] == "sched-sun99-slurmwkr-099072.rfc1918.host"
assert manifest["worker"]["ip"] == "172.16.99.72"

partitions = manifest["validated_partitions"]
assert set(partitions) == {"build", "validation", "gpu-test", "rdma-test"}
assert partitions["rdma-test"]["state"] == "drained"

services = manifest["runtime_services"]
assert services["controller"] == ["munged", "mariadb", "slurmdbd", "slurmctld"]
assert services["worker"] == ["munged", "slurmd"]

accepted = {gate["id"]: gate for gate in manifest["acceptance_gates"]}
required = {
    "render-slurm-conf",
    "render-slurmdbd-conf",
    "render-cgroup-conf",
    "controller-services-openrc",
    "worker-services-openrc",
    "noop-job",
    "e2et-validator-job",
    "portage-binpkg-build-job-gated",
}
missing = required - set(accepted)
assert not missing, sorted(missing)
for gate in required:
    assert accepted[gate]["status"] == "passed"
    assert accepted[gate]["evidence"]

followups = {item["issue"] for item in manifest["follow_up_issues"]}
assert {118, 130}.issubset(followups)
for item in manifest["follow_up_issues"]:
    assert item["not_blocking_hpc_002_closeout"] is True

guardrails = manifest["guardrails"]
assert guardrails["x12again_dependency"] == "not-required-for-pilot"
assert guardrails["rdma_test_partition"] == "drained-until-fabric-e2et-passes"
assert guardrails["artifact_publication"] == "blocked-until-job-validation-passes"
PY

assert_file_contains "${MANIFEST}" 'srun --nodes=1 --ntasks=1 hostname'
assert_file_contains "${MANIFEST}" 'sbatch --wrap="hostname; date -u"'
assert_file_contains "${MANIFEST}" 'bash tests/shell/run-tests.sh'
assert_file_contains "${MANIFEST}" 'Prometheus'
assert_file_contains "${MANIFEST}" 'VictoriaMetrics'
assert_file_contains "${MANIFEST}" 'Elasticsearch'
assert_file_contains "${MANIFEST}" 'X12AGAIN'
assert_file_contains "${DOC}" 'HPC-002 Closeout Manifest'
assert_file_contains "${WIKI}" 'HPC-002 Closeout Manifest'
assert_file_contains "${RUN_TESTS}" 'test_slurm_pilot_closeout_manifest.sh'

printf 'PASS: %s\n' "$(basename "$0")"
