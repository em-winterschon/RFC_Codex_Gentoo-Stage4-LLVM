#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  test -f "${file}" || fail "missing file ${file}"
  grep -Fq -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2
  test -f "${file}" || fail "missing file ${file}"
  if grep -Fq -- "${pattern}" "${file}"; then
    fail "expected ${file} to not contain ${pattern}"
  fi
}

policy="${REPO_ROOT}/artifact-plane/git-annex-policy.yml"
doc="${REPO_ROOT}/docs/GIT-ANNEX-ARTIFACT-PLANE.md"
runbook="${REPO_ROOT}/docs/runbooks/git-annex-artifact-plane-bootstrap.md"
plan="${REPO_ROOT}/docs/superpowers/plans/2026-05-25-git-annex-artifact-plane.md"
script="${REPO_ROOT}/scripts/bootstrap-yukonsys-artifact-annex.sh"

assert_file_contains "${policy}" 'annex_backend: SHA256E'
assert_file_contains "${policy}" 'minimum_numcopies: 2'
assert_file_contains "${policy}" 'remote_encryption_mode: hybrid'
assert_file_contains "${policy}" 'remote_filename_mac: HMACSHA256'
assert_file_contains "${policy}" 'primary_special_remote_type: directory'
assert_file_contains "${policy}" 'primary_special_remote_name: nasa-nfs-artifact-annex'
assert_file_contains "${policy}" 'forbidden_backends:'
assert_file_contains "${policy}" 'SHA1'
assert_file_contains "${policy}" 'SHA1E'
assert_file_contains "${policy}" 'MD5'
assert_file_contains "${policy}" 'MD5E'
assert_file_contains "${policy}" 'WORM'
assert_file_contains "${policy}" 'URL'
assert_file_contains "${policy}" 'worker_preferred_content:'
assert_file_contains "${policy}" 'forge-builder'
assert_file_contains "${policy}" 'forge-inference'
assert_file_contains "${policy}" 'forge-control-plane'
assert_file_contains "${policy}" 'source_workspace_policy:'
assert_file_contains "${policy}" 'required_source_repos:'
assert_file_contains "${policy}" 'YukonSYS-Standard-Definitions'
assert_file_contains "${policy}" 'YukonSYS-Artifact-Annex'
assert_file_contains "${policy}" 'feature_worktrees_are_worker_local: true'

assert_file_contains "${doc}" 'Default backend: `SHA256E`'
assert_file_contains "${doc}" 'Do not use `SHA1`, `SHA1E`, `MD5`, `MD5E`, `WORM`, or `URL`'
assert_file_contains "${doc}" 'Git-Annex backend selection is integrity keying, not transport encryption.'
assert_file_contains "${doc}" 'NFS/NASA primary special remote'
assert_file_contains "${doc}" 'Source Workspace Parity'
assert_file_contains "${doc}" 'Git-Annex should not be used as the source repo parity mechanism.'
assert_file_contains "${doc}" 'preferred content'
assert_file_contains "${doc}" 'No Forge worker should run `git annex drop` without a passing `git annex fsck`'
assert_file_not_contains "${doc}" 'Docker'

assert_file_contains "${runbook}" 'scripts/bootstrap-yukonsys-artifact-annex.sh'
assert_file_contains "${runbook}" 'Source-Workspace Boundary'
assert_file_contains "${runbook}" '--backend SHA256E'
assert_file_contains "${runbook}" '--remote-encryption hybrid'
assert_file_contains "${runbook}" '--remote-mac HMACSHA256'
assert_file_contains "${runbook}" '--numcopies 2'
assert_file_not_contains "${runbook}" 'Docker'

assert_file_contains "${plan}" 'Git-Annex Artifact Plane Implementation Plan'
assert_file_contains "${plan}" 'SHA256E'
assert_file_contains "${plan}" 'forge5'
assert_file_contains "${plan}" 'forge6'

bash -n "${script}"
dry_run_output="$("${script}" --dry-run --repo /tmp/yukonsys-artifact-annex-test --remote-path /mnt/nasa/forge/git-annex/YukonSYS-Artifact-Annex --gpg-key TESTKEY 2>&1)"
grep -Fq -- 'git annex init "forge-artifact-plane"' <<< "${dry_run_output}" || fail "dry-run missing git annex init"
grep -Fq -- 'git config annex.backend SHA256E' <<< "${dry_run_output}" || fail "dry-run missing SHA256E config"
grep -Fq -- 'git config annex.numcopies 2' <<< "${dry_run_output}" || fail "dry-run missing numcopies config"
grep -Fq -- 'type=directory' <<< "${dry_run_output}" || fail "dry-run missing directory special remote"
grep -Fq -- 'encryption=hybrid' <<< "${dry_run_output}" || fail "dry-run missing hybrid encryption"
grep -Fq -- 'mac=HMACSHA256' <<< "${dry_run_output}" || fail "dry-run missing HMACSHA256"
if grep -Fq -- 'Docker' <<< "${dry_run_output}"; then
  fail "dry-run referenced Docker"
fi

assert_file_contains "${SCRIPT_DIR}/run-tests.sh" 'test_git_annex_artifact_plane.sh'

printf 'PASS: %s\n' "$(basename "$0")"
