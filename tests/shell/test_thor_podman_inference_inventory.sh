#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
INVENTORY="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
RUNBOOK="${REPO_ROOT}/docs/THOR-AGX-INFERENCE-READINESS.md"
PLAYBOOK_DOC="${REPO_ROOT}/docs/INFERENCE-SERVICE-PLAYBOOKS.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_fixed() {
  local pattern=$1
  local file=$2
  grep -Fq -- "${pattern}" "${file}" || fail "missing text ${pattern} in ${file}"
}

require_absent_fixed() {
  local pattern=$1
  local file=$2
  if grep -Fq -- "${pattern}" "${file}"; then
    fail "unexpected text ${pattern} in ${file}"
  fi
}

require_file "${INVENTORY}"
require_fixed 'agx_rfc99_bunnydev_099034:' "${INVENTORY}"
require_fixed 'ansible_host: 172.16.99.34' "${INVENTORY}"
require_fixed 'fqdn: agx-rfc99-bunnydev.rfc1918.host' "${INVENTORY}"
require_fixed 'ollama_servers:' "${INVENTORY}"
require_fixed 'open_webui_servers:' "${INVENTORY}"
require_fixed 'inference_service_container_engine: podman' "${INVENTORY}"
require_fixed 'inference_service_accelerator: nvidia' "${INVENTORY}"
require_fixed 'inference_service_manager: systemd' "${INVENTORY}"
require_fixed 'nvidia.com/gpu=all' "${INVENTORY}"
require_absent_fixed 'inference_service_container_engine: docker' "${INVENTORY}"
require_absent_fixed 'inference_service_allow_docker_exception' "${INVENTORY}"

require_file "${RUNBOOK}"
require_fixed 'Podman is installed and validated on Thor.' "${RUNBOOK}"
require_fixed 'nvidia.com/gpu=all' "${RUNBOOK}"
require_fixed '/etc/cdi/nvidia.yaml' "${RUNBOOK}"
require_fixed 'Docker remains masked and inactive.' "${RUNBOOK}"

require_file "${PLAYBOOK_DOC}"
require_fixed 'Thor AGX now uses Podman plus NVIDIA CDI.' "${PLAYBOOK_DOC}"
require_fixed 'inference_service_container_engine: podman' "${PLAYBOOK_DOC}"
require_fixed 'inference_service_accelerator: nvidia' "${PLAYBOOK_DOC}"
require_absent_fixed 'temporary until Podman/CDI is validated' "${PLAYBOOK_DOC}"

printf 'PASS: %s\n' "$(basename "$0")"
