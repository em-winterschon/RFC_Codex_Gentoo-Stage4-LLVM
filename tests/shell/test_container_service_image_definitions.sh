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
assert_file_contains "${MANIFEST}" 'ghcr.io/em-winterschon/gentoo-stage5-nginx:git-d5104ae'
assert_file_contains "${MANIFEST}" 'sha256:8604b39531e508348a3ac3094621b3aef51ca8927721f17087742b888e6e9c90'
assert_file_contains "${MANIFEST}" '^    haproxy:'
assert_file_contains "${MANIFEST}" 'net-proxy/haproxy'
assert_file_contains "${MANIFEST}" 'ghcr.io/em-winterschon/gentoo-stage5-haproxy:git-d5104ae'
assert_file_contains "${MANIFEST}" 'sha256:322699f05e1109f63fff3796ce7dbbddb7200c7933c2eb7ae7aaaa6e88bc8f37'
assert_file_contains "${MANIFEST}" '^    rsyslog_collector:'
assert_file_contains "${MANIFEST}" 'app-admin/rsyslog'
assert_file_contains "${MANIFEST}" 'ghcr.io/em-winterschon/gentoo-stage5-rsyslog-collector:git-37a4d4a'
assert_file_contains "${MANIFEST}" 'sha256:451ca03a0b7aff452cc75ebbf50eea19e322a16b23aab200c19875ecfe7c45f7'
assert_file_contains "${MANIFEST}" '^    ntfy:'
assert_file_contains "${MANIFEST}" 'build_mode: upstream-image'

printf 'PASS: %s\n' "$(basename "$0")"
