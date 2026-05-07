#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_DIR="${SOURCE_DIR:-${REPO_ROOT}/docs/wiki}"
WIKI_REPO_SLUG="${WIKI_REPO_SLUG:-em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM}"
WIKI_WORKTREE="${WIKI_WORKTREE:-/tmp/RFC_Codex_Gentoo-Stage4-LLVM.wiki}"
WIKI_REMOTE_URL="${WIKI_REMOTE_URL:-git@github.com:${WIKI_REPO_SLUG}.wiki.git}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-Sync wiki from docs/wiki}"
PUSH=0

usage() {
  cat <<EOF
Usage: publish-wiki.sh [--push] [--source-dir PATH] [--wiki-worktree PATH] [--remote URL]

Syncs ${SOURCE_DIR} into a local checkout of the GitHub wiki repository.

Options:
  --push                 Commit and push to the wiki remote after syncing.
  --source-dir PATH      Override the source directory. Default: ${SOURCE_DIR}
  --wiki-worktree PATH   Override the local wiki checkout path. Default: ${WIKI_WORKTREE}
  --remote URL           Override the wiki remote URL. Default: ${WIKI_REMOTE_URL}
  --help                 Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH=1
      shift
      ;;
    --source-dir)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --wiki-worktree)
      WIKI_WORKTREE="$2"
      shift 2
      ;;
    --remote)
      WIKI_REMOTE_URL="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "${SOURCE_DIR}" ]]; then
  printf 'ERROR: Source directory not found: %s\n' "${SOURCE_DIR}" >&2
  exit 1
fi

if [[ ! -d "${WIKI_WORKTREE}/.git" ]]; then
  rm -rf "${WIKI_WORKTREE}"
  git clone "${WIKI_REMOTE_URL}" "${WIKI_WORKTREE}"
else
  git -C "${WIKI_WORKTREE}" remote set-url origin "${WIKI_REMOTE_URL}"
  git -C "${WIKI_WORKTREE}" fetch origin
  CURRENT_BRANCH="$(git -C "${WIKI_WORKTREE}" rev-parse --abbrev-ref HEAD)"
  git -C "${WIKI_WORKTREE}" pull --ff-only origin "${CURRENT_BRANCH}"
fi

if ! git -C "${WIKI_WORKTREE}" config user.email >/dev/null; then
  git -C "${WIKI_WORKTREE}" config user.email "codex@example.invalid"
fi

if ! git -C "${WIKI_WORKTREE}" config user.name >/dev/null; then
  git -C "${WIKI_WORKTREE}" config user.name "Codex Automation"
fi

find "${WIKI_WORKTREE}" -maxdepth 1 -type f -name '*.md' -delete

while IFS= read -r src_file; do
  base_name="$(basename "${src_file}")"
  cp "${src_file}" "${WIKI_WORKTREE}/${base_name}"
done < <(find "${SOURCE_DIR}" -maxdepth 1 -type f -name '*.md' | sort)

if [[ -z "$(git -C "${WIKI_WORKTREE}" status --porcelain)" ]]; then
  printf 'Wiki checkout is already in sync with %s\n' "${SOURCE_DIR}"
  exit 0
fi

git -C "${WIKI_WORKTREE}" add .

if git -C "${WIKI_WORKTREE}" diff --cached --quiet --exit-code; then
  printf 'No staged wiki changes after sync.\n'
  exit 0
fi

git -C "${WIKI_WORKTREE}" commit -m "${COMMIT_MESSAGE}"

if [[ "${PUSH}" -eq 1 ]]; then
  CURRENT_BRANCH="$(git -C "${WIKI_WORKTREE}" rev-parse --abbrev-ref HEAD)"
  git -C "${WIKI_WORKTREE}" push origin "${CURRENT_BRANCH}"
  printf 'Published wiki content from %s to %s\n' "${SOURCE_DIR}" "${WIKI_REMOTE_URL}"
else
  printf 'Committed wiki mirror locally in %s but did not push.\n' "${WIKI_WORKTREE}"
  printf 'Run with --push after PR approval to publish.\n'
fi
