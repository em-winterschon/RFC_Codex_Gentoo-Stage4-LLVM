#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DOC="${REPO_ROOT}/docs/FORGE-COMMUNICATIONS-PROTOCOL.md"
WIKI_DOC="${REPO_ROOT}/docs/wiki/Forge-Communications-Protocol.md"
SIDEBAR="${REPO_ROOT}/docs/wiki/_Sidebar.md"

require_file() {
  local path=$1
  if [[ ! -f "${path}" ]]; then
    printf 'missing file: %s\n' "${path}" >&2
    exit 1
  fi
}

require_grep() {
  local pattern=$1
  local path=$2
  if ! grep -q -- "${pattern}" "${path}"; then
    printf 'missing pattern %q in %s\n' "${pattern}" "${path}" >&2
    exit 1
  fi
}

require_file "${DOC}"
require_file "${WIKI_DOC}"

for path in "${DOC}" "${WIKI_DOC}"; do
  require_grep 'Status: Experimental' "${path}"
  require_grep 'Version: FCP/0.1' "${path}"
  require_grep 'Action Directive Registry' "${path}"
  require_grep 'Approval Classes' "${path}"
  require_grep 'Evidence Levels' "${path}"
  require_grep 'Operational State Machine' "${path}"
  require_grep 'Standing Safety Invariants' "${path}"
  require_grep 'Server SOL MUST remain enabled by default' "${path}"
  require_grep '`MAKE IT SO`' "${path}"
  require_grep '`HOLD`' "${path}"
  require_grep '`PAUSE`' "${path}"
  require_grep '`PLAN FIRST`' "${path}"
  require_grep '`QUERY PRIORITY TRACK`' "${path}"
  require_grep '`E2ET`' "${path}"
  require_grep '`COMMIT + PUSH`' "${path}"
  require_grep '`A4`' "${path}"
  require_grep '`E4`' "${path}"
done

require_grep 'Forge Communications Protocol' "${SIDEBAR}"

if grep -R --line-number 'TODO\\|TBD' "${DOC}" "${WIKI_DOC}"; then
  printf 'FCP docs contain unresolved placeholders\n' >&2
  exit 1
fi

printf 'PASS: %s\n' "$(basename "$0")"
