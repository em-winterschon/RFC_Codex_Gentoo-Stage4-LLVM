#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NTFY_NOTIFY="${REPO_ROOT}/scripts/ntfy_notify.py"
CODEX_NOTIFY="${REPO_ROOT}/scripts/codex-ntfy.sh"
CODEX_NOTIFY_EVENT="${REPO_ROOT}/scripts/codex_notify_event.py"
CODEX_NTFY_HOOK="${REPO_ROOT}/scripts/codex_ntfy_hook.py"
CODEX_NOTIFY_WITH_ENV="${REPO_ROOT}/scripts/codex_notify_with_env.sh"
CODEX_HOOK_WITH_ENV="${REPO_ROOT}/scripts/codex_hook_with_env.sh"
CODEX_APPROVAL_WATCHER="${REPO_ROOT}/scripts/codex_approval_watcher.py"
CODEX_APPROVAL_WATCHER_WITH_ENV="${REPO_ROOT}/scripts/codex_approval_watcher_with_env.sh"
NTFY_PUBSUB_TUI="${REPO_ROOT}/scripts/ntfy_pubsub_tui.py"
SLACK_WEBHOOK="${REPO_ROOT}/scripts/slack_webhook.py"
GITHUB_NOTIFY="${REPO_ROOT}/.github/scripts/ntfy_repo_event.py"
CODEX_REPLY_LISTENER="${REPO_ROOT}/scripts/codex_ntfy_reply_listener.py"
CODEX_REPLY_LISTENER_WITH_ENV="${REPO_ROOT}/scripts/codex_ntfy_reply_listener_with_env.sh"
LAN_NTFY_URL="http://msg-sun99-ntfysys.rfc1918.host"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  [[ "${actual}" == "${expected}" ]] || fail "expected '${expected}', got '${actual}'"
}

test_python_sources_compile() {
  python3 -m py_compile \
    "${NTFY_NOTIFY}" \
    "${CODEX_NOTIFY_EVENT}" \
    "${CODEX_NTFY_HOOK}" \
    "${REPO_ROOT}/scripts/codex_ntfy_policy.py" \
    "${REPO_ROOT}/scripts/codex_ntfy_reply_queue.py" \
    "${CODEX_REPLY_LISTENER}" \
    "${CODEX_APPROVAL_WATCHER}" \
    "${NTFY_PUBSUB_TUI}" \
    "${SLACK_WEBHOOK}" \
    "${GITHUB_NOTIFY}" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/action_plugins/ntfy.py" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/callback_plugins/ntfy.py"
}

test_shell_wrappers_parse() {
  bash -n "${CODEX_NOTIFY}" "${CODEX_NOTIFY_WITH_ENV}" "${CODEX_HOOK_WITH_ENV}" "${CODEX_APPROVAL_WATCHER_WITH_ENV}" "${CODEX_REPLY_LISTENER_WITH_ENV}"
}

test_ntfy_notify_dry_run_renders_payload() {
  local output

  output="$(
    python3 "${NTFY_NOTIFY}" \
      --dry-run \
      --url "${LAN_NTFY_URL}" \
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

test_ntfy_notify_requires_configured_url() {
  local output status

  set +e
  output="$(
    env -u NTFY_URL \
      python3 "${NTFY_NOTIFY}" \
      --dry-run \
      --topic codex-test \
      --state info \
      --message "validation complete" 2>&1
  )"
  status=$?
  set -e

  [[ "${status}" -eq 2 ]] || fail "expected missing URL to exit 2, got ${status}: ${output}"
  assert_contains "${output}" "ntfy URL is not configured"
}

test_codex_ntfy_wrapper_skips_without_public_fallback() {
  local output

  output="$(
    env -u CODEX_NTFY_URL -u NTFY_URL \
      CODEX_NTFY_TOPIC=codex-topic \
      bash "${CODEX_NOTIFY}" info "done" --dry-run
  )"

  assert_contains "${output}" '"skipped": true'
  assert_contains "${output}" 'missing URL configuration'
}

test_codex_ntfy_wrapper_uses_coded_env() {
  local output

  output="$(
    CODEX_NTFY_URL="${LAN_NTFY_URL}" \
      CODEX_NTFY_TOPIC=codex-topic \
      bash "${CODEX_NOTIFY}" success "done" --title "Codex done" --dry-run
  )"

  assert_contains "${output}" '"topic": "codex-topic"'
  assert_contains "${output}" '"Title": "Codex done"'
  assert_contains "${output}" '"state": "success"'
}

test_github_event_formatter_renders_pull_request_message() {
  local temp_dir payload output
  temp_dir="$(mktemp -d)"
  payload="${temp_dir}/pull_request.json"

  cat > "${payload}" << 'EOF'
{
  "action": "opened",
  "repository": {
    "full_name": "em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM",
    "html_url": "https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM"
  },
  "sender": {
    "login": "codex"
  },
  "pull_request": {
    "number": 9,
    "title": "Add ntfy support",
    "html_url": "https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM/pull/9",
    "base": { "ref": "main" },
    "head": { "ref": "codex/add-ntfy-notifications" },
    "merged": false
  }
}
EOF

  output="$(
    python3 "${GITHUB_NOTIFY}" \
      --dry-run \
      --allow-missing-config \
      --url "${LAN_NTFY_URL}" \
      --topic repo-topic \
      --event-name pull_request \
      --event-path "${payload}"
  )"

  assert_contains "${output}" '"topic": "repo-topic"'
  assert_contains "${output}" 'PR opened: #9 Add ntfy support'
  assert_contains "${output}" 'pull_request'
  rm -rf "${temp_dir}"
}

test_codex_notify_event_renders_turn_complete_payload() {
  local payload output
  payload='{"type":"agent-turn-complete","thread-id":"thread-1","turn-id":"turn-2","cwd":"/root/project","input-messages":["do work"],"last-assistant-message":"done"}'

  output="$(
    CODEX_NTFY_URL="${LAN_NTFY_URL}" \
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
  cat > "${env_file}" << 'EOF'
export CODEX_NTFY_URL='http://msg-sun99-ntfysys.rfc1918.host'
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
  cat > "${env_file}" << 'EOF'
export CODEX_NTFY_URL='http://msg-sun99-ntfysys.rfc1918.host'
export CODEX_NTFY_ALERT_TOPIC='codex-alerts-wrapper'
export CODEX_NTFY_REPLY_TOPIC='codex-replies-wrapper'
EOF

  output="$(
    CODEX_NTFY_ENV_FILE="${env_file}" \
      CODEX_NTFY_TEST_REQUEST_ID='12345678' \
      bash "${CODEX_HOOK_WITH_ENV}" --dry-run <<< '{"hook_event_name":"PermissionRequest","tool_input":{"description":"Need root access","command":"emerge -avuDN @world"}}'
  )"

  assert_contains "${output}" '"topic": "codex-alerts-wrapper"'
  rm -rf "${temp_dir}"
}

test_codex_reply_listener_wrapper_sources_env_file() {
  local temp_dir env_file output
  temp_dir="$(mktemp -d)"
  env_file="${temp_dir}/ntfy.env"
  cat > "${env_file}" << 'EOF'
export CODEX_NTFY_REPLY_TOPIC='codex-replies-wrapper'
export CODEX_NTFY_REPLY_QUEUE_DIR='/tmp/codex-replies-wrapper'
EOF

  output="$(
    CODEX_NTFY_ENV_FILE="${env_file}" \
      CODEX_NTFY_REPLY_LISTENER_TEST_MESSAGES='allow req-1' \
      bash "${CODEX_REPLY_LISTENER_WITH_ENV}" --dry-run --once --from-start
  )"

  assert_contains "${output}" '"decision": "allow"'
  assert_contains "${output}" '"kind": "permission_reply"'
  rm -rf "${temp_dir}"
}

test_codex_reply_listener_requires_local_url() {
  local output status

  set +e
  output="$(
    env -u CODEX_NTFY_URL -u NTFY_URL -u NTFY_SERVER \
      CODEX_NTFY_REPLY_TOPIC=codex-replies \
      python3 "${CODEX_REPLY_LISTENER}" --once 2>&1
  )"
  status=$?
  set -e

  [[ "${status}" -eq 2 ]] || fail "expected missing listener URL to exit 2, got ${status}: ${output}"
  assert_contains "${output}" "CODEX_NTFY_URL/NTFY_URL/NTFY_SERVER is not configured"
}

test_codex_ntfy_hook_permission_dry_run_and_reply() {
  local payload dry_output reply_output
  payload='{"hook_event_name":"PermissionRequest","tool_input":{"description":"Need root access","command":"emerge -avuDN @world"}}'

  dry_output="$(
    CODEX_NTFY_URL="${LAN_NTFY_URL}" \
      CODEX_NTFY_ALERT_TOPIC=codex-alerts \
      CODEX_NTFY_REPLY_TOPIC=codex-replies \
      python3 "${CODEX_NTFY_HOOK}" --dry-run <<< "${payload}"
  )"

  assert_contains "${dry_output}" '"topic": "codex-alerts"'
  assert_contains "${dry_output}" 'Codex approval needed'

  reply_output="$(
    CODEX_NTFY_URL="${LAN_NTFY_URL}" \
      CODEX_NTFY_ALERT_TOPIC=codex-alerts \
      CODEX_NTFY_REPLY_TOPIC=codex-replies \
      CODEX_NTFY_TEST_REQUEST_ID='12345678' \
      CODEX_NTFY_TEST_REPLIES='allow 12345678' \
      python3 "${CODEX_NTFY_HOOK}" <<< '{"hook_event_name":"PermissionRequest","tool_input":{"description":"Need root access","command":"emerge -avuDN @world"}}'
  )"

  assert_contains "${reply_output}" '"decision"'
  assert_contains "${reply_output}" '"allow"'
}

test_codex_reply_listener_persists_normalized_queue_entries() {
  local temp_dir state_file pending_file content
  temp_dir="$(mktemp -d)"
  state_file="${temp_dir}/listener-state.json"

  CODEX_NTFY_REPLY_TOPIC=codex-replies \
    CODEX_NTFY_REPLY_QUEUE_DIR="${temp_dir}/queue" \
    CODEX_NTFY_REPLY_LISTENER_TEST_MESSAGES=$'allow req-1\nreq-2: continue with stage3' \
    python3 "${CODEX_REPLY_LISTENER}" --once --from-start --state-file "${state_file}"

  pending_file="$(find "${temp_dir}/queue/pending" -type f -name '*.json' | sort | head -n 1)"
  [[ -n "${pending_file}" ]] || fail "expected pending reply queue files"
  content="$(find "${temp_dir}/queue/pending" -type f -name '*.json' -print0 | xargs -0 cat)"
  assert_contains "${content}" '"request_id": "req-1"'
  assert_contains "${content}" '"request_id": "req-2"'
  assert_contains "${content}" '"kind": "question_reply"'
  rm -rf "${temp_dir}"
}

test_codex_ntfy_policy_file_overrides_mode() {
  local temp_dir policy_file output
  temp_dir="$(mktemp -d)"
  policy_file="${temp_dir}/policy.json"
  cat > "${policy_file}" << 'EOF'
{
  "replyKinds": {
    "permission_reply": {
      "mode": "advisory"
    }
  }
}
EOF

  output="$(
    CODEX_NTFY_POLICY_FILE="${policy_file}" \
      PYTHONPATH="${REPO_ROOT}/scripts" \
      python3 - <<'PY'
import codex_ntfy_policy as p
print(p.mode_for_kind("permission_reply"))
print(p.mode_for_kind("question_reply"))
PY
  )"

  assert_contains "${output}" 'advisory'
  assert_contains "${output}" 'state-driven'
  rm -rf "${temp_dir}"
}

test_codex_reply_listener_parses_syslog_wrapped_reply_messages() {
  local temp_dir state_file content
  temp_dir="$(mktemp -d)"
  state_file="${temp_dir}/listener-state.json"

  CODEX_NTFY_REPLY_TOPIC=codex-replies \
    CODEX_NTFY_REPLY_QUEUE_DIR="${temp_dir}/queue" \
    CODEX_NTFY_REPLY_LISTENER_TEST_MESSAGES='<134>1 2026-04-25T18:54:35Z host codex-reply-test 1 - - state="notice" severity="info" severity_code="6" message="allow req-syslog-1"' \
    python3 "${CODEX_REPLY_LISTENER}" --once --from-start --state-file "${state_file}"

  content="$(find "${temp_dir}/queue/pending" -type f -name '*.json' -print0 | xargs -0 cat)"
  assert_contains "${content}" '"request_id": "req-syslog-1"'
  assert_contains "${content}" '"decision": "allow"'
  rm -rf "${temp_dir}"
}

test_codex_ntfy_hook_consumes_reply_queue_entries() {
  local temp_dir state_file output
  temp_dir="$(mktemp -d)"
  state_file="${temp_dir}/listener-state.json"

  CODEX_NTFY_REPLY_TOPIC=codex-replies \
    CODEX_NTFY_REPLY_QUEUE_DIR="${temp_dir}/queue" \
    CODEX_NTFY_REPLY_LISTENER_TEST_MESSAGES='allow 12345678' \
    python3 "${CODEX_REPLY_LISTENER}" --once --from-start --state-file "${state_file}"

  output="$(
    CODEX_NTFY_REPLY_TOPIC=codex-replies \
      CODEX_NTFY_REPLY_QUEUE_DIR="${temp_dir}/queue" \
      CODEX_NTFY_TEST_REQUEST_ID='12345678' \
      python3 "${CODEX_NTFY_HOOK}" <<< '{"hook_event_name":"PermissionRequest","tool_input":{"description":"Need root access","command":"emerge -avuDN @world"}}'
  )"

  assert_contains "${output}" '"decision"'
  assert_contains "${output}" '"allow"'
  [[ -d "${temp_dir}/queue/processed" ]] || fail "expected processed queue directory"
  find "${temp_dir}/queue/processed" -type f -name '*.json' | grep -q . || fail "expected processed reply file"
  rm -rf "${temp_dir}"
}

test_codex_ntfy_hook_respects_advisory_policy_for_queue_entries() {
  local temp_dir state_file policy_file output
  temp_dir="$(mktemp -d)"
  state_file="${temp_dir}/listener-state.json"
  policy_file="${temp_dir}/policy.json"
  cat > "${policy_file}" << 'EOF'
{
  "replyKinds": {
    "permission_reply": {
      "mode": "advisory"
    }
  }
}
EOF

  CODEX_NTFY_REPLY_TOPIC=codex-replies \
    CODEX_NTFY_REPLY_QUEUE_DIR="${temp_dir}/queue" \
    CODEX_NTFY_REPLY_LISTENER_TEST_MESSAGES='allow 87654321' \
    python3 "${CODEX_REPLY_LISTENER}" --once --from-start --state-file "${state_file}"

  output="$(
    CODEX_NTFY_REPLY_TOPIC=codex-replies \
      CODEX_NTFY_POLICY_FILE="${policy_file}" \
      CODEX_NTFY_REPLY_QUEUE_DIR="${temp_dir}/queue" \
      CODEX_NTFY_TEST_REQUEST_ID='87654321' \
      python3 "${CODEX_NTFY_HOOK}" <<< '{"hook_event_name":"PermissionRequest","tool_input":{"description":"Need root access","command":"emerge -avuDN @world"}}'
  )"

  [[ -z "${output}" ]] || fail "expected no hook decision output for advisory policy, got '${output}'"
  find "${temp_dir}/queue/processed" -type f -name '*.json' | grep -q . || fail "expected advisory reply to be moved to processed"
  rm -rf "${temp_dir}"
}

test_approval_watcher_exec_request_dry_run() {
  local temp_dir log_file state_file output
  temp_dir="$(mktemp -d)"
  log_file="${temp_dir}/codex-tui.log"
  state_file="${temp_dir}/state.json"
  cat > "${log_file}" << 'EOF'
2026-04-24T00:00:00.000000Z  INFO session_loop{thread_id=thread-1}: codex_core::stream_events_utils: ToolCall: exec_command {"cmd":"bash -lc 'emerge -avuDN @world'","justification":"Need to update packages","sandbox_permissions":"require_escalated","workdir":"/root"} thread_id=thread-1
2026-04-24T00:00:02.000000Z  INFO session_loop{thread_id=thread-1}:submission_dispatch{otel.name="op.dispatch.exec_approval" submission.id="req-123" codex.op="exec_approval"}: codex_core::codex: new
EOF

  output="$(
    CODEX_NTFY_URL="${LAN_NTFY_URL}" \
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
  cat > "${log_file}" << 'EOF'
2026-04-24T00:00:00.000000Z  INFO session_loop{thread_id=thread-1}: codex_core::stream_events_utils: ToolCall: apply_patch *** Begin Patch
2026-04-24T00:00:02.000000Z  INFO session_loop{thread_id=thread-1}:submission_dispatch{otel.name="op.dispatch.patch_approval" submission.id="patch-456" codex.op="patch_approval"}: codex_core::codex: new
EOF

  output="$(
    CODEX_NTFY_URL="${LAN_NTFY_URL}" \
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

test_ntfy_pubsub_tui_prints_config() {
  local output

  output="$(
    NTFY_URL=https://ntfy.example.invalid \
      NTFY_ALERT_TOPIC=alerts-topic \
      NTFY_REPLY_TOPIC=replies-topic \
      python3 "${NTFY_PUBSUB_TUI}" --print-config
  )"

  assert_contains "${output}" '"server": "https://ntfy.example.invalid"'
  assert_contains "${output}" '"alert_topic": "alerts-topic"'
  assert_contains "${output}" '"reply_topic": "replies-topic"'
}

test_public_ntfy_service_url_is_not_reintroduced() {
  if grep -R -I --exclude-dir='__pycache__' "https://ntfy\\.sh" \
    "${REPO_ROOT}/scripts" \
    "${REPO_ROOT}/ntfy.env.example" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/action_plugins" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/callback_plugins" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/ansible.cfg" \
    > /dev/null; then
    fail "public ntfy service URL fallback was reintroduced"
  fi
}

test_slack_webhook_dry_run_renders_payload() {
  local output

  output="$(
    python3 "${SLACK_WEBHOOK}" \
      --webhook-url https://hooks.slack.example.invalid/services/test \
      --title "Codex update" \
      --dry-run \
      "validation complete"
  )"

  assert_contains "${output}" '"webhook_url": "https://hooks.slack.example.invalid/services/test"'
  assert_contains "${output}" '"text": "*Codex update*'
  assert_contains "${output}" 'validation complete"'
}

test_python_sources_compile
test_shell_wrappers_parse
test_ntfy_notify_dry_run_renders_payload
test_ntfy_notify_requires_configured_url
test_codex_ntfy_wrapper_skips_without_public_fallback
test_codex_ntfy_wrapper_uses_coded_env
test_github_event_formatter_renders_pull_request_message
test_codex_notify_event_renders_turn_complete_payload
test_codex_notify_wrapper_sources_env_file
test_codex_hook_wrapper_sources_env_file
test_codex_reply_listener_wrapper_sources_env_file
test_codex_reply_listener_requires_local_url
test_codex_ntfy_hook_permission_dry_run_and_reply
test_codex_reply_listener_persists_normalized_queue_entries
test_codex_ntfy_policy_file_overrides_mode
test_codex_reply_listener_parses_syslog_wrapped_reply_messages
test_codex_ntfy_hook_consumes_reply_queue_entries
test_codex_ntfy_hook_respects_advisory_policy_for_queue_entries
test_approval_watcher_exec_request_dry_run
test_approval_watcher_patch_request_dry_run
test_ntfy_pubsub_tui_prints_config
test_public_ntfy_service_url_is_not_reintroduced
test_slack_webhook_dry_run_renders_payload

printf 'PASS: %s\n' "$(basename "$0")"
