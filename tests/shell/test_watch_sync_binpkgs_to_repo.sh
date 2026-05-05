#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WATCH_SCRIPT="${REPO_ROOT}/scripts/watch-sync-binpkgs-to-repo.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected '${needle}' in '${haystack}'"
}

test_dry_run_local_source() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  output="$(
    bash "${WATCH_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --remote root@example.invalid \
      --once \
      --dry-run
  )"

  assert_contains "${output}" "pkgdir=${temp_dir}"
  assert_contains "${output}" 'remote-source=false'
  assert_contains "${output}" 'staging-dir='
  assert_contains "${output}" 'once=true'
}

test_dry_run_remote_source_uses_staging() {
  local output

  output="$(
    bash "${WATCH_SCRIPT}" \
      --pkgdir root@builder.example:/var/cache/binpkgs \
      --repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --remote root@example.invalid \
      --watch-remote root@builder.example \
      --watch-pattern build-gentoo-rootfs-container \
      --interval 30 \
      --dry-run
  )"

  assert_contains "${output}" 'remote-source=true'
  assert_contains "${output}" 'staging-dir=/var/tmp/stage5-binpkg-sync/stage4-test__stage5-test__amd64__x86_64_v2'
  assert_contains "${output}" 'watch-remote=root@builder.example'
  assert_contains "${output}" 'watch-pattern=build-gentoo-rootfs-container'
  assert_contains "${output}" 'interval=30'
}

test_dry_run_watch_pid() {
  local output

  output="$(
    bash "${WATCH_SCRIPT}" \
      --pkgdir root@builder.example:/var/cache/binpkgs \
      --repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --remote root@example.invalid \
      --watch-remote root@builder.example \
      --watch-pid 1234 \
      --dry-run
  )"

  assert_contains "${output}" 'watch-remote=root@builder.example'
  assert_contains "${output}" 'watch-pid=1234'
}

test_rejects_incomplete_watch_args() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  if output="$(
    bash "${WATCH_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --remote root@example.invalid \
      --watch-remote root@builder.example \
      --dry-run 2>&1
  )"; then
    fail "expected incomplete watch args to fail"
  fi

  assert_contains "${output}" '--watch-remote requires --watch-pid or --watch-pattern'
}

test_rejects_multiple_watch_modes() {
  local temp_dir output
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  if output="$(
    bash "${WATCH_SCRIPT}" \
      --pkgdir "${temp_dir}" \
      --repo-id stage4-test__stage5-test__amd64__x86_64_v2 \
      --remote root@example.invalid \
      --watch-pid 1234 \
      --watch-pattern build-gentoo-rootfs-container \
      --dry-run 2>&1
  )"; then
    fail "expected multiple watch modes to fail"
  fi

  assert_contains "${output}" '--watch-pid and --watch-pattern are mutually exclusive'
}

test_dry_run_local_source
test_dry_run_remote_source_uses_staging
test_dry_run_watch_pid
test_rejects_incomplete_watch_args
test_rejects_multiple_watch_modes

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
