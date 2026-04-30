#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${REPO_ROOT}/container-image-definitions/service-layers.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q "${pattern}" "${file}" || fail "expected ${pattern} in ${file}"
}

test -f "${MANIFEST}"
assert_file_contains "${MANIFEST}" 'ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc:latest'
assert_file_contains "${MANIFEST}" '^    nginx:'
assert_file_contains "${MANIFEST}" 'www-servers/nginx'
assert_file_contains "${MANIFEST}" '^    haproxy:'
assert_file_contains "${MANIFEST}" 'net-proxy/haproxy'
assert_file_contains "${MANIFEST}" '^    rsyslog_collector:'
assert_file_contains "${MANIFEST}" 'app-admin/rsyslog'
assert_file_contains "${MANIFEST}" '^    ntfy:'
assert_file_contains "${MANIFEST}" 'build_mode: upstream-image'

printf 'PASS: %s\n' "$(basename "$0")"
