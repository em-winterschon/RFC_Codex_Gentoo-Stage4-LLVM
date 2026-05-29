#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALLER="${REPO_ROOT}/scripts/install_codex_ntfy_reply_listener_service.sh"

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
  SERVICE_NAME=test-codex-ntfy-reply-listener \
    LIBEXEC_DIR=/tmp/libexec-test \
    INITD_DIR=/tmp/initd-test \
    CONFD_DIR=/tmp/confd-test \
    LOG_DIR=/tmp/log-test \
    INSTALL_REPO_ROOT=/srv/codex/repo \
    INSTALL_ENV_FILE=/srv/codex/ntfy.env \
    INSTALL_STATE_FILE=/srv/codex/reply-state.json \
    INSTALL_QUEUE_DIR=/srv/codex/replies \
    bash "${INSTALLER}" --dry-run --no-enable --no-start
)"

assert_contains "${output}" "/tmp/libexec-test/test-codex-ntfy-reply-listener"
assert_contains "${output}" "codex_ntfy_reply_listener_repo_root=\"/srv/codex/repo\""
assert_contains "${output}" "codex_ntfy_reply_listener_env_file=\"/srv/codex/ntfy.env\""
assert_contains "${output}" "codex_ntfy_reply_listener_state_file=\"/srv/codex/reply-state.json\""
assert_contains "${output}" "codex_ntfy_reply_listener_queue_dir=\"/srv/codex/replies\""
assert_contains "${output}" "exec /bin/bash \"\${codex_ntfy_reply_listener_repo_root}/scripts/codex_ntfy_reply_listener_with_env.sh\""

printf 'PASS: %s\n' "$(basename "$0")"
