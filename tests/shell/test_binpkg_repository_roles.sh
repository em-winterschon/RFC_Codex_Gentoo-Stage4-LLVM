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

require_dir "${ANSIBLE_ROOT}/roles/binpkg_repo"
require_file "${ANSIBLE_ROOT}/roles/binpkg_repo/tasks/main.yml"
require_file "${ANSIBLE_ROOT}/roles/binpkg_repo/templates/binpkg-repo.nginx.conf.j2"
require_file "${ANSIBLE_ROOT}/roles/binpkg_repo/templates/stage5-binpkg-index.sh.j2"

require_file "${ANSIBLE_ROOT}/profile-definitions/vm-binpkg-repository.yml"
require_file "${ANSIBLE_ROOT}/profile-definitions/vm-binpkg-repository.metadata.yml"
require_file "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-binpkg-repository.packages"
require_file "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-binpkg-repository.yml"
require_file "${ANSIBLE_ROOT}/inventories/examples/group_vars/binpkg_repositories.yml"
require_file "${ANSIBLE_ROOT}/inventories/pathb-binpkg-repository/hosts.yml"
require_file "${ANSIBLE_ROOT}/vars/pathb_binpkg_repository_install.yml"
require_file "${ANSIBLE_ROOT}/scripts/run-binpkg-repository-install.sh"

require_grep 'binpkg_repo' "${ANSIBLE_ROOT}/vars/install_sequences.yml"
require_grep 'binpkg_repo' "${ANSIBLE_ROOT}/playbooks/install.yml"
require_grep 'resolved_profile_binpkg_repo' "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml"
require_grep 'gentoo_profile_definition.binpkg_repo' "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml"
require_grep 'portage_binrepos' "${ANSIBLE_ROOT}/roles/portage/tasks/main.yml"
require_grep 'PORTAGE_BINPKG_FORMAT' "${ANSIBLE_ROOT}/roles/portage/templates/make.conf.j2"

require_file "${REPO_ROOT}/scripts/sync-binpkgs-to-repo.sh"
require_grep 'local-root' "${REPO_ROOT}/scripts/sync-binpkgs-to-repo.sh"
require_grep 'binpkg-sync-remote' "${REPO_ROOT}/scripts/build-gentoo-rootfs-container.sh"
require_file "${REPO_ROOT}/gentoo-virt-qemu/qemu-launch-binpkg-repository-vm.sh"
require_file "${REPO_ROOT}/docs/BINPKG-REPOSITORY.md"
require_grep 'M70-local NASA NFS' "${REPO_ROOT}/docs/BINPKG-REPOSITORY.md"
require_grep '--local-root' "${REPO_ROOT}/docs/BINPKG-REPOSITORY.md"
require_file "${REPO_ROOT}/docs/wiki/Binpkg-Repository.md"
require_grep 'M70-local NASA NFS' "${REPO_ROOT}/docs/wiki/Binpkg-Repository.md"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
