#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPER="${REPO_ROOT}/scripts/migrate-container-services-runtime.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

test -f "${HELPER}"
bash -n "${HELPER}"

output="$(
  SOURCE_HOST=root@10.9.8.89 \
    TARGET_HOST=root@172.16.99.89 \
    bash "${HELPER}" --dry-run
)"

assert_contains "${output}" "DRY RUN"
assert_contains "${output}" "source=root@10.9.8.89"
assert_contains "${output}" "target=root@172.16.99.89"
assert_contains "${output}" "/etc/container-services"
assert_contains "${output}" "staging_mode=1"
assert_contains "${output}" "target_pathb_routes="

override_output="$(
  SOURCE_HOST=root@10.9.8.89 \
    TARGET_HOST=root@172.16.99.89 \
    TARGET_PATHB_ROUTES="10.9.8.91/32 via 172.16.99.108" \
    bash "${HELPER}" --dry-run
)"
assert_contains "${override_output}" "target_pathb_routes=10.9.8.91/32 via 172.16.99.108"

script_text="$(<"${HELPER}")"
assert_contains "${script_text}" "persist_target_pathb_routes"
assert_contains "${script_text}" "routes_eth0"
assert_contains "${script_text}" "routes_ens18"
assert_contains "${script_text}" "\"route\", \"get\", gateway"
assert_contains "${script_text}" 'TARGET_PATHB_ROUTES="${TARGET_PATHB_ROUTES:-}"'

printf 'PASS: %s\n' "$(basename "$0")"
