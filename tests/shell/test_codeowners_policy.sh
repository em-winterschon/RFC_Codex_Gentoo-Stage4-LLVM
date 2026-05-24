#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CODEOWNERS="${REPO_ROOT}/.github/CODEOWNERS"

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

[[ -f "${CODEOWNERS}" ]] || fail "missing ${CODEOWNERS}"
[[ "$(wc -c < "${CODEOWNERS}")" -lt 3145728 ]] || fail "CODEOWNERS exceeds GitHub 3 MB limit"

assert_file_contains "${CODEOWNERS}" "* @RobinWinters @yukon-forge"
assert_file_contains "${CODEOWNERS}" "/.github/ @RobinWinters @yukon-forge"
assert_file_contains "${CODEOWNERS}" "/.github/CODEOWNERS @RobinWinters @yukon-forge"
assert_file_contains "${CODEOWNERS}" "/project-management/ @RobinWinters @yukon-forge"
assert_file_contains "${CODEOWNERS}" "/docs/wiki/ @RobinWinters @yukon-forge"
assert_file_contains "${CODEOWNERS}" "/scripts/publish-wiki.sh @RobinWinters @yukon-forge"
assert_file_contains "${CODEOWNERS}" "/scripts/github_project_seed.py @RobinWinters @yukon-forge"
assert_file_contains "${CODEOWNERS}" "/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/ @RobinWinters @yukon-forge"

python3 - "${CODEOWNERS}" << 'PY'
import pathlib
import re
import sys

codeowners = pathlib.Path(sys.argv[1])
allowed_owners = {"@RobinWinters", "@yukon-forge", "@em-winterschon"}
owner_re = re.compile(r"^(@[A-Za-z0-9_.-]+|@[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$")

for line_number, raw_line in enumerate(codeowners.read_text(encoding="utf-8").splitlines(), 1):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split()
    if len(parts) < 2:
        raise SystemExit(f"{codeowners}:{line_number}: missing owner for pattern {parts[0]!r}")
    pattern, owners = parts[0], parts[1:]
    if pattern.startswith("!"):
        raise SystemExit(f"{codeowners}:{line_number}: CODEOWNERS does not support negation")
    if "[" in pattern or "]" in pattern:
        raise SystemExit(f"{codeowners}:{line_number}: CODEOWNERS does not support character ranges")
    for owner in owners:
        if not owner_re.match(owner):
            raise SystemExit(f"{codeowners}:{line_number}: invalid owner syntax {owner!r}")
        if owner not in allowed_owners:
            raise SystemExit(f"{codeowners}:{line_number}: owner {owner!r} is not in the validated owner allowlist")

print("codeowners-ok")
PY

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
