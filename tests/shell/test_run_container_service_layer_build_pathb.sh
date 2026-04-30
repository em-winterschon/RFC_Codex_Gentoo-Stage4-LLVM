#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCHER="${REPO_ROOT}/scripts/run-container-service-layer-build-pathb.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in output"
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" != *"${needle}"* ]] || fail "did not expect '${needle}' in output"
}

test_nginx_plan() {
  local output
  output="$(
    CONTAINER_STAGE3_TARBALL=/tmp/stage3.tar.xz \
      bash "${LAUNCHER}" --service nginx --dry-run
  )"

  assert_contains "${output}" 'service=nginx'
  assert_contains "${output}" 'package-list=container-image-definitions/gentoo-stage5-nginx.packages'
  assert_contains "${output}" 'package-use-file=container-image-definitions/gentoo-stage5-nginx.package.use'
  assert_contains "${output}" 'image-ref=localhost/gentoo-stage5-nginx:latest'
  assert_contains "${output}" 'binpkg-repo-id=stage3-llvm_clang_openrc__stage5-service_container-nginx__amd64__x86_64_v2_generic'
  assert_contains "${output}" 'stage3-tarball=/tmp/stage3.tar.xz'
  assert_not_contains "${output}" 'main-env='
}

test_unknown_service_fails() {
  local output
  if output="$(bash "${LAUNCHER}" --service does-not-exist --dry-run 2>&1)"; then
    fail 'expected unknown service to fail'
  fi

  assert_contains "${output}" 'Unsupported service layer: does-not-exist'
}

test_haproxy_uses_gcc_compat() {
  local output
  output="$(bash "${LAUNCHER}" --service haproxy --dry-run)"

  assert_contains "${output}" 'service=haproxy'
  assert_contains "${output}" 'package-use-file=container-image-definitions/gentoo-stage5-haproxy.package.use'
  assert_contains "${output}" 'main-env=CC=gcc'
  assert_contains "${output}" 'main-env=CXX=g++'
}

test_nginx_plan
test_unknown_service_fails
test_haproxy_uses_gcc_compat

printf 'PASS: %s\n' "$(basename "$0")"
