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

require_dir "${ANSIBLE_ROOT}/roles/nexus_repo"
require_file "${ANSIBLE_ROOT}/roles/nexus_repo/defaults/main.yml"
require_file "${ANSIBLE_ROOT}/roles/nexus_repo/tasks/main.yml"
require_file "${ANSIBLE_ROOT}/roles/nexus_repo/templates/nexus.openrc.j2"
require_file "${ANSIBLE_ROOT}/roles/nexus_repo/templates/nexus.vmoptions.j2"
require_file "${ANSIBLE_ROOT}/roles/nexus_repo/templates/nexus-repository.properties.j2"
require_file "${ANSIBLE_ROOT}/roles/nexus_repo/templates/nexus-proxy-intent.yml.j2"

require_file "${ANSIBLE_ROOT}/profile-definitions/vm-nexus-repository.yml"
require_file "${ANSIBLE_ROOT}/profile-definitions/vm-nexus-repository.metadata.yml"
require_file "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-nexus-repository.packages"
require_file "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-nexus-repository.yml"
require_file "${ANSIBLE_ROOT}/inventories/examples/group_vars/nexus_repositories.yml"

require_grep 'nexus_repo' "${ANSIBLE_ROOT}/playbooks/install.yml"
require_grep 'resolved_profile_nexus_repo' "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml"
require_grep 'gentoo_profile_definition.nexus_repo' "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml"
require_grep 'nexus_repo' "${ANSIBLE_ROOT}/vars/install_sequences.yml"
require_grep 'nexus_repo_default_version: 3.90.1-01' "${ANSIBLE_ROOT}/roles/nexus_repo/defaults/main.yml"
require_grep '/tmp/Nexus-Repo-OSS/sonatype-nexus-repo-oss_-3.90.1-01-linux-x86_64.tar.gz' "${ANSIBLE_ROOT}/profile-definitions/vm-nexus-repository.yml"
require_grep 'transparent_proxy_repositories' "${ANSIBLE_ROOT}/profile-definitions/vm-nexus-repository.yml"
require_grep 'app_version_lock_id: sonatype-nexus-repository-oss' "${ANSIBLE_ROOT}/profile-definitions/vm-nexus-repository.metadata.yml"

require_file "${REPO_ROOT}/docs/NEXUS-REPOSITORY.md"
require_file "${REPO_ROOT}/docs/wiki/Nexus-Repository.md"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
