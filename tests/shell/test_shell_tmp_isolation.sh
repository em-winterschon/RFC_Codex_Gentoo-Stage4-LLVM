#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bad_redirects="$(
  grep -RInE '(^|[[:space:]])(>|2>)[[:space:]]*/tmp/' "${SCRIPT_DIR}"/test_*.sh \
    | grep -v '/test_shell_tmp_isolation.sh:' || true
)"

if [[ -n "${bad_redirects}" ]]; then
  printf '%s\n' "${bad_redirects}" >&2
  fail 'shell tests must write transient output under mktemp-owned directories, not fixed /tmp paths'
fi

bad_reply_queue="$(
  grep -RInF "CODEX_NTFY_REPLY_QUEUE_DIR='/tmp/codex-replies-wrapper'" "${SCRIPT_DIR}"/test_*.sh \
    | grep -v '/test_shell_tmp_isolation.sh:' || true
)"

if [[ -n "${bad_reply_queue}" ]]; then
  printf '%s\n' "${bad_reply_queue}" >&2
  fail 'shell tests must not use a shared fixed ntfy reply queue under /tmp'
fi

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
