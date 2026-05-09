#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVICE_NAME="${SERVICE_NAME:-codex-ntfy-reply-listener}"
LIBEXEC_DIR="${LIBEXEC_DIR:-/usr/local/libexec}"
INITD_DIR="${INITD_DIR:-/etc/init.d}"
CONFD_DIR="${CONFD_DIR:-/etc/conf.d}"
LOG_DIR="${LOG_DIR:-/var/log}"
INSTALL_REPO_ROOT="${INSTALL_REPO_ROOT:-${REPO_ROOT}}"
INSTALL_ENV_FILE="${INSTALL_ENV_FILE:-/root/.codex/ntfy-pub-subs.export.sh}"
INSTALL_STATE_FILE="${INSTALL_STATE_FILE:-/root/.codex/ntfy-reply-listener-state.json}"
INSTALL_QUEUE_DIR="${INSTALL_QUEUE_DIR:-/root/.codex/ntfy-replies}"
ENABLE_SERVICE="${ENABLE_SERVICE:-1}"
START_SERVICE="${START_SERVICE:-1}"
DRY_RUN=0

usage() {
  cat << EOF
Usage: $(basename "$0") [--dry-run] [--no-enable] [--no-start]

Installs the Codex ntfy reply listener as an OpenRC service.

Environment overrides:
  SERVICE_NAME
  LIBEXEC_DIR
  INITD_DIR
  CONFD_DIR
  LOG_DIR
  INSTALL_REPO_ROOT
  INSTALL_ENV_FILE
  INSTALL_STATE_FILE
  INSTALL_QUEUE_DIR
  ENABLE_SERVICE=0|1
  START_SERVICE=0|1
EOF
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '+ %q' "$1"
    shift
    for arg in "$@"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

write_file() {
  local path="$1"
  local mode="$2"
  shift 2
  local content="$1"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf -- '--- %s (%s) ---\n%s\n' "${path}" "${mode}" "${content}"
    return 0
  fi
  install -d -m 0755 "$(dirname "${path}")"
  printf '%s' "${content}" > "${path}"
  chmod "${mode}" "${path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    ;;
  --no-enable)
    ENABLE_SERVICE=0
    ;;
  --no-start)
    START_SERVICE=0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'ERROR: unknown argument: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

if [[ ! -f "${REPO_ROOT}/scripts/codex_ntfy_reply_listener_with_env.sh" ]]; then
  printf 'ERROR: expected repo files are missing under %s\n' "${REPO_ROOT}" >&2
  exit 2
fi

run install -d -m 0755 "${LIBEXEC_DIR}" "${INITD_DIR}" "${CONFD_DIR}" "${LOG_DIR}"

wrapper_path="${LIBEXEC_DIR}/${SERVICE_NAME}"
initd_path="${INITD_DIR}/${SERVICE_NAME}"
confd_path="${CONFD_DIR}/${SERVICE_NAME}"

wrapper_content="$(
  cat << EOF
#!/usr/bin/env bash
set -euo pipefail

source "${CONFD_DIR}/${SERVICE_NAME}"

export CODEX_NTFY_ENV_FILE="\${codex_ntfy_reply_listener_env_file}"
export CODEX_NTFY_REPLY_QUEUE_DIR="\${codex_ntfy_reply_listener_queue_dir}"

exec /bin/bash "\${codex_ntfy_reply_listener_repo_root}/scripts/codex_ntfy_reply_listener_with_env.sh" \\
  --state-file "\${codex_ntfy_reply_listener_state_file}"
EOF
)"

confd_content="$(
  cat << EOF
# Configuration for ${SERVICE_NAME}

codex_ntfy_reply_listener_description="Codex ntfy reply listener"
codex_ntfy_reply_listener_user="root"
codex_ntfy_reply_listener_group="root"
codex_ntfy_reply_listener_repo_root="${INSTALL_REPO_ROOT}"
codex_ntfy_reply_listener_env_file="${INSTALL_ENV_FILE}"
codex_ntfy_reply_listener_state_file="${INSTALL_STATE_FILE}"
codex_ntfy_reply_listener_queue_dir="${INSTALL_QUEUE_DIR}"
codex_ntfy_reply_listener_output_log="${LOG_DIR}/${SERVICE_NAME}.log"
codex_ntfy_reply_listener_error_log="${LOG_DIR}/${SERVICE_NAME}.err.log"
codex_ntfy_reply_listener_retry="TERM/30/KILL/5"
codex_ntfy_reply_listener_respawn_delay="5"
codex_ntfy_reply_listener_respawn_max="0"
EOF
)"

initd_content="$(cat "${REPO_ROOT}/openrc/codex-ntfy-reply-listener.initd")"

write_file "${wrapper_path}" 0755 "${wrapper_content}"
write_file "${confd_path}" 0644 "${confd_content}"
write_file "${initd_path}" 0755 "${initd_content}"

if [[ "${ENABLE_SERVICE}" == "1" ]]; then
  run rc-update add "${SERVICE_NAME}" default
fi

if [[ "${START_SERVICE}" == "1" ]]; then
  run rc-service "${SERVICE_NAME}" restart
fi

printf 'Installed %s\n' "${SERVICE_NAME}"
printf '  wrapper: %s\n' "${wrapper_path}"
printf '  conf.d:  %s\n' "${confd_path}"
printf '  init.d:  %s\n' "${initd_path}"
