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

test_dry_run_local_root() {
  local temp_dir output local_root
  temp_dir="$(mktemp -d)"
  local_root="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}" "${local_root}"' RETURN

  output="$(
    bash "${SYNC_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --local-root "${local_root}" \
      --dry-run
  )"

  assert_contains "${output}" "pkgdir=${temp_dir}"
  assert_contains "${output}" "repo-id=stage4-test__stage5-test__amd64__x86_64_v2"
  assert_contains "${output}" "local-root=${local_root}"
  assert_contains "${output}" "local-repo=${local_root}/stage4-test__stage5-test__amd64__x86_64_v2"
}

test_dry_run_nested_repo_id() {
  local temp_dir output local_root
  temp_dir="$(mktemp -d)"
  local_root="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}" "${local_root}"' RETURN

  output="$(
    bash "${SYNC_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm \
      --local-root "${local_root}" \
      --dry-run
  )"

  assert_contains "${output}" "repo-id=contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm"
  assert_contains "${output}" "local-repo=${local_root}/contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm"
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

  assert_contains "${output}" 'repo-id contains unsafe path component'
}

test_rejects_repo_id_traversal_component() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  if output="$(
    bash "${SYNC_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id 'contracts/../bad' \
      --remote root@example.invalid \
      --dry-run 2>&1
  )"; then
    fail "expected repo-id traversal to fail"
  fi

  assert_contains "${output}" 'repo-id contains unsafe path component'
}

test_rejects_missing_destination() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  if output="$(
    bash "${SYNC_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --dry-run 2>&1
  )"; then
    fail "expected missing destination to fail"
  fi

  assert_contains "${output}" 'one of --remote or --local-root is required'
}

test_dry_run
test_dry_run_local_root
test_dry_run_nested_repo_id
test_rejects_unsafe_repo_id
test_rejects_repo_id_traversal_component
test_rejects_missing_destination

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
