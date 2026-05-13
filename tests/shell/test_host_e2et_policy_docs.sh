#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

assert_file_contains() {
  local file=$1
  local pattern=$2
  test -f "${file}"
  grep -q -- "${pattern}" "${file}"
}

doc="${REPO_ROOT}/docs/HOST-E2ET-ACCEPTANCE.md"
wiki_doc="${REPO_ROOT}/docs/wiki/Host-E2ET-Acceptance.md"
roadmap="${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
changelog="${REPO_ROOT}/docs/CHANGELOG.md"

for path in "${doc}" "${wiki_doc}"; do
  assert_file_contains "${path}" 'RFC99 Host E2ET Acceptance Pipeline'
  assert_file_contains "${path}" 'transient validated'
  assert_file_contains "${path}" 'reboot-durable'
  assert_file_contains "${path}" 'Inventory Gate'
  assert_file_contains "${path}" 'Provisioning Gate'
  assert_file_contains "${path}" 'First Boot Gate'
  assert_file_contains "${path}" 'Platform Gate'
  assert_file_contains "${path}" 'Network Gate'
  assert_file_contains "${path}" 'Storage Gate'
  assert_file_contains "${path}" 'Identity Gate'
  assert_file_contains "${path}" 'Service Gate'
  assert_file_contains "${path}" 'Performance Gate'
  assert_file_contains "${path}" 'Conformance Report'
  assert_file_contains "${path}" 'p60'
  assert_file_contains "${path}" 'p80'
  assert_file_contains "${path}" 'p90'
  assert_file_contains "${path}" 'p95'
  assert_file_contains "${path}" 'p99'
  assert_file_contains "${path}" 'K10'
  assert_file_contains "${path}" 'aaa-domain-client'
done

assert_file_contains "${roadmap}" 'E2ET-001'
assert_file_contains "${roadmap}" 'RFC99 Host E2ET Acceptance Pipeline'
assert_file_contains "${changelog}" 'RFC99 Host E2ET Acceptance Pipeline'

printf 'PASS: %s\n' "$(basename "$0")"
