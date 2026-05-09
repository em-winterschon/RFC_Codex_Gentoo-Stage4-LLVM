#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

cd "${ANSIBLE_ROOT}"
ANSIBLE_LINT_NODEPS=1 ansible-lint playbooks/install.yml

printf 'PASS: %s\n' "$(basename "$0")"
