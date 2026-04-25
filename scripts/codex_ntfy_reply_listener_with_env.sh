#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${HOME}/.codex/ntfy-pub-subs.export.sh"
FALLBACK_ENV_FILE="/opt/codex/ntfy-pub-subs.export.sh"
NTFY_ENV_FILE="${CODEX_NTFY_ENV_FILE:-}"

if [[ -z "${NTFY_ENV_FILE}" ]]; then
  if [[ -r "${DEFAULT_ENV_FILE}" ]]; then
    NTFY_ENV_FILE="${DEFAULT_ENV_FILE}"
  else
    NTFY_ENV_FILE="${FALLBACK_ENV_FILE}"
  fi
fi

if [[ -r "${NTFY_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  . "${NTFY_ENV_FILE}"
fi

exec python3 "${SCRIPT_DIR}/codex_ntfy_reply_listener.py" "$@"
