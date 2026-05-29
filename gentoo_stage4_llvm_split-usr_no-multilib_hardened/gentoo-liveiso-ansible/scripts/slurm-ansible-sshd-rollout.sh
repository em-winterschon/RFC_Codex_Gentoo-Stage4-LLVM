#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
LIMIT=""
DEPENDENCY=""
DRY_RUN=0
SHARD_SIZE=10
MAX_PARALLEL_SHARDS=4
AUDIT_DIR=""
ELIGIBLE_HOSTS_FILE=""
ROLLBACK_SOURCE=""
CACHE_CONNECTION="localhost:6379:0:"
CACHE_PLUGIN="community.general.redis"
CONTROL_FLOW_DIR="/tmp/ansible-control-flow"
PREFLIGHT_SCRIPT="${SCRIPT_DIR}/slurm-ansible-preflight.sh"
SKIP_PREFLIGHT=0

usage() {
  cat << USAGE
Usage: $(basename "$0") <audit|apply|verify|rollback> [options]

Options:
  --inventory PATH              Ansible inventory path (default: ${INVENTORY})
  --limit PATTERN               Optional Ansible --limit pattern
  --run-id ID                   Rollout run id (default: UTC timestamp)
  --dependency SPEC             Slurm dependency, for example afterok:<jobid>
  --audit-dir PATH              Audit artifact dir (default: /tmp/ansible-control-flow/sshd-baseline/<run-id>)
  --eligible-hosts-file PATH    Apply host list file; otherwise derived from audit JSON records
  --shard-size N                Hosts per apply array task (default: ${SHARD_SIZE})
  --max-parallel-shards N       Slurm array throttle (default: ${MAX_PARALLEL_SHARDS})
  --rollback-source PATH        Host-local backup path for rollback mode
  --skip-preflight              Do not submit the Slurm Ansible dependency preflight
  --dry-run                     Print sbatch commands instead of submitting
USAGE
}

MODE="${1:-}"
if [[ -z "${MODE}" || "${MODE}" == "-h" || "${MODE}" == "--help" ]]; then
  usage
  exit 0
fi
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
  --inventory)
    INVENTORY="$2"
    shift 2
    ;;
  --limit)
    LIMIT="$2"
    shift 2
    ;;
  --run-id)
    RUN_ID="$2"
    shift 2
    ;;
  --dependency)
    DEPENDENCY="$2"
    shift 2
    ;;
  --audit-dir)
    AUDIT_DIR="$2"
    shift 2
    ;;
  --eligible-hosts-file)
    ELIGIBLE_HOSTS_FILE="$2"
    shift 2
    ;;
  --shard-size)
    SHARD_SIZE="$2"
    shift 2
    ;;
  --max-parallel-shards)
    MAX_PARALLEL_SHARDS="$2"
    shift 2
    ;;
  --rollback-source)
    ROLLBACK_SOURCE="$2"
    shift 2
    ;;
  --skip-preflight)
    SKIP_PREFLIGHT=1
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'unknown option: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

case "${MODE}" in
audit | apply | verify | rollback) ;;
*)
  printf 'unknown mode: %s\n' "${MODE}" >&2
  usage >&2
  exit 2
  ;;
esac

AUDIT_DIR="${AUDIT_DIR:-${CONTROL_FLOW_DIR}/sshd-baseline/${RUN_ID}}"
LOG_DIR="${CONTROL_FLOW_DIR}/sshd-baseline-slurm/${RUN_ID}"
mkdir -p "${LOG_DIR}"

submit_sbatch() {
  if [[ "${DRY_RUN}" == 1 ]]; then
    printf 'DRY-RUN sbatch'
    printf ' %q' "$@"
    printf '\n'
  else
    sbatch "$@"
  fi
}

base_exports() {
  cat << EXPORTS
export ANSIBLE_CONFIG='${ANSIBLE_ROOT}/ansible.cfg'
export ANSIBLE_STDOUT_CALLBACK='default'
export ANSIBLE_CACHE_PLUGIN='${CACHE_PLUGIN}'
export ANSIBLE_CACHE_PLUGIN_CONNECTION='${CACHE_CONNECTION}'
export ANSIBLE_CONTROL_FLOW_ENABLED=true
export ANSIBLE_CONTROL_FLOW_DIR='${CONTROL_FLOW_DIR}'
export SSHD_BASELINE_RUN_ID='${RUN_ID}'
cd '${ANSIBLE_ROOT}'
EXPORTS
}

limit_args() {
  if [[ -n "${LIMIT}" ]]; then
    printf -- " --limit %q" "${LIMIT}"
  fi
}

submit_single_playbook_job() {
  local job_name=$1
  local playbook=$2
  local extra_args=$3
  local wrap
  wrap="$(base_exports)
ansible-playbook -i '${INVENTORY}' '${playbook}'$(limit_args) ${extra_args}"
  local args=(--job-name "${job_name}-${RUN_ID}" --output "${LOG_DIR}/${job_name}.%j.out" --error "${LOG_DIR}/${job_name}.%j.err")
  if [[ -n "${DEPENDENCY}" ]]; then
    args+=(--dependency "${DEPENDENCY}")
  fi
  args+=(--wrap "${wrap}")
  submit_sbatch "${args[@]}"
}

build_eligible_hosts_file() {
  local output=$1
  python3 - "${AUDIT_DIR}" "${output}" << 'PY'
import json
import pathlib
import sys

audit_dir = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
hosts = []
for path in sorted(audit_dir.glob('*.json')):
    try:
        row = json.loads(path.read_text(encoding='utf-8'))
    except Exception as exc:
        print(f"WARN: skipping unreadable audit record {path}: {exc}", file=sys.stderr)
        continue
    if not row.get('managed', True):
        continue
    if row.get('variant') == 'installer_recovery_only':
        continue
    if not row.get('syntax_ok', False):
        continue
    if not row.get('drift', False):
        continue
    host = row.get('host')
    if host:
        hosts.append(str(host))
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text('\n'.join(hosts) + ('\n' if hosts else ''), encoding='utf-8')
print(f"eligible_hosts={len(hosts)} path={out}")
PY
}

build_limit_hosts_file() {
  local output=$1
  python3 - "${INVENTORY}" "${LIMIT}" "${output}" "${ANSIBLE_ROOT}/ansible.cfg" << 'PY'
import json
import os
import pathlib
import subprocess
import sys

inventory = sys.argv[1]
limit = sys.argv[2]
out = pathlib.Path(sys.argv[3])
ansible_config = sys.argv[4]
env = os.environ.copy()
env["ANSIBLE_CONFIG"] = ansible_config
env["ANSIBLE_CACHE_PLUGIN"] = "memory"
payload = json.loads(
    subprocess.check_output(
        ["ansible-inventory", "-i", inventory, "--list", "--limit", limit],
        text=True,
        env=env,
    )
)
hostvars = payload.get("_meta", {}).get("hostvars", {})
if not isinstance(hostvars, dict):
    hostvars = {}
hosts = sorted(str(host) for host in hostvars if str(host).strip())
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(hosts) + ("\n" if hosts else ""), encoding="utf-8")
if not hosts:
    print(f"ERROR: --limit {limit!r} matched zero inventory hosts", file=sys.stderr)
    raise SystemExit(2)
print(f"limit_hosts={len(hosts)} path={out}")
PY
}

filter_hosts_file() {
  local source_file=$1
  local limit_file=$2
  local output=$3
  python3 - "${source_file}" "${limit_file}" "${output}" << 'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
limit = pathlib.Path(sys.argv[2])
out = pathlib.Path(sys.argv[3])
source_hosts = [
    line.strip()
    for line in source.read_text(encoding="utf-8").splitlines()
    if line.strip()
]
limit_hosts = {
    line.strip()
    for line in limit.read_text(encoding="utf-8").splitlines()
    if line.strip()
}
seen = set()
filtered = []
for host in source_hosts:
    if host in limit_hosts and host not in seen:
        seen.add(host)
        filtered.append(host)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(filtered) + ("\n" if filtered else ""), encoding="utf-8")
print(f"eligible_hosts={len(filtered)} path={out} limit_path={limit}")
PY
}

submit_preflight() {
  if [[ "${SKIP_PREFLIGHT}" == 1 ]]; then
    return 0
  fi
  local args=(--ansible-root "${ANSIBLE_ROOT}" --inventory "${INVENTORY}" --run-id "${RUN_ID}" --control-flow-dir "${CONTROL_FLOW_DIR}" --cache-connection "${CACHE_CONNECTION}")
  if [[ -n "${DEPENDENCY}" ]]; then
    args+=(--dependency "${DEPENDENCY}")
  fi
  if [[ "${DRY_RUN}" == 1 ]]; then
    args+=(--dry-run)
    "${PREFLIGHT_SCRIPT}" "${args[@]}"
    return 0
  fi
  local output
  output="$("${PREFLIGHT_SCRIPT}" "${args[@]}")"
  printf '%s\n' "${output}"
  local job_ids
  job_ids="$(awk '/Submitted batch job/ { print $4 }' <<< "${output}" | paste -sd ':' -)"
  if [[ -z "${job_ids}" ]]; then
    printf 'could not parse Slurm preflight job id from: %s\n' "${output}" >&2
    exit 1
  fi
  DEPENDENCY="afterok:${job_ids}"
}

build_shards() {
  local hosts_file=$1
  local shard_dir=$2
  python3 - "${hosts_file}" "${shard_dir}" "${SHARD_SIZE}" << 'PY'
import pathlib
import sys

hosts_file = pathlib.Path(sys.argv[1])
shard_dir = pathlib.Path(sys.argv[2])
size = int(sys.argv[3])
hosts = [line.strip() for line in hosts_file.read_text(encoding='utf-8').splitlines() if line.strip()]
shard_dir.mkdir(parents=True, exist_ok=True)
for old in shard_dir.glob('shard_*.hosts'):
    old.unlink()
for idx in range(0, len(hosts), size):
    shard = hosts[idx:idx + size]
    (shard_dir / f'shard_{idx // size:04d}.hosts').write_text('\n'.join(shard) + '\n', encoding='utf-8')
print((len(hosts) + size - 1) // size if hosts else 0)
PY
}

submit_preflight

case "${MODE}" in
audit)
  mkdir -p "${AUDIT_DIR}"
  submit_single_playbook_job "sshd-audit" "playbooks/sshd-baseline-audit.yml" "-e sshd_baseline_run_id='${RUN_ID}' -e sshd_baseline_report_dir='${AUDIT_DIR}'"
  ;;
verify)
  mkdir -p "${AUDIT_DIR}"
  submit_single_playbook_job "sshd-verify" "playbooks/sshd-baseline-audit.yml" "-e sshd_baseline_run_id='${RUN_ID}' -e sshd_baseline_report_dir='${AUDIT_DIR}'"
  ;;
rollback)
  if [[ -z "${ROLLBACK_SOURCE}" ]]; then
    printf 'rollback mode requires --rollback-source PATH\n' >&2
    exit 2
  fi
  submit_single_playbook_job "sshd-rollback" "playbooks/sshd-baseline-rollback.yml" "-e sshd_baseline_rollback_source='${ROLLBACK_SOURCE}'"
  ;;
apply)
  mkdir -p "${AUDIT_DIR}"
  if [[ -z "${ELIGIBLE_HOSTS_FILE}" ]]; then
    if [[ -n "${LIMIT}" ]]; then
      ELIGIBLE_HOSTS_FILE="${LOG_DIR}/audit-eligible-hosts.unfiltered.txt"
    else
      ELIGIBLE_HOSTS_FILE="${LOG_DIR}/eligible-hosts.txt"
    fi
  fi
  if [[ ! -s "${ELIGIBLE_HOSTS_FILE}" ]]; then
    build_eligible_hosts_file "${ELIGIBLE_HOSTS_FILE}"
  fi

  APPLY_HOSTS_FILE="${ELIGIBLE_HOSTS_FILE}"
  if [[ -n "${LIMIT}" ]]; then
    LIMIT_HOSTS_FILE="${LOG_DIR}/limit-hosts.txt"
    FILTERED_ELIGIBLE_HOSTS_FILE="${LOG_DIR}/eligible-hosts.limit-filtered.txt"
    build_limit_hosts_file "${LIMIT_HOSTS_FILE}"
    filter_hosts_file "${ELIGIBLE_HOSTS_FILE}" "${LIMIT_HOSTS_FILE}" "${FILTERED_ELIGIBLE_HOSTS_FILE}"
    APPLY_HOSTS_FILE="${FILTERED_ELIGIBLE_HOSTS_FILE}"
  fi

  SHARD_DIR="${LOG_DIR}/shards"
  SHARD_COUNT="$(build_shards "${APPLY_HOSTS_FILE}" "${SHARD_DIR}")"
  if [[ "${SHARD_COUNT}" == 0 ]]; then
    printf 'No eligible hosts to apply. Audit dir: %s\n' "${AUDIT_DIR}"
    exit 0
  fi
  LAST_INDEX=$((SHARD_COUNT - 1))
  read -r -d '' WRAP << 'WRAP' || true
set -euo pipefail
export ANSIBLE_CONFIG="${ANSIBLE_ROOT}/ansible.cfg"
export ANSIBLE_STDOUT_CALLBACK="default"
export ANSIBLE_CACHE_PLUGIN="community.general.redis"
export ANSIBLE_CACHE_PLUGIN_CONNECTION="localhost:6379:0:"
export ANSIBLE_CONTROL_FLOW_ENABLED=true
export ANSIBLE_CONTROL_FLOW_DIR="/tmp/ansible-control-flow"
export SSHD_BASELINE_RUN_ID="${RUN_ID}"
SHARD_FILE="${SHARD_DIR}/shard_$(printf '%04d' "${SLURM_ARRAY_TASK_ID}").hosts"
LIMIT_PATTERN="$(paste -sd, "${SHARD_FILE}")"
cd "${ANSIBLE_ROOT}"
ansible-playbook -i "${INVENTORY}" playbooks/sshd-baseline-apply.yml --limit "${LIMIT_PATTERN}" -e sshd_baseline_apply_required=true -e sshd_baseline_run_id="${RUN_ID}"
WRAP
  # Expand selected variables now while preserving Slurm's runtime array id.
  WRAP="${WRAP//'${ANSIBLE_ROOT}'/${ANSIBLE_ROOT}}"
  WRAP="${WRAP//'${RUN_ID}'/${RUN_ID}}"
  WRAP="${WRAP//'${SHARD_DIR}'/${SHARD_DIR}}"
  WRAP="${WRAP//'${INVENTORY}'/${INVENTORY}}"
  local_args=(--job-name "sshd-apply-${RUN_ID}" "--array=0-${LAST_INDEX}%${MAX_PARALLEL_SHARDS}" --output "${LOG_DIR}/sshd-apply.%A.%a.out" --error "${LOG_DIR}/sshd-apply.%A.%a.err")
  if [[ -n "${DEPENDENCY}" ]]; then
    local_args+=(--dependency "${DEPENDENCY}")
  fi
  local_args+=(--wrap "${WRAP}")
  submit_sbatch "${local_args[@]}"
  ;;
esac
