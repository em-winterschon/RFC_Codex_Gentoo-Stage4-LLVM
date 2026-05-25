#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

canary_doc="${REPO_ROOT}/docs/M70-CANARY-VALIDATION-LANE.md"
platform_doc="${REPO_ROOT}/docs/M70-PLATFORM-OPTIMIZATION-PLAN.md"
serial_doc="${REPO_ROOT}/docs/M70-SERIAL-CONSOLE-MAP.md"
gap_doc="${REPO_ROOT}/docs/M70-CANARY-GAP-ANALYSIS-2026-05-24.md"
wiki_canary="${REPO_ROOT}/docs/wiki/M70-Canary-Validation-Lane.md"
wiki_platform="${REPO_ROOT}/docs/wiki/M70-Platform-Optimization-Plan.md"
wiki_serial="${REPO_ROOT}/docs/wiki/M70-Serial-Console-Map.md"
wiki_gap="${REPO_ROOT}/docs/wiki/M70-Canary-Gap-Analysis-2026-05-24.md"
wiki_home="${REPO_ROOT}/docs/wiki/Home.md"
wiki_sidebar="${REPO_ROOT}/docs/wiki/_Sidebar.md"
wiki_readme="${REPO_ROOT}/docs/wiki/README.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${canary_doc}" "Current Remediation State"
assert_file_contains "${canary_doc}" "sbsoc-accel-int64-m70n2.rfc1918.host"
assert_file_contains "${canary_doc}" "90-intel-qat-c3000.config"
assert_file_contains "${canary_doc}" "kernel/x86/microcode/AuthenticAMD.bin"
assert_file_contains "${canary_doc}" "kernel/x86/microcode/GenuineIntel.bin"
assert_file_contains "${canary_doc}" "spl_hostid=1709fd12"
assert_file_contains "${canary_doc}" "Installed-root validation on 2026-05-25"
assert_file_contains "${canary_doc}" "lacp_status: negotiated"

assert_file_contains "${platform_doc}" "Current canary evidence from 2026-05-24"
assert_file_contains "${platform_doc}" "kernel_config"
assert_file_contains "${platform_doc}" "local ZFSBootMenu boot validation"
assert_file_contains "${serial_doc}" "m70_canary"

assert_file_contains "${gap_doc}" "Open Issue Review"
assert_file_contains "${gap_doc}" "86 open issues"
assert_file_contains "${gap_doc}" "#144"
assert_file_contains "${gap_doc}" "#160"
assert_file_contains "${gap_doc}" "#161"
assert_file_contains "${gap_doc}" "Remaining documentation gaps"

assert_file_contains "${wiki_canary}" "M70 Canary Validation Lane"
assert_file_contains "${wiki_platform}" "M70 Platform Optimization Plan"
assert_file_contains "${wiki_serial}" "M70 Serial Console Map"
assert_file_contains "${wiki_gap}" "M70 Canary Gap Analysis 2026-05-24"
assert_file_contains "${wiki_home}" "M70 Canary Validation Lane"
assert_file_contains "${wiki_sidebar}" "M70 Canary Validation Lane"
assert_file_contains "${wiki_readme}" "M70-Canary-Validation-Lane.md"
assert_file_contains "${run_tests}" "test_m70_canary_docs.sh"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
