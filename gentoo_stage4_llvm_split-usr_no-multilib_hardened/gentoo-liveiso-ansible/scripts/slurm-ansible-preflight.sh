#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
DEPENDENCY=""
SLURM_NODES=""
SLURM_NODE_FILE=""
DRY_RUN=0
CONTROL_FLOW_DIR="/tmp/ansible-control-flow"
LOG_DIR=""
CACHE_CONNECTION="localhost:6379:0:"
CACHE_PLUGIN="community.general.redis"

usage() {
  cat << USAGE
Usage: $(basename "$0") [options]

Options:
  --ansible-root PATH           Ansible project root (default: ${ANSIBLE_ROOT})
  --inventory PATH              Ansible inventory path (default: ${INVENTORY})
  --run-id ID                   Preflight run id (default: UTC timestamp)
  --dependency SPEC             Slurm dependency, for example afterok:<jobid>
  --slurm-nodes SPEC            Slurm node list expression; default is every sinfo node
  --slurm-node-file PATH        File containing one Slurm node name per line
  --control-flow-dir PATH       Artifact root (default: ${CONTROL_FLOW_DIR})
  --cache-connection SPEC       Redis fact cache connection (default: ${CACHE_CONNECTION})
  --dry-run                     Print sbatch command instead of submitting
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --ansible-root)
    ANSIBLE_ROOT="$2"
    shift 2
    ;;
  --inventory)
    INVENTORY="$2"
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
  --slurm-nodes)
    SLURM_NODES="$2"
    shift 2
    ;;
  --slurm-node-file)
    SLURM_NODE_FILE="$2"
    shift 2
    ;;
  --control-flow-dir)
    CONTROL_FLOW_DIR="$2"
    shift 2
    ;;
  --cache-connection)
    CACHE_CONNECTION="$2"
    shift 2
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

LOG_DIR="${CONTROL_FLOW_DIR}/slurm-ansible-preflight/${RUN_ID}"
mkdir -p "${LOG_DIR}"

expand_slurm_nodes() {
  if [[ -n "${SLURM_NODE_FILE}" ]]; then
    sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "${SLURM_NODE_FILE}"
    return 0
  fi

  if [[ -n "${SLURM_NODES}" ]]; then
    if command -v scontrol > /dev/null 2>&1; then
      scontrol show hostnames "${SLURM_NODES}"
    else
      tr ',' '\n' <<< "${SLURM_NODES}"
    fi
    return 0
  fi

  if [[ "${DRY_RUN}" == 1 ]]; then
    printf '%s\n' "ALL_SLURM_NODES_FROM_SINFO"
    return 0
  fi

  command -v sinfo > /dev/null
  sinfo -h -N -o '%N'
}

mapfile -t PREFLIGHT_NODES < <(expand_slurm_nodes | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | awk 'NF' | sort -u)
if [[ "${#PREFLIGHT_NODES[@]}" -eq 0 ]]; then
  printf 'no Slurm nodes found for Ansible preflight\n' >&2
  exit 1
fi

sanitize_node_for_path() {
  tr -c '[:alnum:]_.-' '_' <<< "$1" | sed 's/_$//'
}

submit_sbatch() {
  if [[ "${DRY_RUN}" == 1 ]]; then
    printf 'DRY-RUN sbatch'
    printf ' %q' "$@"
    printf '\n'
  else
    sbatch "$@"
  fi
}

read -r -d '' WRAP << 'WRAP' || true
set -euo pipefail
export ANSIBLE_CONFIG='${ANSIBLE_ROOT}/ansible.cfg'
export ANSIBLE_STDOUT_CALLBACK='default'
export ANSIBLE_CACHE_PLUGIN=community.general.redis
export ANSIBLE_CACHE_PLUGIN_CONNECTION='${CACHE_CONNECTION}'
export ANSIBLE_CONTROL_FLOW_ENABLED=true
export ANSIBLE_CONTROL_FLOW_DIR='${CONTROL_FLOW_DIR}'
cd '${ANSIBLE_ROOT}'

command -v python3 >/dev/null
command -v ansible-playbook >/dev/null
command -v ansible-inventory >/dev/null
command -v ansible-galaxy >/dev/null
command -v ansible-doc >/dev/null
command -v redis-cli >/dev/null

python3 - <<'PY'
import importlib
for module in ('redis', 'yaml'):
    importlib.import_module(module)
PY

redis-cli -h localhost -p 6379 ping | grep -q PONG
ansible-doc -t cache community.general.redis >/dev/null

python3 - requirements.yml collections/requirements.yml <<'PY' | while IFS= read -r collection; do
import sys
from pathlib import Path
import yaml
seen = set()
for raw in sys.argv[1:]:
    path = Path(raw)
    if not path.exists():
        continue
    payload = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
    for item in payload.get('collections', []) or []:
        name = item.get('name') if isinstance(item, dict) else item
        if name and name not in seen:
            seen.add(str(name))
            print(name)
PY
  ansible-galaxy collection list "${collection}" | grep -Fq "${collection}"
done

find playbooks -maxdepth 1 -type f -name '*.yml' -print0 | sort -z | while IFS= read -r -d '' playbook; do
  ansible-playbook --syntax-check -i '${INVENTORY}' "${playbook}" >/dev/null
done
WRAP

WRAP="${WRAP//'${ANSIBLE_ROOT}'/${ANSIBLE_ROOT}}"
WRAP="${WRAP//'${INVENTORY}'/${INVENTORY}}"
WRAP="${WRAP//'${CACHE_CONNECTION}'/${CACHE_CONNECTION}}"
WRAP="${WRAP//'${CONTROL_FLOW_DIR}'/${CONTROL_FLOW_DIR}}"

for node in "${PREFLIGHT_NODES[@]}"; do
  safe_node="$(sanitize_node_for_path "${node}")"
  args=(--job-name "ansible-preflight-${RUN_ID}-${safe_node}" --nodes 1 --ntasks 1 --nodelist "${node}" --output "${LOG_DIR}/preflight.${safe_node}.%j.out" --error "${LOG_DIR}/preflight.${safe_node}.%j.err")
  if [[ -n "${DEPENDENCY}" ]]; then
    args+=(--dependency "${DEPENDENCY}")
  fi
  args+=(--wrap "${WRAP}")
  submit_sbatch "${args[@]}"
done
