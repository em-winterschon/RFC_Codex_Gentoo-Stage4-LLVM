#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/inference_service"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_grep() {
  local pattern=$1
  local file=$2
  grep -q -- "${pattern}" "${file}" || fail "missing pattern '${pattern}' in ${file}"
}

require_file "${ROLE_DIR}/defaults/main.yml"
require_file "${ROLE_DIR}/tasks/main.yml"
require_file "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_file "${ROLE_DIR}/templates/inference-service.env.j2"
require_file "${ROLE_DIR}/templates/inference-service.systemd.j2"
require_file "${ROLE_DIR}/templates/inference-service.openrc.j2"

require_grep 'inference_service_package_map:' "${ROLE_DIR}/defaults/main.yml"
require_grep 'inference_service_backend:' "${ROLE_DIR}/defaults/main.yml"
require_grep 'inference_service_allow_docker_exception:' "${ROLE_DIR}/defaults/main.yml"
require_grep 'Debian:' "${ROLE_DIR}/defaults/main.yml"
require_grep 'RedHat:' "${ROLE_DIR}/defaults/main.yml"
require_grep 'Gentoo:' "${ROLE_DIR}/defaults/main.yml"
require_grep 'inference_service_accelerator_profiles:' "${ROLE_DIR}/defaults/main.yml"
require_grep 'nvidia.com/gpu=all' "${ROLE_DIR}/defaults/main.yml"
require_grep '/dev/kfd' "${ROLE_DIR}/defaults/main.yml"
require_grep '/dev/dri' "${ROLE_DIR}/defaults/main.yml"
require_grep 'ollama' "${ROLE_DIR}/defaults/main.yml"
require_grep 'vllm' "${ROLE_DIR}/defaults/main.yml"
require_grep 'sglang' "${ROLE_DIR}/defaults/main.yml"
require_grep 'open-webui' "${ROLE_DIR}/defaults/main.yml"
require_grep '/usr/local/libexec/inference-services' "${ROLE_DIR}/defaults/main.yml"
require_grep '/etc/inference-services' "${ROLE_DIR}/defaults/main.yml"
require_grep '/var/lib/inference' "${ROLE_DIR}/defaults/main.yml"
require_grep '/var/log/inference-services' "${ROLE_DIR}/defaults/main.yml"

require_grep 'ansible.builtin.package:' "${ROLE_DIR}/tasks/main.yml"
require_grep 'ansible_service_mgr' "${ROLE_DIR}/tasks/main.yml"
require_grep "selectattr('name', 'equalto', inference_service_backend)" "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference_service_allow_docker_exception' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference-service-run.sh.j2' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference-service.env.j2' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference-service.systemd.j2' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference-service.openrc.j2' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference_service_libexec_dir' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference_service_config_dir' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference_service_state_root' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference_service_log_root' "${ROLE_DIR}/tasks/main.yml"

require_grep 'inference_service_container_engine' "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep "inference_service_container_engine == 'podman'" "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep '--pull' "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep '--env-file' "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep '--device' "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep 'INFERENCE_SERVICE_NAME=' "${ROLE_DIR}/templates/inference-service.env.j2"
require_grep 'ExecStart={{ inference_service_libexec_dir }}/run-' "${ROLE_DIR}/templates/inference-service.systemd.j2"
require_grep 'command="{{ inference_service_libexec_dir }}/run-' "${ROLE_DIR}/templates/inference-service.openrc.j2"
require_grep '#!/sbin/openrc-run' "${ROLE_DIR}/templates/inference-service.openrc.j2"

printf 'PASS: %s\n' "$(basename "$0")"
