#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

PLAN="${REPO_ROOT}/docs/OVERNIGHT-EXECUTION-2026-05-12.md"
WIKI_PLAN="${REPO_ROOT}/docs/wiki/Overnight-Execution-2026-05-12.md"

assert_file_contains "${PLAN}" "Backup-Safe Operating Mode"
assert_file_contains "${PLAN}" "Issue #114"
assert_file_contains "${PLAN}" "Issue #115"
assert_file_contains "${PLAN}" "Issue #116"
assert_file_contains "${PLAN}" "Issue #111"
assert_file_contains "${PLAN}" "Do not start heavy Portage, VM image, or live-infrastructure mutation work while the off-host backup is active."
assert_file_contains "${PLAN}" "Morning handoff sequence"
assert_file_contains "${WIKI_PLAN}" "Backup-Safe Operating Mode"
assert_file_contains "${WIKI_PLAN}" "Morning handoff sequence"

printf 'PASS: %s\n' "$(basename "$0")"
