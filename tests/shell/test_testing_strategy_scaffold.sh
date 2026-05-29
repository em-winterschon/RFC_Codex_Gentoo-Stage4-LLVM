#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

assert_executable() {
  local file="$1"

  [[ -x "${file}" ]] || fail "expected executable file ${file}"
}

assert_file_contains "${REPO_ROOT}/docs/TESTING-STRATEGY.md" "Layered Test Model"
assert_file_contains "${REPO_ROOT}/docs/TESTING-STRATEGY.md" "Robot Framework acceptance"
assert_file_contains "${REPO_ROOT}/docs/TESTING-STRATEGY.md" "unittest"
assert_file_contains "${REPO_ROOT}/docs/TESTING-STRATEGY.md" "doctest"
assert_file_contains "${REPO_ROOT}/docs/TESTING-STRATEGY.md" "IsolatedAsyncioTestCase"
assert_file_contains "${REPO_ROOT}/docs/TESTING-STRATEGY.md" "Jenkins Pipeline"
assert_file_contains "${REPO_ROOT}/docs/TESTING-STRATEGY.md" "AI Agent"

assert_executable "${REPO_ROOT}/tests/python/run-tests.sh"
assert_file_contains "${REPO_ROOT}/tests/python/test_service_validator.py" "unittest.TestCase"
assert_file_contains "${REPO_ROOT}/tests/python/test_service_validator.py" "extract_port_state"

assert_executable "${REPO_ROOT}/tests/robot/run-tests.sh"
assert_file_contains "${REPO_ROOT}/tests/robot/suites/repo_acceptance.robot" "*** Test Cases ***"
assert_file_contains "${REPO_ROOT}/tests/robot/suites/repo_acceptance.robot" "Testing Strategy Document Exists"

assert_file_contains "${REPO_ROOT}/Jenkinsfile" "pipeline"
assert_file_contains "${REPO_ROOT}/Jenkinsfile" "Python Unit Tests"
assert_file_contains "${REPO_ROOT}/Jenkinsfile" "Robot Acceptance Tests"
assert_file_contains "${REPO_ROOT}/Jenkinsfile" "test-results/robot"
assert_file_contains "${REPO_ROOT}/Jenkinsfile" "aiAgent"

assert_file_contains "${REPO_ROOT}/requirements-dev.txt" "robotframework=="
assert_file_contains "${REPO_ROOT}/tests/shell/run-tests.sh" "test_testing_strategy_scaffold.sh"
assert_file_contains "${REPO_ROOT}/tests/shell/run-tests.sh" "tests/python/run-tests.sh"
assert_file_contains "${REPO_ROOT}/tests/shell/run-tests.sh" "tests/robot/run-tests.sh"

printf 'PASS: %s\n' "$(basename "$0")"
