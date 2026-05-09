#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SCRIPT="${REPO_ROOT}/scripts/sync-binpkgs-to-repo.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

test_dry_run() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  output="$(
    bash "${SYNC_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --remote root@example.invalid \
      --remote-root /srv/stage5-binpkgs \
      --dry-run
  )"

  assert_contains "${output}" "pkgdir=${temp_dir}"
  assert_contains "${output}" "repo-id=stage4-test__stage5-test__amd64__x86_64_v2"
  assert_contains "${output}" "remote=root@example.invalid"
  assert_contains "${output}" "remote-repo=/srv/stage5-binpkgs/stage4-test__stage5-test__amd64__x86_64_v2"
}

test_rejects_unsafe_repo_id() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  if output="$(
    bash "${SYNC_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id '../bad' \
      --remote root@example.invalid \
      --dry-run 2>&1
  )"; then
    fail "expected unsafe repo-id to fail"
  fi

  assert_contains "${output}" 'repo-id contains unsafe characters'
}

test_dry_run
test_rejects_unsafe_repo_id

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
