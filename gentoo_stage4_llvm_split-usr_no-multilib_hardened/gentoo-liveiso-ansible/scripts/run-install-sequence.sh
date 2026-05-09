#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

inventory="${INVENTORY:-${ANSIBLE_ROOT}/inventories/examples/hosts.yml}"
playbook="${PLAYBOOK:-${ANSIBLE_ROOT}/playbooks/install.yml}"
sequence="${INSTALL_SEQUENCE:-full-default}"
limit_target="${LIMIT_TARGET:-}"
stdout_callback="${ANSIBLE_STDOUT_CALLBACK:-yaml}"
ansible_ssh_args="${ANSIBLE_SSH_ARGS:-}"
control_flow_dir="${ANSIBLE_CONTROL_FLOW_DIR:-/tmp/ansible-control-flow}"
control_flow_path="${ANSIBLE_CONTROL_FLOW_PATH:-}"
debug_checkpoints="${INSTALL_DEBUG_CHECKPOINTS:-false}"
dry_run=0

extra_vars=()

usage() {
  cat << 'EOF'
Usage: run-install-sequence.sh [options]

Options:
  --inventory PATH            Inventory file to use.
  --playbook PATH             Playbook path to execute.
  --sequence NAME             install_sequence enum value.
  --limit TARGET              Optional Ansible host limit.
  --control-flow-path PATH    Explicit JSONL control-flow output path.
  --control-flow-dir PATH     Directory for generated control-flow logs.
  --ssh-args VALUE            Explicit ANSIBLE_SSH_ARGS value.
  --stdout-callback VALUE     ANSIBLE_STDOUT_CALLBACK value.
  --checkpoint                Enable install_debug_checkpoints=true.
  --no-checkpoint             Disable install_debug_checkpoints.
  --extra-vars VALUE          Additional -e payload. May be repeated.
  --dry-run                   Print the resolved environment and command.
  --help                      Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --inventory)
    inventory="$2"
    shift 2
    ;;
  --playbook)
    playbook="$2"
    shift 2
    ;;
  --sequence)
    sequence="$2"
    shift 2
    ;;
  --limit)
    limit_target="$2"
    shift 2
    ;;
  --control-flow-path)
    control_flow_path="$2"
    shift 2
    ;;
  --control-flow-dir)
    control_flow_dir="$2"
    shift 2
    ;;
  --ssh-args)
    ansible_ssh_args="$2"
    shift 2
    ;;
  --stdout-callback)
    stdout_callback="$2"
    shift 2
    ;;
  --checkpoint)
    debug_checkpoints='true'
    shift
    ;;
  --no-checkpoint)
    debug_checkpoints='false'
    shift
    ;;
  --extra-vars)
    extra_vars+=("$2")
    shift 2
    ;;
  --dry-run)
    dry_run=1
    shift
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    printf 'ERROR: Unknown argument: %s\n' "$1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

if [[ -z "${control_flow_path}" ]]; then
  timestamp="$(date +'%Y-%m%d-%H%M_%s.UTC%z')"
  mkdir -p "${control_flow_dir}"
  control_flow_path="${control_flow_dir}/install.${sequence}.${timestamp}.jsonl"
else
  mkdir -p "$(dirname "${control_flow_path}")"
fi

cmd=(
  ansible-playbook
  -i "${inventory}"
  "${playbook}"
  -e "install_sequence=${sequence}"
  -e "install_debug_checkpoints=${debug_checkpoints}"
)

if [[ -n "${limit_target}" ]]; then
  cmd+=(-l "${limit_target}")
fi

for extra_var in "${extra_vars[@]}"; do
  cmd+=(-e "${extra_var}")
done

printf 'Sequence: %s\n' "${sequence}"
printf 'Playbook: %s\n' "${playbook}"
printf 'Inventory: %s\n' "${inventory}"
printf 'Control flow pipeline: %s\n' "${control_flow_path}"
printf 'Watch command: python3 %s/scripts/watch-control-flow.py --path %s --follow\n' "${ANSIBLE_ROOT}" "${control_flow_path}"

if [[ "${dry_run}" -eq 1 ]]; then
  printf 'ANSIBLE_STDOUT_CALLBACK=%s\n' "${stdout_callback}"
  printf 'ANSIBLE_SSH_ARGS=%s\n' "${ansible_ssh_args}"
  printf 'ANSIBLE_CONTROL_FLOW_ENABLED=true\n'
  printf 'ANSIBLE_CONTROL_FLOW_PATH=%s\n' "${control_flow_path}"
  printf 'Command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  exit 0
fi

env \
  ANSIBLE_STDOUT_CALLBACK="${stdout_callback}" \
  ANSIBLE_SSH_ARGS="${ansible_ssh_args}" \
  ANSIBLE_CONTROL_FLOW_ENABLED=true \
  ANSIBLE_CONTROL_FLOW_PATH="${control_flow_path}" \
  "${cmd[@]}"
