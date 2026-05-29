#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_dir() {
  [[ -d "$1" ]] || fail "missing directory: $1"
}

require_grep() {
  local pattern=$1
  local file=$2
  grep -q -- "${pattern}" "${file}" || fail "missing pattern '${pattern}' in ${file}"
}

reject_grep() {
  local pattern=$1
  local file=$2
  if grep -q -- "${pattern}" "${file}"; then
    fail "unexpected pattern '${pattern}' in ${file}"
  fi
}

ROLE_DIR="${ANSIBLE_ROOT}/roles/forge_memory_object_store"

require_dir "${ROLE_DIR}"
require_file "${ROLE_DIR}/defaults/main.yml"
require_file "${ROLE_DIR}/tasks/main.yml"
require_file "${ROLE_DIR}/templates/forge-memory-object-store.env.j2"
require_file "${ROLE_DIR}/templates/forge-memory-object-store-policy.yml.j2"
require_file "${ROLE_DIR}/templates/forge-memory-object-store.openrc.j2"

require_file "${ANSIBLE_ROOT}/profile-definitions/vm-forge-memory-object-store.yml"
require_file "${ANSIBLE_ROOT}/profile-definitions/vm-forge-memory-object-store.metadata.yml"
require_file "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-forge-memory-object-store.packages"
require_file "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-forge-memory-object-store.yml"

require_grep 'forge_memory_object_store' "${ANSIBLE_ROOT}/vars/install_sequences.yml"
require_grep 'forge_memory_object_store' "${ANSIBLE_ROOT}/playbooks/install.yml"
require_grep 'resolved_profile_forge_memory_object_store' "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml"
require_grep 'gentoo_profile_definition.forge_memory_object_store' "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml"

require_grep 'forge_memory_object_store_default_bucket: forge-memory' "${ROLE_DIR}/defaults/main.yml"
require_grep 'forge_memory_object_store_default_prefix: forge-memory/v1' "${ROLE_DIR}/defaults/main.yml"
require_grep 'forge_memory_object_store_default_object_lock_enabled: true' "${ROLE_DIR}/defaults/main.yml"
require_grep 'forge_memory_object_store_default_sse_algorithm: AES256' "${ROLE_DIR}/defaults/main.yml"
require_grep 'forge_memory_object_store_default_lifecycle_retention_days: 365' "${ROLE_DIR}/defaults/main.yml"
require_grep 'append-only' "${ROLE_DIR}/templates/forge-memory-object-store-policy.yml.j2"
require_grep 'agent_namespace_isolation' "${ROLE_DIR}/templates/forge-memory-object-store-policy.yml.j2"
require_grep 'audit_log_prefix' "${ROLE_DIR}/templates/forge-memory-object-store-policy.yml.j2"
require_grep 'AWS_ENDPOINT_URL' "${ROLE_DIR}/templates/forge-memory-object-store.env.j2"
require_grep 'FORGE_MEMORY_S3_BUCKET' "${ROLE_DIR}/templates/forge-memory-object-store.env.j2"
require_grep 'FORGE_MEMORY_S3_PREFIX' "${ROLE_DIR}/templates/forge-memory-object-store.env.j2"
reject_grep 'AWS_SECRET_ACCESS_KEY' "${ROLE_DIR}/defaults/main.yml"
reject_grep 'AWS_SECRET_ACCESS_KEY' "${ANSIBLE_ROOT}/profile-definitions/vm-forge-memory-object-store.yml"

require_file "${REPO_ROOT}/docs/FORGE-MEMORY-OBJECT-STORE.md"
require_file "${REPO_ROOT}/docs/wiki/Forge-Memory-Object-Store.md"
require_grep 'MEM-001' "${REPO_ROOT}/docs/FORGE-MEMORY-OBJECT-STORE.md"
require_grep 'MEM-002' "${REPO_ROOT}/docs/FORGE-MEMORY-OBJECT-STORE.md"
require_grep 'append-only' "${REPO_ROOT}/docs/FORGE-MEMORY-OBJECT-STORE.md"
require_grep 'server-side encryption' "${REPO_ROOT}/docs/FORGE-MEMORY-OBJECT-STORE.md"
require_grep 'No access keys or secret keys are stored' "${REPO_ROOT}/docs/FORGE-MEMORY-OBJECT-STORE.md"
require_grep 'MEM-001' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
require_grep 'MEM-002' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
require_grep 'forge_memory_object_store' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
