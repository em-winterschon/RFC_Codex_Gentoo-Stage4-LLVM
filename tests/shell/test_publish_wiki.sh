#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PUBLISH="${REPO_ROOT}/scripts/publish-wiki.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

source_dir="${temp_dir}/source"
seed_repo="${temp_dir}/seed"
remote_repo="${temp_dir}/wiki.git"
wiki_worktree="${temp_dir}/wiki-worktree"

mkdir -p "${source_dir}"
printf '# Source policy\n' > "${source_dir}/README.md"
printf '# Home\n' > "${source_dir}/Home.md"

git init -q "${seed_repo}"
git -C "${seed_repo}" config user.email test@example.invalid
git -C "${seed_repo}" config user.name 'Test User'
printf '# Old source policy\n' > "${seed_repo}/README.md"
printf '# Old home\n' > "${seed_repo}/Home.md"
git -C "${seed_repo}" add .
git -C "${seed_repo}" commit -q -m 'Seed wiki'
git -C "${seed_repo}" branch -M master
git clone -q --bare "${seed_repo}" "${remote_repo}"

COMMIT_MESSAGE='Sync test wiki' \
  "${PUBLISH}" \
  --source-dir "${source_dir}" \
  --wiki-worktree "${wiki_worktree}" \
  --remote "${remote_repo}" >/tmp/publish-wiki-test.out

test -f "${wiki_worktree}/README.md" || fail 'README.md was not preserved in wiki sync'
grep -q 'Source policy' "${wiki_worktree}/README.md" || fail 'README.md was not copied from source'
grep -q 'Home' "${wiki_worktree}/Home.md" || fail 'Home.md was not copied from source'

printf 'PASS: %s\n' "$(basename "$0")"
