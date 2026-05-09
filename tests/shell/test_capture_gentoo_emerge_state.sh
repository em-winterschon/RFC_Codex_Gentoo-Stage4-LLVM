#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/capture-gentoo-emerge-state.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "${SCRIPT}" ]] || fail "expected executable script: ${SCRIPT}"
bash -n "${SCRIPT}"

help_output="$("${SCRIPT}" --help)"
[[ "${help_output}" == *"Captures Gentoo Portage state"* ]] || fail "help output did not describe capture behavior"
[[ "${help_output}" == *"OUTPUT_DIR"* ]] || fail "help output did not mention OUTPUT_DIR"

printf 'PASS: %s\n' "$(basename "$0")"
