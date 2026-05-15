#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

M70_SSH_TARGET="${M70_SSH_TARGET:-forge}"
HASSLEHOFF_SSH_TARGET="${HASSLEHOFF_SSH_TARGET:-root@hasslehoff}"
SUNRISE_SKIP_LIVE="${SUNRISE_SKIP_LIVE:-0}"
SUNRISE_NOTIFY="${SUNRISE_NOTIFY:-0}"
SUNRISE_NTFY_URL="${SUNRISE_NTFY_URL:-http://msg-sun99-ntfysys.rfc1918.host}"
SUNRISE_NTFY_TOPIC="${SUNRISE_NTFY_TOPIC:-forge-change}"
SUNRISE_CONNECT_TIMEOUT="${SUNRISE_CONNECT_TIMEOUT:-6}"

failures=0
warnings=0

usage() {
  cat <<'USAGE'
Usage: validate-sunrise-critical-path.sh

Read-only launch gate for the current SUN99/FMT2 critical path.

Environment:
  SUNRISE_SKIP_LIVE=1       Only validate repo artifacts; skip SSH, curl, ping.
  SUNRISE_NOTIFY=1          Publish final summary to local ntfy.
  SUNRISE_NTFY_URL=URL      Default: http://msg-sun99-ntfysys.rfc1918.host
  SUNRISE_NTFY_TOPIC=TOPIC  Default: forge-change
  M70_SSH_TARGET=HOST       Default: forge
  HASSLEHOFF_SSH_TARGET=H   Default: root@hasslehoff

This script must not mutate hosts, routes, services, or secrets.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '[sunrise] %s\n' "$*"
}

ok() {
  printf '[sunrise] OK: %s\n' "$*"
}

warn() {
  warnings=$((warnings + 1))
  printf '[sunrise] WARN: %s\n' "$*" >&2
}

fail() {
  failures=$((failures + 1))
  printf '[sunrise] FAIL: %s\n' "$*" >&2
}

require_file() {
  local path="$1"
  if [[ -f "${path}" ]]; then
    ok "file exists: ${path#${REPO_ROOT}/}"
  else
    fail "missing file: ${path#${REPO_ROOT}/}"
  fi
}

require_grep() {
  local pattern="$1"
  local path="$2"
  if grep -q -- "${pattern}" "${path}"; then
    ok "pattern present: ${pattern} in ${path#${REPO_ROOT}/}"
  else
    fail "missing pattern: ${pattern} in ${path#${REPO_ROOT}/}"
  fi
}

run_check() {
  local description="$1"
  shift
  if "$@" >/tmp/sunrise-check.out 2>/tmp/sunrise-check.err; then
    ok "${description}"
  else
    fail "${description}"
    sed 's/^/[sunrise] stderr: /' /tmp/sunrise-check.err >&2 || true
    sed 's/^/[sunrise] stdout: /' /tmp/sunrise-check.out >&2 || true
  fi
}

ssh_readonly() {
  local target="$1"
  shift
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout="${SUNRISE_CONNECT_TIMEOUT}" \
    -o StrictHostKeyChecking=accept-new \
    "${target}" "$@"
}

check_repo_artifacts() {
  log "checking repo critical-path artifacts"

  require_file "${REPO_ROOT}/docs/SUNRISE-CRITICAL-PATH.md"
  require_file "${REPO_ROOT}/docs/FMT2-OPENVPN-COMPAT-TRANSPORT.md"
  require_file "${REPO_ROOT}/docs/HASSLEHOFF-BACKUP.md"
  require_file "${REPO_ROOT}/docs/SLURM-PILOT-BRINGUP.md"
  require_file "${REPO_ROOT}/docs/X12AGAIN-BAREMETAL-REIMAGE-PREP.md"
  require_file "${REPO_ROOT}/scripts/backup-hasslehoff-config.sh"
  require_file "${REPO_ROOT}/scripts/forge_memory_spool.py"

  require_grep 'openvpn.fmt2' "${REPO_ROOT}/docs/FMT2-OPENVPN-COMPAT-TRANSPORT.md"
  require_grep '172.16.99.70' "${REPO_ROOT}/docs/FMT2-OPENVPN-COMPAT-TRANSPORT.md"
  require_grep 'PNR-034' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
  require_grep 'HPC-002' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
  require_grep 'ADM-003' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
  require_grep 'BUILD-VM-002' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
}

check_live_m70_and_fmt2() {
  log "checking M70 and temporary FMT2 transport"

  run_check "M70 SSH responds" \
    ssh_readonly "${M70_SSH_TARGET}" 'hostname >/dev/null'

  run_check "M70 OpenVPN service is started" \
    ssh_readonly "${M70_SSH_TARGET}" 'rc-service openvpn.fmt2 status | grep -q "status: started"'

  run_check "M70 routes FMT2 management subnet over tun-fmt2" \
    ssh_readonly "${M70_SSH_TARGET}" 'ip route get 172.18.20.4 | grep -q "dev tun-fmt2"'

  run_check "M70 routes FMT2 CARP subnet over tun-fmt2" \
    ssh_readonly "${M70_SSH_TARGET}" 'ip route get 10.200.99.1 | grep -q "dev tun-fmt2"'

  run_check "local client reaches FMT2 OPNsense CARP VIP" \
    ping -c 2 -W 2 10.200.99.1

  run_check "local client reaches FMT2 management target 172.18.20.4" \
    ping -c 2 -W 2 172.18.20.4
}

check_live_hasslehoff() {
  log "checking Hasslehoff backup and Proxmox reachability"

  run_check "Hasslehoff SSH responds" \
    ssh_readonly "${HASSLEHOFF_SSH_TARGET}" 'hostname >/dev/null'

  run_check "Hasslehoff Proxmox CLI responds" \
    ssh_readonly "${HASSLEHOFF_SSH_TARGET}" 'pveversion >/dev/null && qm list >/dev/null'

  run_check "Hasslehoff config backup dry-run renders destinations" \
    env HASSLEHOFF_BACKUP_DRY_RUN=1 HASSLEHOFF_SSH_TARGET="${HASSLEHOFF_SSH_TARGET}" \
      bash "${REPO_ROOT}/scripts/backup-hasslehoff-config.sh"
}

check_live_ntfy() {
  log "checking local ntfy awareness path"

  run_check "local ntfy HTTP health responds" \
    curl -fsS "${SUNRISE_NTFY_URL%/}/v1/health"

  if [[ "${SUNRISE_NTFY_URL}" == http://* ]]; then
    local https_url="https://${SUNRISE_NTFY_URL#http://}"
    run_check "local ntfy HTTPS health responds" \
      curl -kfsS "${https_url%/}/v1/health"
  fi
}

send_ntfy_summary() {
  local status="$1"
  local message="$2"

  [[ "${SUNRISE_NOTIFY}" == "1" ]] || return 0

  curl -fsS \
    -H "Title: Sunrise critical path ${status}" \
    -H "Tags: sunrise,critical-path" \
    --data-binary "${message}" \
    "${SUNRISE_NTFY_URL%/}/${SUNRISE_NTFY_TOPIC}" >/dev/null || \
    warn "failed to publish ntfy summary"
}

main() {
  check_repo_artifacts

  if [[ "${SUNRISE_SKIP_LIVE}" == "1" ]]; then
    warn "SUNRISE_SKIP_LIVE=1; skipped SSH, curl, and ping checks"
  else
    check_live_m70_and_fmt2
    check_live_hasslehoff
    check_live_ntfy
  fi

  log "summary: failures=${failures} warnings=${warnings}"

  if (( failures > 0 )); then
    send_ntfy_summary "failed" "Sunrise critical path gate failed: failures=${failures}, warnings=${warnings}."
    exit 1
  fi

  send_ntfy_summary "passed" "Sunrise critical path gate passed: failures=0, warnings=${warnings}."
  exit 0
}

main "$@"
