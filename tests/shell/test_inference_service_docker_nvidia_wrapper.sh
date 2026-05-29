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

assert_contains() {
  local file=$1
  local pattern=$2

  grep -Eq -- "${pattern}" "${file}" ||
    fail "expected ${file} to contain ${pattern}"
}

assert_not_contains() {
  local file=$1
  local pattern=$2

  if grep -Eq -- "${pattern}" "${file}"; then
    fail "expected ${file} not to contain ${pattern}"
  fi
}

command -v ansible-playbook > /dev/null 2>&1 ||
  fail "ansible-playbook is required to render inference service wrappers"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

render_playbook="${tmpdir}/render-inference-wrapper.yml"
cat > "${render_playbook}" << 'EOF'
---
- name: Render inference service wrapper variants
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    role_dir: "{{ lookup('env', 'ROLE_DIR') }}"
    output_dir: "{{ lookup('env', 'OUTPUT_DIR') }}"
    ansible_python_interpreter: /usr/bin/python3
  tasks:
    - name: Load inference service defaults
      ansible.builtin.include_vars:
        file: "{{ role_dir }}/defaults/main.yml"

    - name: Select Ollama definition and common runtime facts
      ansible.builtin.set_fact:
        inference_service: >-
          {{ (inference_service_definitions
            | selectattr('name', 'equalto', 'ollama') | list | first)
            | combine({'accelerator': 'nvidia'}, recursive=True) }}
        resolved_inference_service_architecture: aarch64
        resolved_inference_service_accelerator: nvidia
        inference_service_config_dir: /etc/inference-services
        inference_service_network: host

    - name: Select Docker NVIDIA runtime
      ansible.builtin.set_fact:
        inference_service_container_engine: docker
        inference_service_allow_docker_exception: true

    - name: Render Docker NVIDIA wrapper
      ansible.builtin.template:
        src: "{{ role_dir }}/templates/inference-service-run.sh.j2"
        dest: "{{ output_dir }}/docker-nvidia-run.sh"

    - name: Select Podman NVIDIA runtime
      ansible.builtin.set_fact:
        inference_service_container_engine: podman

    - name: Render Podman NVIDIA wrapper
      ansible.builtin.template:
        src: "{{ role_dir }}/templates/inference-service-run.sh.j2"
        dest: "{{ output_dir }}/podman-nvidia-run.sh"
EOF

ROLE_DIR="${ROLE_DIR}" OUTPUT_DIR="${tmpdir}" ansible-playbook \
  -i localhost, \
  "${render_playbook}" > /dev/null

docker_wrapper="${tmpdir}/docker-nvidia-run.sh"
podman_wrapper="${tmpdir}/podman-nvidia-run.sh"

assert_contains "${docker_wrapper}" 'exec docker run'
assert_contains "${docker_wrapper}" '^[[:space:]]+--gpus[[:space:]]+all[[:space:]]+\\$'
assert_not_contains "${docker_wrapper}" 'nvidia\.com/gpu=all'

assert_contains "${podman_wrapper}" 'exec podman run'
assert_contains "${podman_wrapper}" '^[[:space:]]+--device[[:space:]]+nvidia\.com/gpu=all[[:space:]]+\\$'

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
