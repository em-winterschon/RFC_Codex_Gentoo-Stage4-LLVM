# Inference Service Role Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the forge2-owned shared Ansible role core for Podman-backed Ollama, vLLM, SGLang, and Open WebUI services.

**Architecture:** Implement one `inference_service` role in the repository's existing Ansible root, `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible`. The role resolves safe defaults plus per-backend overrides, installs platform package prerequisites for Debian, RedHat, and Gentoo families, renders one env file and one Podman wrapper per service, and registers either systemd or OpenRC service definitions based on `ansible_service_mgr`.

**Tech Stack:** Ansible YAML, Jinja2 templates, Bash shell tests, Podman, systemd, OpenRC.

---

## File Structure

- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/defaults/main.yml`
  - Owns role defaults, package maps, backend defaults, accelerator profiles, runtime paths, and service manager policy.
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/tasks/main.yml`
  - Resolves settings, validates contracts, installs packages, creates directories, renders env/wrapper/service files, and enables services.
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/templates/inference-service-run.sh.j2`
  - Renders the Podman run wrapper used by all inference services.
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/templates/inference-service.env.j2`
  - Renders stable per-service environment files under `/etc/inference-services`.
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/templates/inference-service.systemd.j2`
  - Renders one systemd unit per inference service.
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/templates/inference-service.openrc.j2`
  - Renders one OpenRC init script per inference service.
- Create: `tests/shell/test_inference_service_role_core.sh`
  - Standalone forge2-owned role core gate. Forge3 owns `tests/shell/run-tests.sh` and can add this file there during integration.

## Task 1: Failing Role Core Test

**Files:**
- Create: `tests/shell/test_inference_service_role_core.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/shell/test_inference_service_role_core.sh` with checks for:

```bash
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

require_grep 'ansible.builtin.package:' "${ROLE_DIR}/tasks/main.yml"
require_grep 'ansible_service_mgr' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference-service-run.sh.j2' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference-service.env.j2' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference-service.systemd.j2' "${ROLE_DIR}/tasks/main.yml"
require_grep 'inference-service.openrc.j2' "${ROLE_DIR}/tasks/main.yml"
require_grep '/usr/local/libexec/inference-services' "${ROLE_DIR}/tasks/main.yml"
require_grep '/etc/inference-services' "${ROLE_DIR}/tasks/main.yml"
require_grep '/var/lib/inference' "${ROLE_DIR}/tasks/main.yml"
require_grep '/var/log/inference-services' "${ROLE_DIR}/tasks/main.yml"

require_grep 'podman run' "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep -- '--pull' "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep -- '--env-file' "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep -- '--device' "${ROLE_DIR}/templates/inference-service-run.sh.j2"
require_grep 'INFERENCE_SERVICE_NAME=' "${ROLE_DIR}/templates/inference-service.env.j2"
require_grep 'ExecStart=/usr/local/libexec/inference-services/run-' "${ROLE_DIR}/templates/inference-service.systemd.j2"
require_grep '#!/sbin/openrc-run' "${ROLE_DIR}/templates/inference-service.openrc.j2"

printf 'PASS: %s\n' "$(basename "$0")"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/shell/test_inference_service_role_core.sh
```

Expected: `FAIL: missing file: .../roles/inference_service/defaults/main.yml`

## Task 2: Role Defaults

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/defaults/main.yml`

- [ ] **Step 1: Add defaults**

Create defaults defining:

```yaml
---
inference_service_enabled: true
inference_service_state: started
inference_service_enable_on_boot: true
inference_service_manager: auto
inference_service_container_engine: podman
inference_service_config_dir: /etc/inference-services
inference_service_libexec_dir: /usr/local/libexec/inference-services
inference_service_state_root: /var/lib/inference
inference_service_log_root: /var/log/inference-services
inference_service_service_user: root
inference_service_service_group: root
inference_service_runlevel: default
inference_service_pull_policy: missing
inference_service_network: host
inference_service_accelerator: auto

inference_service_package_map:
  Debian:
    - podman
    - uidmap
    - slirp4netns
    - fuse-overlayfs
  RedHat:
    - podman
    - shadow-utils
    - slirp4netns
    - fuse-overlayfs
  Gentoo:
    - app-containers/podman
    - sys-apps/shadow

inference_service_accelerator_profiles:
  cpu:
    devices: []
    security_opts: []
    environment:
      INFERENCE_ACCELERATOR: cpu
  nvidia:
    devices:
      - nvidia.com/gpu=all
    security_opts: []
    environment:
      INFERENCE_ACCELERATOR: nvidia
      NVIDIA_VISIBLE_DEVICES: all
      NVIDIA_DRIVER_CAPABILITIES: compute,utility
  amd_rocm:
    devices:
      - /dev/kfd
      - /dev/dri
    security_opts: []
    environment:
      INFERENCE_ACCELERATOR: amd_rocm
      HSA_OVERRIDE_GFX_VERSION: ""
  auto:
    devices: []
    security_opts: []
    environment:
      INFERENCE_ACCELERATOR: auto

inference_service_default_environment: {}
inference_service_default_extra_args: []
inference_service_default_volumes: []
inference_service_default_ports: []
inference_service_default_command: []

inference_service_definitions:
  - name: ollama
    image: docker.io/ollama/ollama:latest
    port: 11434
    command: []
    environment:
      OLLAMA_HOST: 0.0.0.0:11434
    volumes:
      - ollama:/root/.ollama
  - name: vllm
    image: docker.io/vllm/vllm-openai:latest
    port: 8000
    command:
      - --host
      - 0.0.0.0
      - --port
      - "8000"
    environment: {}
    volumes: []
  - name: sglang
    image: docker.io/lmsysorg/sglang:latest
    port: 30000
    command:
      - python3
      - -m
      - sglang.launch_server
      - --host
      - 0.0.0.0
      - --port
      - "30000"
    environment: {}
    volumes: []
  - name: open-webui
    image: ghcr.io/open-webui/open-webui:main
    port: 8080
    command: []
    environment:
      OLLAMA_BASE_URL: http://127.0.0.1:11434
      OPENAI_API_BASE_URL: http://127.0.0.1:8000/v1
    volumes:
      - open-webui:/app/backend/data
```

- [ ] **Step 2: Run the role core test**

Run:

```bash
bash tests/shell/test_inference_service_role_core.sh
```

Expected: failure advances to missing task/template content.

## Task 3: Role Tasks and Templates

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/templates/inference-service-run.sh.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/templates/inference-service.env.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/templates/inference-service.systemd.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/inference_service/templates/inference-service.openrc.j2`

- [ ] **Step 1: Implement tasks**

Create tasks that:

```yaml
---
- name: Resolve inference service manager
  ansible.builtin.set_fact:
    resolved_inference_service_manager: >-
      {{ ansible_service_mgr if inference_service_manager == 'auto' else inference_service_manager }}
    resolved_inference_service_packages: >-
      {{ inference_service_package_map.get(ansible_os_family, inference_service_package_map.get(ansible_distribution, [])) }}
    resolved_inference_service_accelerator: "{{ inference_service_accelerator }}"
    resolved_inference_service_accelerator_profile: >-
      {{ inference_service_accelerator_profiles[inference_service_accelerator] }}
    resolved_inference_services: "{{ inference_service_definitions }}"

- name: Assert inference service inputs are supported
  ansible.builtin.assert:
    that:
      - inference_service_container_engine == 'podman'
      - resolved_inference_service_manager in ['systemd', 'openrc']
      - resolved_inference_service_accelerator in inference_service_accelerator_profiles
      - resolved_inference_services | length > 0
    fail_msg: "inference_service requires podman, systemd/openrc, a known accelerator profile, and at least one service definition."
  when: inference_service_enabled | bool

- name: Install inference service container prerequisites
  ansible.builtin.package:
    name: "{{ resolved_inference_service_packages }}"
    state: present
  when:
    - inference_service_enabled | bool
    - resolved_inference_service_packages | length > 0

- name: Ensure inference service directories exist
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  loop:
    - "{{ inference_service_config_dir }}"
    - "{{ inference_service_libexec_dir }}"
    - "{{ inference_service_state_root }}"
    - "{{ inference_service_log_root }}"
  when: inference_service_enabled | bool

- name: Render inference service environment files
  ansible.builtin.template:
    src: inference-service.env.j2
    dest: "{{ inference_service_config_dir }}/{{ inference_service.name }}.env"
    owner: root
    group: "{{ inference_service_service_group }}"
    mode: "0640"
  loop: "{{ resolved_inference_services }}"
  loop_control:
    loop_var: inference_service
  when: inference_service_enabled | bool

- name: Render inference service Podman wrappers
  ansible.builtin.template:
    src: inference-service-run.sh.j2
    dest: "{{ inference_service_libexec_dir }}/run-{{ inference_service.name }}.sh"
    owner: root
    group: root
    mode: "0755"
  loop: "{{ resolved_inference_services }}"
  loop_control:
    loop_var: inference_service
  when: inference_service_enabled | bool

- name: Render inference service systemd units
  ansible.builtin.template:
    src: inference-service.systemd.j2
    dest: "/etc/systemd/system/inference-{{ inference_service.name }}.service"
    owner: root
    group: root
    mode: "0644"
  loop: "{{ resolved_inference_services }}"
  loop_control:
    loop_var: inference_service
  when:
    - inference_service_enabled | bool
    - resolved_inference_service_manager == 'systemd'

- name: Render inference service OpenRC init scripts
  ansible.builtin.template:
    src: inference-service.openrc.j2
    dest: "/etc/init.d/inference-{{ inference_service.name }}"
    owner: root
    group: root
    mode: "0755"
  loop: "{{ resolved_inference_services }}"
  loop_control:
    loop_var: inference_service
  when:
    - inference_service_enabled | bool
    - resolved_inference_service_manager == 'openrc'

- name: Enable inference service systemd units
  ansible.builtin.systemd:
    name: "inference-{{ inference_service.name }}.service"
    enabled: "{{ inference_service_enable_on_boot | bool }}"
    state: "{{ inference_service_state }}"
    daemon_reload: true
  loop: "{{ resolved_inference_services }}"
  loop_control:
    loop_var: inference_service
  when:
    - inference_service_enabled | bool
    - resolved_inference_service_manager == 'systemd'

- name: Enable inference service OpenRC services
  ansible.builtin.service:
    name: "inference-{{ inference_service.name }}"
    enabled: "{{ inference_service_enable_on_boot | bool }}"
    state: "{{ inference_service_state }}"
  loop: "{{ resolved_inference_services }}"
  loop_control:
    loop_var: inference_service
  when:
    - inference_service_enabled | bool
    - resolved_inference_service_manager == 'openrc'
```

- [ ] **Step 2: Implement templates**

The templates must render a common env file, Podman wrapper with accelerator devices, and service-manager wrappers that call the generated script.

- [ ] **Step 3: Run test to verify it passes**

Run:

```bash
bash tests/shell/test_inference_service_role_core.sh
```

Expected: `PASS: test_inference_service_role_core.sh`

## Task 4: Targeted Verification

**Files:**
- No new files.

- [ ] **Step 1: Shell syntax and targeted role test**

Run:

```bash
bash -n tests/shell/test_inference_service_role_core.sh
bash tests/shell/test_inference_service_role_core.sh
```

Expected: both commands exit 0.

- [ ] **Step 2: Existing adjacent tests**

Run:

```bash
bash tests/shell/test_container_service_roles.sh
bash tests/shell/test_ntfy_server_role.sh
```

Expected: both commands exit 0.

- [ ] **Step 3: Document full-suite baseline blocker**

Record that `bash tests/shell/run-tests.sh` currently fails before inference tests because `/tmp/hetzner-dns-import.out` is owned by `forge4:forge4` with mode `0640`.

## Self-Review

- Spec coverage: role files cover package maps, service manager abstraction, Podman wrapper generation, accelerator profiles, env files, runtime wrappers, state root, and log root from the handoff. Forge3 retains playbooks and `run-tests.sh`; forge4 retains docs/live target audit.
- Placeholder scan: no implementation step uses TBD/TODO/fill-in language.
- Type consistency: role variable names use the `inference_service_*` prefix consistently; per-service loop variable is `inference_service`.
