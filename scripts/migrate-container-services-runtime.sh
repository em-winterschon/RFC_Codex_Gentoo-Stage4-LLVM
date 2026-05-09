#!/usr/bin/env bash
set -euo pipefail

SOURCE_HOST="${SOURCE_HOST:-root@10.9.8.89}"
TARGET_HOST="${TARGET_HOST:-root@172.16.99.89}"
STAGING_MODE="${STAGING_MODE:-1}"
START_SERVICES="${START_SERVICES:-0}"
DRY_RUN=1

usage() {
  cat << 'EOF'
Usage: migrate-container-services-runtime.sh [--dry-run|--apply] [--start-services]

Copies the validated container-services runtime layer from the current source
VM to a staging VM. Default mode is dry-run.

Environment:
  SOURCE_HOST    SSH target for the source container-services VM.
  TARGET_HOST    SSH target for the staging VM.
  STAGING_MODE   When 1, patch HAProxy to avoid claiming production 10.9.8.92.

Safety:
  This copies runtime config and OpenRC wrappers only. It does not move the
  production service IP and does not stop the source VM.

Prerequisites:
  The target must already have Podman installed. If images are private, log in
  to the registry on the target before using --start-services.
EOF
}

log() {
  printf '[migrate-container-services-runtime] %s\n' "$*"
}

fail() {
  printf '[migrate-container-services-runtime] ERROR: %s\n' "$*" >&2
  exit 2
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --apply)
      DRY_RUN=0
      ;;
    --start-services)
      START_SERVICES=1
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
    esac
    shift
  done
}

remote_paths=(
  /etc/container-services
  /etc/containers/registries.conf.d/10-container-services.conf
  /etc/conf.d/container-haproxy
  /etc/conf.d/container-nginx
  /etc/conf.d/container-ntfy
  /etc/conf.d/container-rsyslog-collector
  /etc/init.d/container-haproxy
  /etc/init.d/container-nginx
  /etc/init.d/container-ntfy
  /etc/init.d/container-rsyslog-collector
  /etc/sysctl.d/90-container-services.conf
  /usr/local/libexec/container-haproxy
  /usr/local/libexec/container-nginx
  /usr/local/libexec/container-ntfy
  /usr/local/libexec/container-rsyslog-collector
  /usr/local/libexec/container-services
)

dry_run() {
  log "DRY RUN; no remote changes will be made."
  log "source=${SOURCE_HOST}"
  log "target=${TARGET_HOST}"
  log "paths=${remote_paths[*]}"
  log "staging_mode=${STAGING_MODE}"
  log "start_services=${START_SERVICES}"
}

copy_runtime() {
  local tar_args=()
  local path

  for path in "${remote_paths[@]}"; do
    tar_args+=("${path#/}")
  done

  ssh "${SOURCE_HOST}" "tar -C / -czf - ${tar_args[*]}" |
    ssh "${TARGET_HOST}" 'tar -C / -xzf -'
}

patch_staging_haproxy() {
  [[ "${STAGING_MODE}" == '1' ]] || return 0
  ssh "${TARGET_HOST}" 'python3 -' << 'PY'
from pathlib import Path

path = Path("/usr/local/libexec/container-services/run-haproxy.sh")
text = path.read_text(encoding="utf-8")
old_vip_claim = """vip_dev="$(ip -o route get 10.9.8.1 | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')"
test -n "${vip_dev}"
ip address replace 10.9.8.92/32 dev "${vip_dev}"
"""
text = text.replace(old_vip_claim, "")
text = text.replace("  -p 10.9.8.92:9200:9200/tcp \\\n", "  -p 9200:9200/tcp \\\n")
path.write_text(text, encoding="utf-8")
PY
}

enable_runtime() {
  ssh "${TARGET_HOST}" 'set -euo pipefail
mkdir -p /var/lib/container-services-ephemeral/data /var/lib/container-services-ephemeral/logs
chmod +x /usr/local/libexec/container-services/*.sh /etc/init.d/container-* /usr/local/libexec/container-services/ensure-networks.sh
rc-update add container-rsyslog-collector default
rc-update add container-nginx default
rc-update add container-haproxy default
'
}

start_runtime() {
  [[ "${START_SERVICES}" == '1' ]] || return 0
  ssh "${TARGET_HOST}" 'set -euo pipefail
rc-service container-rsyslog-collector restart
rc-service container-nginx restart
rc-service container-haproxy restart
'
}

main() {
  parse_args "$@"

  if [[ "${DRY_RUN}" == '1' ]]; then
    dry_run
    return 0
  fi

  ssh "${SOURCE_HOST}" 'test -d /etc/container-services && command -v podman >/dev/null'
  ssh "${TARGET_HOST}" 'command -v podman >/dev/null'
  copy_runtime
  patch_staging_haproxy
  enable_runtime
  start_runtime
}

main "$@"
