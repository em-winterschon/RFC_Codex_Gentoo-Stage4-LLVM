#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="${REPO_ROOT}/.github/workflows/validate.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

grep -q 'FORCE_JAVASCRIPT_ACTIONS_TO_NODE24' "${WORKFLOW}" || fail "Validate workflow must opt into Node.js 24 before GitHub runner default changes"
grep -q "actions/checkout@v4" "${WORKFLOW}" || fail "Validate workflow must check out repository"
grep -q "actions/setup-python@v5" "${WORKFLOW}" || fail "Validate workflow must install Python"
grep -q "pre-commit run --all-files --show-diff-on-failure" "${WORKFLOW}" || fail "Validate workflow must run pre-commit"
grep -q "bash tests/shell/run-tests.sh" "${WORKFLOW}" || fail "Validate workflow must run shell tests"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
