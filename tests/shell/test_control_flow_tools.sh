#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

python3 -m py_compile \
  "${ANSIBLE_ROOT}/callback_plugins/control_flow.py" \
  "${ANSIBLE_ROOT}/scripts/watch-control-flow.py"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

dry_run_output="$(
  bash "${ANSIBLE_ROOT}/scripts/run-install-sequence.sh" \
    --inventory "${ANSIBLE_ROOT}/inventories/vm-stage4/hosts.yml" \
    --limit stage4-vm \
    --sequence repair-boot \
    --checkpoint \
    --control-flow-path "${tmp_dir}/repair-boot.jsonl" \
    --dry-run
)"

assert_contains "${dry_run_output}" 'Sequence: repair-boot'
assert_contains "${dry_run_output}" "Control flow pipeline: ${tmp_dir}/repair-boot.jsonl"
assert_contains "${dry_run_output}" 'install_sequence=repair-boot'
assert_contains "${dry_run_output}" 'install_debug_checkpoints=true'
assert_contains "${dry_run_output}" 'watch-control-flow.py --path'

cat > "${tmp_dir}/events.jsonl" << 'EOF'
{"event":"playbook_start","play":"install","task":"-","host":"-","ts":"2026-04-24T20:00:00Z"}
{"event":"task_ok","play":"install","task":"Checkpoint start | full-default | preflight","host":"stage4-vm","ts":"2026-04-24T20:00:01Z","checkpoint":{"checkpoint":"start","stage_id":"preflight"}}
EOF

watch_output="$(
  python3 "${ANSIBLE_ROOT}/scripts/watch-control-flow.py" --path "${tmp_dir}/events.jsonl"
)"

assert_contains "${watch_output}" '[playbook_start]'
assert_contains "${watch_output}" 'stage=preflight phase=start'

printf 'PASS: %s\n' "$(basename "$0")"
