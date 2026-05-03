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

crs309_plan="${REPO_ROOT}/docs/CRS309-ROUTEROS-REPLACEMENT-PLAN.md"
netbox_plan="${REPO_ROOT}/docs/NETBOX-IPAM-DCIM-COMPLETION-PLAN.md"
eod="${REPO_ROOT}/docs/EOD-STATUS-2026-05-02.md"
implementation_plan="${REPO_ROOT}/docs/superpowers/plans/2026-05-02-netbox-dcim-ipam-and-crs309-router-replacement.md"
wiki_crs309="${REPO_ROOT}/docs/wiki/CRS309-RouterOS-Replacement-Plan.md"
wiki_netbox="${REPO_ROOT}/docs/wiki/NetBox-IPAM-DCIM-Completion-Plan.md"
wiki_eod="${REPO_ROOT}/docs/wiki/EOD-Status-2026-05-02.md"
wiki_home="${REPO_ROOT}/docs/wiki/Home.md"
wiki_sidebar="${REPO_ROOT}/docs/wiki/_Sidebar.md"
roadmap="${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
run_tests="${REPO_ROOT}/tests/shell/run-tests.sh"

assert_file_contains "${crs309_plan}" "/tmp/crs309-router-mode-idc.wip.rsc"
assert_file_contains "${crs309_plan}" "/tmp/rfc99-sun99-host-networking.md"
assert_file_contains "${crs309_plan}" "destructive replacement-router import"
assert_file_contains "${crs309_plan}" "172.16.228.0/22"
assert_file_contains "${crs309_plan}" "Validation Gates"
assert_file_contains "${crs309_plan}" "Rollback"

assert_file_contains "${netbox_plan}" "Make NetBox the authoritative IPAM/DCIM source"
assert_file_contains "${netbox_plan}" "RFC99"
assert_file_contains "${netbox_plan}" "SUN99"
assert_file_contains "${netbox_plan}" "FMT2"
assert_file_contains "${netbox_plan}" "Acceptance Criteria"

assert_file_contains "${eod}" "EOD Status 2026-05-02"
assert_file_contains "${eod}" "Non-destructive overnight tasks"
assert_file_contains "${eod}" "Destructive work explicitly deferred"
assert_file_contains "${implementation_plan}" "# NetBox DCIM/IPAM And CRS309 Router Replacement Implementation Plan"
assert_file_contains "${implementation_plan}" "REQUIRED SUB-SKILL"

assert_file_contains "${wiki_crs309}" "CRS309 RouterOS Replacement Plan"
assert_file_contains "${wiki_netbox}" "NetBox IPAM/DCIM Completion Plan"
assert_file_contains "${wiki_eod}" "EOD Status 2026-05-02"
assert_file_contains "${wiki_home}" "CRS309 RouterOS Replacement Plan"
assert_file_contains "${wiki_home}" "EOD Status 2026-05-02"
assert_file_contains "${wiki_sidebar}" "NetBox IPAM DCIM Completion Plan"
assert_file_contains "${roadmap}" "PNR-011"
assert_file_contains "${roadmap}" "PNR-012"
assert_file_contains "${run_tests}" "test_network_planning_docs.sh"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
