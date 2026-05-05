#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

INVENTORY="${INVENTORY:-${ANSIBLE_ROOT}/inventories/pathb-binpkg-repository/hosts.yml}"
EXTRA_VARS_FILE="${EXTRA_VARS_FILE:-${ANSIBLE_ROOT}/vars/pathb_binpkg_repository_install.yml}"
SEQUENCE="${INSTALL_SEQUENCE:-full-default}"
LIMIT_TARGET="${LIMIT_TARGET:-target_system_remote}"
CONTROL_FLOW_PATH="${ANSIBLE_CONTROL_FLOW_PATH:-/tmp/ansible-control-flow/binpkg-repository.${SEQUENCE}.jsonl}"
STDOUT_CALLBACK="${ANSIBLE_STDOUT_CALLBACK:-default}"

exec "${SCRIPT_DIR}/run-install-sequence.sh" \
  --inventory "${INVENTORY}" \
  --limit "${LIMIT_TARGET}" \
  --sequence "${SEQUENCE}" \
  --control-flow-path "${CONTROL_FLOW_PATH}" \
  --stdout-callback "${STDOUT_CALLBACK}" \
  --extra-vars "@${EXTRA_VARS_FILE}" \
  "$@"
