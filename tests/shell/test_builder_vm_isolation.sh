#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

doc="${REPO_ROOT}/docs/X12AGAIN-BUILDER-VM-ISOLATION.md"
wiki_doc="${REPO_ROOT}/docs/wiki/X12AGAIN-Builder-VM-Isolation.md"
recover_script="${ANSIBLE_ROOT}/scripts/recover-pathb-build-root.sh"

[[ -f "${doc}" ]] || fail "missing ${doc}"
[[ -f "${wiki_doc}" ]] || fail "missing ${wiki_doc}"
[[ -x "${recover_script}" ]] || fail "missing executable ${recover_script}"

assert_file_contains "${doc}" "X12AGAIN is a resource provider"
assert_file_contains "${doc}" "Do not build here"
assert_file_contains "${doc}" "/var/lib/netboot/staging/path-b"
assert_file_contains "${doc}" "Failed or stale builder VMs are destroyed"
assert_file_contains "${doc}" "Do not run blind"
assert_file_contains "${wiki_doc}" "X12AGAIN is a resource provider"
assert_file_contains "${recover_script}" "rm -rf --one-file-system"
assert_file_contains "${recover_script}" "mountpoint -q"
assert_file_contains "${recover_script}" "/proc/self/mountinfo"
assert_file_contains "${recover_script}" "mktemp"
assert_file_contains "${recover_script}" "rm -f"
assert_file_contains "${recover_script}" "Refusing unsafe build root"

printf 'PASS: %s\n' "$(basename "$0")"
