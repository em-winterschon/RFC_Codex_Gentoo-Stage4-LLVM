#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAYOUT_FILE="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/storage/tasks/layout_zfs_native.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

content="$(< "${LAYOUT_FILE}")"

[[ "${content}" == *"{% elif storage_layout in ['zfs-mirror', 'zfs-boot-root-mirror'] %}"* ]] ||
  fail "root vdev spec does not treat zfs-boot-root-mirror as a mirrored root pool"

printf 'PASS: %s\n' "$(basename "$0")"
