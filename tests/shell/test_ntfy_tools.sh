#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NTFY_NOTIFY="${REPO_ROOT}/scripts/ntfy_notify.py"
CODEX_NOTIFY_EVENT="${REPO_ROOT}/scripts/codex_notify_event.py"
CODEX_NTFY_HOOK="${REPO_ROOT}/scripts/codex_ntfy_hook.py"
CODEX_NOTIFY_WITH_ENV="${REPO_ROOT}/scripts/codex_notify_with_env.sh"
CODEX_HOOK_WITH_ENV="${REPO_ROOT}/scripts/codex_hook_with_env.sh"
CODEX_APPROVAL_WATCHER="${REPO_ROOT}/scripts/codex_approval_watcher.py"
CODEX_APPROVAL_WATCHER_WITH_ENV="${REPO_ROOT}/scripts/codex_approval_watcher_with_env.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

test_python_sources_compile() {
  python3 -m py_compile \
    "${NTFY_NOTIFY}" \
    "${CODEX_NOTIFY_EVENT}" \
    "${CODEX_NTFY_HOOK}" \
    "${CODEX_APPROVAL_WATCHER}"
}

test_shell_wrappers_parse() {
  bash -n \
    "${CODEX_NOTIFY_WITH_ENV}" \
    "${CODEX_HOOK_WITH_ENV}" \
    "${CODEX_APPROVAL_WATCHER_WITH_ENV}"
}

test_ntfy_notify_dry_run_renders_payload() {
  local output

  output="$(
    python3 "${NTFY_NOTIFY}" \
      --dry-run \
      --url https://ntfy.sh \
      --topic codex-test \
      --state success \
      --app-name codex \
      --title "Codex success" \
      --message "validation complete" \
      --tag codex
  )"

  assert_contains "${output}" '"topic": "codex-test"'
  assert_contains "${output}" '"Priority": "3"'
  assert_contains "${output}" '"Title": "Codex success"'
  assert_contains "${output}" 'validation complete'
}

test_codex_notify_event_renders_turn_complete_payload() {
  local payload output
  payload='{"type":"agent-turn-complete","thread-id":"thread-1","turn-id":"turn-2","cwd":"/root/project","input-messages":["do work"],"last-assistant-message":"done"}'

  output="$(
    CODEX_NTFY_TOPIC=codex-alerts \
    python3 "${CODEX_NOTIFY_EVENT}" --dry-run "${payload}"
  )"

  assert_contains "${output}" '"topic": "codex-alerts"'
  assert_contains "${output}" 'thread=thread-1'
  assert_contains "${output}" 'assistant=done'
}

test_codex_notify_wrapper_sources_env_file() {
  local temp_dir env_file output
  temp_dir="$(mktemp -d)"
  env_file="${temp_dir}/ntfy.env"
  cat >"${env_file}" <<'EOF'
export CODEX_NTFY_URL='https://ntfy.sh'
export CODEX_NTFY_TOPIC='codex-wrapper-topic'
EOF

  output="$(
    CODEX_NTFY_ENV_FILE="${env_file}" \
    bash "${CODEX_NOTIFY_WITH_ENV}" --dry-run '{"type":"agent-turn-complete","thread-id":"thread-1","turn-id":"turn-2","cwd":"/root/project","input-messages":["do work"],"last-assistant-message":"done"}'
  )"

  assert_contains "${output}" '"topic": "codex-wrapper-topic"'
  rm -rf "${temp_dir}"
}

test_codex_hook_wrapper_sources_env_file() {
  local temp_dir env_file output
  temp_dir="$(mktemp -d)"
  env_file="${temp_dir}/ntfy.env"
  cat >"${env_file}" <<'EOF'
export CODEX_NTFY_ALERT_TOPIC='codex-alerts-wrapper'
export CODEX_NTFY_REPLY_TOPIC='codex-replies-wrapper'
EOF

  output="$(
    CODEX_NTFY_ENV_FILE="${env_file}" \
    CODEX_NTFY_TEST_REQUEST_ID='12345678' \
    bash "${CODEX_HOOK_WITH_ENV}" --dry-run <<<'{"hook_event_name":"PermissionRequest","tool_input":{"description":"Need root access","command":"emerge -avuDN @world"}}'
  )"

  assert_contains "${output}" '"topic": "codex-alerts-wrapper"'
  rm -rf "${temp_dir}"
}

test_codex_ntfy_hook_permission_dry_run_and_reply() {
  local payload dry_output reply_output
  payload='{"hook_event_name":"PermissionRequest","tool_input":{"description":"Need root access","command":"emerge -avuDN @world"}}'

  dry_output="$(
    CODEX_NTFY_ALERT_TOPIC=codex-alerts \
    CODEX_NTFY_REPLY_TOPIC=codex-replies \
    python3 "${CODEX_NTFY_HOOK}" --dry-run <<<"${payload}"
  )"

  assert_contains "${dry_output}" '"topic": "codex-alerts"'
  assert_contains "${dry_output}" 'Codex approval needed'

  reply_output="$(
    CODEX_NTFY_ALERT_TOPIC=codex-alerts \
    CODEX_NTFY_REPLY_TOPIC=codex-replies \
    CODEX_NTFY_TEST_REQUEST_ID='12345678' \
    CODEX_NTFY_TEST_REPLIES='allow 12345678' \
    python3 "${CODEX_NTFY_HOOK}" <<<'{"hook_event_name":"PermissionRequest","tool_input":{"description":"Need root access","command":"emerge -avuDN @world"}}'
  )"

  assert_contains "${reply_output}" '"decision"'
  assert_contains "${reply_output}" '"allow"'
}

test_approval_watcher_exec_request_dry_run() {
  local temp_dir log_file state_file output
  temp_dir="$(mktemp -d)"
  log_file="${temp_dir}/codex-tui.log"
  state_file="${temp_dir}/state.json"
  cat >"${log_file}" <<'EOF'
2026-04-24T00:00:00.000000Z  INFO session_loop{thread_id=thread-1}: codex_core::stream_events_utils: ToolCall: exec_command {"cmd":"bash -lc 'emerge -avuDN @world'","justification":"Need to update packages","sandbox_permissions":"require_escalated","workdir":"/root"} thread_id=thread-1
2026-04-24T00:00:02.000000Z  INFO session_loop{thread_id=thread-1}:submission_dispatch{otel.name="op.dispatch.exec_approval" submission.id="req-123" codex.op="exec_approval"}: codex_core::codex: new
EOF

  output="$(
    CODEX_NTFY_ALERT_TOPIC=codex-alerts \
    python3 "${CODEX_APPROVAL_WATCHER}" \
      --dry-run \
      --from-start \
      --once \
      --log-file "${log_file}" \
      --state-file "${state_file}"
  )"

  assert_contains "${output}" '"topic": "codex-alerts"'
  assert_contains "${output}" 'Codex exec approval needed'
  assert_contains "${output}" 'Need to update packages'
  assert_contains "${output}" "emerge -avuDN @world"
  rm -rf "${temp_dir}"
}

test_approval_watcher_patch_request_dry_run() {
  local temp_dir log_file state_file output
  temp_dir="$(mktemp -d)"
  log_file="${temp_dir}/codex-tui.log"
  state_file="${temp_dir}/state.json"
  cat >"${log_file}" <<'EOF'
2026-04-24T00:00:00.000000Z  INFO session_loop{thread_id=thread-1}: codex_core::stream_events_utils: ToolCall: apply_patch *** Begin Patch
2026-04-24T00:00:02.000000Z  INFO session_loop{thread_id=thread-1}:submission_dispatch{otel.name="op.dispatch.patch_approval" submission.id="patch-456" codex.op="patch_approval"}: codex_core::codex: new
EOF

  output="$(
    CODEX_NTFY_ALERT_TOPIC=codex-alerts \
    python3 "${CODEX_APPROVAL_WATCHER}" \
      --dry-run \
      --from-start \
      --once \
      --log-file "${log_file}" \
      --state-file "${state_file}"
  )"

  assert_contains "${output}" '"topic": "codex-alerts"'
  assert_contains "${output}" 'Codex patch approval needed'
  rm -rf "${temp_dir}"
}

test_python_sources_compile
test_shell_wrappers_parse
test_ntfy_notify_dry_run_renders_payload
test_codex_notify_event_renders_turn_complete_payload
test_codex_notify_wrapper_sources_env_file
test_codex_hook_wrapper_sources_env_file
test_codex_ntfy_hook_permission_dry_run_and_reply
test_approval_watcher_exec_request_dry_run
test_approval_watcher_patch_request_dry_run

printf 'PASS: %s\n' "$(basename "$0")"
