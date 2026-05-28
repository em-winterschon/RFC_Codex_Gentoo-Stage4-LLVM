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

usage() {
  cat <<USAGE
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
    --inventory) INVENTORY="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --dependency) DEPENDENCY="$2"; shift 2 ;;
    --audit-dir) AUDIT_DIR="$2"; shift 2 ;;
    --eligible-hosts-file) ELIGIBLE_HOSTS_FILE="$2"; shift 2 ;;
    --shard-size) SHARD_SIZE="$2"; shift 2 ;;
    --max-parallel-shards) MAX_PARALLEL_SHARDS="$2"; shift 2 ;;
    --rollback-source) ROLLBACK_SOURCE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${MODE}" in
  audit|apply|verify|rollback) ;;
  *) printf 'unknown mode: %s\n' "${MODE}" >&2; usage >&2; exit 2 ;;
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
  cat <<EXPORTS
export ANSIBLE_CONFIG='${ANSIBLE_ROOT}/ansible.cfg'
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
  python3 - "${AUDIT_DIR}" "${output}" <<'PY'
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

build_shards() {
  local hosts_file=$1
  local shard_dir=$2
  python3 - "${hosts_file}" "${shard_dir}" "${SHARD_SIZE}" <<'PY'
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
    ELIGIBLE_HOSTS_FILE="${ELIGIBLE_HOSTS_FILE:-${LOG_DIR}/eligible-hosts.txt}"
    if [[ ! -s "${ELIGIBLE_HOSTS_FILE}" ]]; then
      build_eligible_hosts_file "${ELIGIBLE_HOSTS_FILE}"
    fi
    SHARD_DIR="${LOG_DIR}/shards"
    SHARD_COUNT="$(build_shards "${ELIGIBLE_HOSTS_FILE}" "${SHARD_DIR}")"
    if [[ "${SHARD_COUNT}" == 0 ]]; then
      printf 'No eligible hosts to apply. Audit dir: %s\n' "${AUDIT_DIR}"
      exit 0
    fi
    LAST_INDEX=$((SHARD_COUNT - 1))
    read -r -d '' WRAP <<'WRAP' || true
set -euo pipefail
export ANSIBLE_CONFIG="${ANSIBLE_ROOT}/ansible.cfg"
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
