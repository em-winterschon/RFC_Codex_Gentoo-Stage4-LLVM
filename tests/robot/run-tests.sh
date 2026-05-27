#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULT_DIR="${REPO_ROOT}/test-results/robot"

if ! command -v robot > /dev/null 2>&1; then
  printf 'FAIL: robot command not found. Install requirements-dev.txt first.\n' >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"
robot \
  --outputdir "${RESULT_DIR}" \
  --xunit xunit.xml \
  --variable "REPO_ROOT:${REPO_ROOT}" \
  "${SCRIPT_DIR}/suites"
