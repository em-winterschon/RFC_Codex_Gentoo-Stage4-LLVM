#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH_SCRIPT="${REPO_ROOT}/scripts/watch-vm-serial.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

bash -n "${WATCH_SCRIPT}"

help_output="$("${WATCH_SCRIPT}" --help)"
assert_contains "${help_output}" 'container-services'
assert_contains "${help_output}" 'elasticsearch-test'
assert_contains "${help_output}" 'Ctrl-]'

print_output="$("${WATCH_SCRIPT}" --vm container-services --print)"
assert_contains "${print_output}" 'telnet'
assert_contains "${print_output}" '127.0.0.1'
assert_contains "${print_output}" '5003'

elastic_output="$("${WATCH_SCRIPT}" --vm elasticsearch-test --print)"
assert_contains "${elastic_output}" 'telnet'
assert_contains "${elastic_output}" '127.0.0.1'
assert_contains "${elastic_output}" '5005'

nc_output="$("${WATCH_SCRIPT}" --host 10.9.8.90 --port 5003 --mode nc --print)"
assert_contains "${nc_output}" 'nc'
assert_contains "${nc_output}" '10.9.8.90'
assert_contains "${nc_output}" '5003'

printf 'PASS: %s\n' "$(basename "$0")"
