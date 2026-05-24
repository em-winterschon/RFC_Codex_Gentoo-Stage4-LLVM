#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SEED="${REPO_ROOT}/scripts/github_project_seed.py"
LABELS="${REPO_ROOT}/project-management/labels.yml"
MILESTONES="${REPO_ROOT}/project-management/milestones.yml"
ISSUES="${REPO_ROOT}/project-management/issue-seed.yml"
DOCS="${REPO_ROOT}/docs/GITHUB-PROJECT-MANAGEMENT.md"
WIKI="${REPO_ROOT}/docs/wiki/GitHub-Project-Management.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
create_project_output="${tmpdir}/github-project-seed-project.out"

assert_file_contains "${REPO_ROOT}/.github/ISSUE_TEMPLATE/roadmap_task.yml" "name: Roadmap task"
assert_file_contains "${REPO_ROOT}/.github/ISSUE_TEMPLATE/change_control.yml" "name: Change control"
assert_file_contains "${REPO_ROOT}/.github/ISSUE_TEMPLATE/service_role.yml" "name: Service role"
assert_file_contains "${REPO_ROOT}/.github/ISSUE_TEMPLATE/blocker.yml" "name: Blocker"
assert_file_contains "${REPO_ROOT}/.github/ISSUE_TEMPLATE/config.yml" "blank_issues_enabled: false"
assert_file_contains "${LABELS}" "area:identity-aaa"
assert_file_contains "${LABELS}" "type:epic"
assert_file_contains "${LABELS}" "type:task"
assert_file_contains "${LABELS}" "rel:depends-on"
assert_file_contains "${LABELS}" "rel:blocked-by"
assert_file_contains "${MILESTONES}" "Identity/RBAC/AAA"
assert_file_contains "${ISSUES}" "roadmap_source: docs/ROADMAP-AND-TODO.md"
assert_file_contains "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md" "AAA-004"
assert_file_contains "${DOCS}" "GitHub Query URLs"
assert_file_contains "${DOCS}" "read:project"
assert_file_contains "${DOCS}" "Kanban Status"
assert_file_contains "${WIKI}" "GitHub Query URLs"
assert_file_contains "${WIKI}" "Kanban Status"
assert_file_contains "${SEED}" "verify_project_scope"
assert_file_contains "${SEED}" "Roadmap Status"
assert_file_contains "${SEED}" "Kanban Status"
assert_file_contains "${SEED}" "add_issues_to_project"
assert_file_contains "${SEED}" "resolve_dependency_numbers"
assert_file_contains "${SEED}" "apply_issue_relationships"
assert_file_contains "${SEED}" "update_project_item_fields"

python3 - "${REPO_ROOT}/.github/ISSUE_TEMPLATE" "${REPO_ROOT}/project-management" << 'PY'
import pathlib
import sys
import yaml

for root in sys.argv[1:]:
    for path in sorted(pathlib.Path(root).glob("*.yml")):
        with path.open("r", encoding="utf-8") as handle:
            yaml.safe_load(handle)
print("yaml-ok")
PY

dry_run="$("${SEED}" --repo example/example --emit-query-urls)"
grep -Fq 'DRY-RUN: no GitHub mutations will be performed' <<< "${dry_run}" ||
  fail 'dry run did not state mutation policy'
grep -Fq 'label: area:identity-aaa' <<< "${dry_run}" ||
  fail 'dry run did not include expected label'
grep -Fq 'milestone: Identity/RBAC/AAA' <<< "${dry_run}" ||
  fail 'dry run did not include expected milestone'
grep -Fq 'issue: [AAA-004]' <<< "${dry_run}" ||
  fail 'dry run did not include expected seeded issue'
grep -Fq 'epic: [EPIC] Identity/RBAC/AAA' <<< "${dry_run}" ||
  fail 'dry run did not include expected epic issue'
grep -Fq 'relationship edges:' <<< "${dry_run}" ||
  fail 'dry run did not summarize relationship edges'
grep -Fq 'https://github.com/example/example/issues/new?template=roadmap_task.yml' <<< "${dry_run}" ||
  fail 'dry run did not include issue query URL'

if "${SEED}" --repo example/example --create-project > "${create_project_output}" 2>&1; then
  fail 'create-project succeeded without --apply'
fi
grep -Fq -- '--create-project requires --apply' "${create_project_output}" ||
  fail 'create-project refusal message missing'

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
