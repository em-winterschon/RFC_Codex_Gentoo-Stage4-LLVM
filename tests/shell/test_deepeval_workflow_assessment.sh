#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ASSESSMENT="${REPO_ROOT}/docs/DEEPEVAL-WORKFLOW-ASSESSMENT.md"
TESTING_STRATEGY="${REPO_ROOT}/docs/TESTING-STRATEGY.md"

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

assert_file_contains "${ASSESSMENT}" "DeepEval Workflow Assessment"
assert_file_contains "${ASSESSMENT}" "https://deepeval.com/docs/vibe-coding"
assert_file_contains "${ASSESSMENT}" "https://deepeval.com/docs/synthesizer-generate-from-contexts"
assert_file_contains "${ASSESSMENT}" "https://deepeval.com/docs/metrics-plan-quality"
assert_file_contains "${ASSESSMENT}" "PlanQualityMetric"
assert_file_contains "${ASSESSMENT}" "tests/evals/"
assert_file_contains "${ASSESSMENT}" 'requirements-dev.txt'
assert_file_contains "${ASSESSMENT}" "Do not use DeepEval as an authority for live infrastructure state."
assert_file_contains "${ASSESSMENT}" "sanitized FCP"
assert_file_contains "${ASSESSMENT}" "optional Jenkins stage"

assert_file_contains "${TESTING_STRATEGY}" "DeepEval Candidate Lane"
assert_file_contains "${TESTING_STRATEGY}" "docs/DEEPEVAL-WORKFLOW-ASSESSMENT.md"
assert_file_contains "${TESTING_STRATEGY}" "advisory pilot only"
assert_file_contains "${TESTING_STRATEGY}" "DeepEval synthetic contexts"

printf 'PASS: %s\n' "$(basename "$0")"
