#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NOTIFY_BIN="${REPO_ROOT}/scripts/ntfy_notify.py"

usage() {
  cat << 'EOF'
Usage: codex-ntfy.sh <state> <message> [--title TITLE] [--dry-run]

States:
  start
  success
  fail
  error
  warning
  info
  debug
  action-required
EOF
}

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 2
fi

state="$1"
shift
message="$1"
shift

title="Codex ${state}"
extra_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --title)
    title="${2:?missing value for --title}"
    shift 2
    ;;
  --dry-run)
    extra_args+=("--dry-run")
    shift
    ;;
  *)
    printf 'Unknown option: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

url="${CODEX_NTFY_URL:-${NTFY_URL:-}}"
topic="${CODEX_NTFY_TOPIC:-${NTFY_TOPIC:-}}"

topic_override_var="CODEX_NTFY_TOPIC_$(printf '%s' "${state}" | tr '[:lower:]-' '[:upper:]_')"
if [[ -n "${!topic_override_var:-}" ]]; then
  topic="${!topic_override_var}"
fi

exec python3 "${NOTIFY_BIN}" \
  --allow-missing-config \
  --app-name "codex" \
  --url "${url:-https://ntfy.sh}" \
  --topic "${topic}" \
  --state "${state}" \
  --title "${title}" \
  --message "${message}" \
  --tag "codex" \
  "${extra_args[@]}"
