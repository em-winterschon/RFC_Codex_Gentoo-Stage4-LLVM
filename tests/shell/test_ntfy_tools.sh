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
NTFY_PUBSUB_TUI="${REPO_ROOT}/scripts/ntfy_pubsub_tui.py"
SLACK_WEBHOOK="${REPO_ROOT}/scripts/slack_webhook.py"
GITHUB_NOTIFY="${REPO_ROOT}/.github/scripts/ntfy_repo_event.py"

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
    "${NTFY_PUBSUB_TUI}" \
    "${SLACK_WEBHOOK}" \
    "${GITHUB_NOTIFY}" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/action_plugins/ntfy.py" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/callback_plugins/ntfy.py"
}

test_shell_wrappers_parse() {
  bash -n "${CODEX_NOTIFY_WITH_ENV}" "${CODEX_HOOK_WITH_ENV}"
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

test_codex_ntfy_wrapper_uses_coded_env() {
  local output

  output="$(
    CODEX_NTFY_URL=https://ntfy.sh \
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

  cat >"${payload}" <<'EOF'
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
      --url https://ntfy.sh \
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
test_codex_ntfy_wrapper_uses_coded_env
test_github_event_formatter_renders_pull_request_message
test_codex_notify_event_renders_turn_complete_payload
test_codex_notify_wrapper_sources_env_file
test_codex_hook_wrapper_sources_env_file
test_codex_ntfy_hook_permission_dry_run_and_reply
test_ntfy_pubsub_tui_prints_config
test_slack_webhook_dry_run_renders_payload

printf 'PASS: %s\n' "$(basename "$0")"
