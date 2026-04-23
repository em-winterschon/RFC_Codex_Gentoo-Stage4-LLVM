#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NTFY_NOTIFY="${REPO_ROOT}/scripts/ntfy_notify.py"
CODEX_NOTIFY="${REPO_ROOT}/scripts/codex-ntfy.sh"
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
    "${GITHUB_NOTIFY}" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/action_plugins/ntfy.py" \
    "${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/callback_plugins/ntfy.py"
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

test_python_sources_compile
test_ntfy_notify_dry_run_renders_payload
test_codex_ntfy_wrapper_uses_coded_env
test_github_event_formatter_renders_pull_request_message

printf 'PASS: %s\n' "$(basename "$0")"
