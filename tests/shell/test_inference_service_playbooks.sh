#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PLAYBOOK_DIR="${ANSIBLE_ROOT}/playbooks"
ROLE_DIR="${ANSIBLE_ROOT}/roles/inference_service"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -q -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2

  if grep -Eq -- "${pattern}" "${file}"; then
    fail "expected ${file} not to contain ${pattern}"
  fi
}

declare -A backend_hosts=(
  [ollama]=ollama_servers
  [vllm]=vllm_servers
  [sglang]=sglang_servers
  ["open-webui"]=open_webui_servers
)

for backend in "${!backend_hosts[@]}"; do
  playbook="${PLAYBOOK_DIR}/${backend}.yml"
  hosts="${backend_hosts[${backend}]}"

  assert_file_contains "${playbook}" "hosts: ${hosts}"
  assert_file_contains "${playbook}" "gather_facts: true"
  assert_file_contains "${playbook}" "become: true"
  assert_file_contains "${playbook}" "role: inference_service"
  assert_file_contains "${playbook}" "inference_service_backend: ${backend}"
  assert_file_contains "${playbook}" "inference_service_name: ${backend}"
  assert_file_not_contains "${playbook}" 'ansible\.builtin\.(shell|command)'
  assert_file_not_contains "${playbook}" '(^|[^[:alnum:]_-])(podman|docker)([^[:alnum:]_-]|$)'
done

ANSIBLE_ROOT="${ANSIBLE_ROOT}" python3 - << 'PY'
import os
from pathlib import Path

import yaml

ansible_root = Path(os.environ["ANSIBLE_ROOT"])
playbooks = {
    "ollama": "ollama_servers",
    "vllm": "vllm_servers",
    "sglang": "sglang_servers",
    "open-webui": "open_webui_servers",
}

for backend, expected_hosts in sorted(playbooks.items()):
    path = ansible_root / "playbooks" / f"{backend}.yml"
    documents = list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
    if len(documents) != 1:
        raise SystemExit(f"{path} must contain exactly one YAML document")
    plays = documents[0]
    if not isinstance(plays, list) or len(plays) != 1:
        raise SystemExit(f"{path} must contain exactly one play")
    play = plays[0]
    if play.get("hosts") != expected_hosts:
        raise SystemExit(f"{path} hosts should be {expected_hosts!r}")
    if play.get("gather_facts") is not True:
        raise SystemExit(f"{path} must gather facts for OS/service-manager detection")
    if play.get("become") is not True:
        raise SystemExit(f"{path} must use privilege escalation for service installation")
    roles = play.get("roles")
    if not isinstance(roles, list) or len(roles) != 1:
        raise SystemExit(f"{path} must call exactly one shared role")
    role = roles[0]
    if not isinstance(role, dict) or role.get("role") != "inference_service":
        raise SystemExit(f"{path} must call role inference_service")
    vars_block = play.get("vars")
    if not isinstance(vars_block, dict):
        raise SystemExit(f"{path} must define common role variables")
    if vars_block.get("inference_service_backend") != backend:
        raise SystemExit(f"{path} backend variable drifted from filename")
    if vars_block.get("inference_service_name") != backend:
        raise SystemExit(f"{path} service-name variable drifted from filename")
    unexpected_sections = {"tasks", "pre_tasks", "post_tasks", "handlers"} & set(play)
    if unexpected_sections:
        raise SystemExit(
            f"{path} should stay thin; unexpected sections: {sorted(unexpected_sections)}"
        )
PY

if command -v ansible-playbook > /dev/null 2>&1; then
  tmp_inventory="$(mktemp --suffix=.yml)"
  tmp_role_root="$(mktemp -d)"
  trap 'rm -f "${tmp_inventory}"; rm -rf "${tmp_role_root}"' EXIT
  cat > "${tmp_inventory}" << 'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
  children:
    ollama_servers:
      hosts:
        localhost:
    vllm_servers:
      hosts:
        localhost:
    sglang_servers:
      hosts:
        localhost:
    open_webui_servers:
      hosts:
        localhost:
EOF

  if [[ -d "${ROLE_DIR}" ]]; then
    roles_path="${ANSIBLE_ROOT}/roles"
  else
    mkdir -p "${tmp_role_root}/roles/inference_service/tasks"
    printf -- '---\n[]\n' > "${tmp_role_root}/roles/inference_service/tasks/main.yml"
    roles_path="${tmp_role_root}/roles:${ANSIBLE_ROOT}/roles"
  fi

  for backend in "${!backend_hosts[@]}"; do
    ANSIBLE_ROLES_PATH="${roles_path}" ansible-playbook \
      --syntax-check \
      -i "${tmp_inventory}" \
      "${PLAYBOOK_DIR}/${backend}.yml" > /dev/null
  done
fi

assert_file_contains "${SCRIPT_DIR}/run-tests.sh" 'test_inference_service_playbooks.sh'

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
