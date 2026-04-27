#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PUBLISH_SCRIPT="${REPO_ROOT}/scripts/publish-container-ghcr.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

test_print_target() {
  local output

  output="$(
    cd "${REPO_ROOT}" &&
      bash "${PUBLISH_SCRIPT}" \
        --local-image local/test:latest \
        --image-name gentoo-stage4-base \
        --namespace em-winterschon \
        --tag git-deadbeef \
        --print-target
  )"

  [[ "${output}" == 'ghcr.io/em-winterschon/gentoo-stage4-base:git-deadbeef' ]] ||
    fail "unexpected target: ${output}"
}

test_dry_run() {
  local output

  output="$(
    cd "${REPO_ROOT}" &&
      bash "${PUBLISH_SCRIPT}" \
        --local-image local/test:latest \
        --image-name gentoo-stage4-base \
        --namespace em-winterschon \
        --tag latest \
        --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
        --description 'Gentoo Stage4 LLVM/Clang hardened base container' \
        --dry-run
  )"

  assert_contains "${output}" 'local-image=local/test:latest'
  assert_contains "${output}" 'target-ref=ghcr.io/em-winterschon/gentoo-stage4-base:latest'
  assert_contains "${output}" 'source-url=https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM'
}

test_print_target
test_dry_run

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
