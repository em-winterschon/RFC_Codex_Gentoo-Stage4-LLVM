#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALLER="${REPO_ROOT}/scripts/install_codex_approval_watcher_service.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

output="$(
  SERVICE_NAME=test-codex-approval-watcher \
  LIBEXEC_DIR=/tmp/libexec-test \
  INITD_DIR=/tmp/initd-test \
  CONFD_DIR=/tmp/confd-test \
  LOG_DIR=/tmp/log-test \
  INSTALL_REPO_ROOT=/srv/codex/repo \
  INSTALL_ENV_FILE=/srv/codex/ntfy.env \
  INSTALL_LOG_FILE=/srv/codex/codex-tui.log \
  INSTALL_STATE_FILE=/srv/codex/approval-state.json \
  bash "${INSTALLER}" --dry-run --no-enable --no-start
)"

assert_contains "${output}" "/tmp/libexec-test/test-codex-approval-watcher"
assert_contains "${output}" "codex_approval_watcher_repo_root=\"/srv/codex/repo\""
assert_contains "${output}" "codex_approval_watcher_env_file=\"/srv/codex/ntfy.env\""
assert_contains "${output}" "codex_approval_watcher_log_file=\"/srv/codex/codex-tui.log\""
assert_contains "${output}" "codex_approval_watcher_state_file=\"/srv/codex/approval-state.json\""
assert_contains "${output}" "exec /bin/bash \"\${codex_approval_watcher_repo_root}/scripts/codex_approval_watcher_with_env.sh\""

printf 'PASS: %s\n' "$(basename "$0")"
