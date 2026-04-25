#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
GENERATOR="${ANSIBLE_DIR}/scripts/generate-ansible-python-setup.sh"
COMMITTED_OUTPUT="${ANSIBLE_DIR}/scripts/setup-ansible-python-env.sh"
TEMP_DIR="$(mktemp -d)"
TEMP_OUTPUT="${TEMP_DIR}/setup-ansible-python-env.sh"
trap 'rm -rf "${TEMP_DIR}"' EXIT

"${GENERATOR}" "${TEMP_OUTPUT}" > /dev/null

diff -u "${COMMITTED_OUTPUT}" "${TEMP_OUTPUT}"

printf 'PASS: %s\n' "$(basename "$0")"
