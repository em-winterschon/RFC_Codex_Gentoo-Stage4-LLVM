#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SUN99_POWER_SKIP_LIVE="${SUN99_POWER_SKIP_LIVE:-0}"
SUN99_POWER_NOTIFY="${SUN99_POWER_NOTIFY:-0}"
SUN99_POWER_NTFY_URL="${SUN99_POWER_NTFY_URL:-http://msg-sun99-ntfysys.rfc1918.host}"
SUN99_POWER_NTFY_TOPIC="${SUN99_POWER_NTFY_TOPIC:-forge-change}"
SUN99_POWER_CONNECT_TIMEOUT="${SUN99_POWER_CONNECT_TIMEOUT:-6}"
SUN99_POWER_EXPECT_CYBERPOWER_USB="${SUN99_POWER_EXPECT_CYBERPOWER_USB:-0}"

M70_SSH_TARGET="${M70_SSH_TARGET:-forge}"
HASSLEHOFF_SSH_TARGET="${HASSLEHOFF_SSH_TARGET:-root@hasslehoff}"
K10_SSH_TARGET="${K10_SSH_TARGET:-root@172.16.99.156}"

AP7901_HOST="${AP7901_HOST:-172.16.99.241}"
APC_NETWORK_CANDIDATES="${APC_NETWORK_CANDIDATES:-172.16.99.242 172.16.99.244}"
SUN99_POWER_EDGE_SWITCH="${SUN99_POWER_EDGE_SWITCH:-172.16.99.250}"
SUN99_POWER_AP7901_SNMP_ARGS="${SUN99_POWER_AP7901_SNMP_ARGS:-}"

failures=0
warnings=0

usage() {
  cat << 'USAGE'
Usage: validate-sun99-power-recovery.sh

Read-only post-incident gate for the SUN99 power recovery path.

Environment:
  SUN99_POWER_SKIP_LIVE=1          Only validate repo artifacts; skip SSH/curl/ping/SNMP.
  SUN99_POWER_NOTIFY=1             Publish final summary to local ntfy.
  SUN99_POWER_NTFY_URL=URL         Default: http://msg-sun99-ntfysys.rfc1918.host
  SUN99_POWER_NTFY_TOPIC=TOPIC     Default: forge-change
  M70_SSH_TARGET=HOST              Default: forge
  HASSLEHOFF_SSH_TARGET=HOST       Default: root@hasslehoff
  K10_SSH_TARGET=HOST              Default: root@172.16.99.156
  SUN99_POWER_AP7901_SNMP_ARGS=... Optional snmpget options for AP7901 verification.

This script must not mutate hosts, power outlets, services, routes, or secrets.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '[sun99-power] %s\n' "$*"
}

ok() {
  printf '[sun99-power] OK: %s\n' "$*"
}

warn() {
  warnings=$((warnings + 1))
  printf '[sun99-power] WARN: %s\n' "$*" >&2
}

fail() {
  failures=$((failures + 1))
  printf '[sun99-power] FAIL: %s\n' "$*" >&2
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
  if "$@" > /tmp/sun99-power-check.out 2> /tmp/sun99-power-check.err; then
    ok "${description}"
  else
    fail "${description}"
    sed 's/^/[sun99-power] stderr: /' /tmp/sun99-power-check.err >&2 || true
    sed 's/^/[sun99-power] stdout: /' /tmp/sun99-power-check.out >&2 || true
  fi
}

run_warn_check() {
  local description="$1"
  shift
  if "$@" > /tmp/sun99-power-check.out 2> /tmp/sun99-power-check.err; then
    ok "${description}"
  else
    warn "${description}"
    sed 's/^/[sun99-power] stderr: /' /tmp/sun99-power-check.err >&2 || true
    sed 's/^/[sun99-power] stdout: /' /tmp/sun99-power-check.out >&2 || true
  fi
}

ssh_readonly() {
  local target="$1"
  shift
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout="${SUN99_POWER_CONNECT_TIMEOUT}" \
    -o StrictHostKeyChecking=accept-new \
    "${target}" "$@"
}

check_repo_artifacts() {
  log "checking repo power-recovery artifacts"

  require_file "${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
  require_file "${REPO_ROOT}/docs/wiki/Sun99-Power-Recovery.md"
  require_file "${REPO_ROOT}/docs/SUNRISE-CRITICAL-PATH.md"
  require_file "${REPO_ROOT}/docs/M70-FORGE-AUTOMATION-ADMIN.md"
  require_file "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"

  require_grep 'Post-Incident Recovery Gate' "${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
  require_grep 'CyberPower CP1500PFCRM2U' "${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
  require_grep 'APC SRT1500RMXLA' "${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
  require_grep 'ATS' "${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
  require_grep 'Blackbox' "${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
  require_grep 'NUT' "${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
  require_grep 'apcupsd' "${REPO_ROOT}/docs/SUN99-POWER-RECOVERY.md"
  require_grep 'ST-017' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
  require_grep 'OBS-004' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
  require_grep 'AAA-005' "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"
}

check_hasslehoff_recovery() {
  log "checking Hasslehoff post-outage service state"

  run_check "Hasslehoff SSH responds" \
    ssh_readonly "${HASSLEHOFF_SSH_TARGET}" 'hostname >/dev/null'

  run_check "Hasslehoff service VMs have onboot/startup policy" \
    ssh_readonly "${HASSLEHOFF_SSH_TARGET}" '
      set -eu
      for spec in \
        "1063:order=10" "1088:order=20" "1089:order=25" "1062:order=30" \
        "1064:order=40" "1065:order=41" "1091:order=45" "1066:order=50" \
        "1067:order=60"
      do
        vmid=${spec%%:*}
        order=${spec#*:}
        qm config "${vmid}" | grep -q "^onboot: 1"
        qm config "${vmid}" | grep -q "^startup: ${order}"
      done
      memory=$(qm config 1089 | awk "/^memory:/ { print \$2 }")
      test "${memory}" -le 8192
    '

  run_check "Hasslehoff ZFS pools report healthy" \
    ssh_readonly "${HASSLEHOFF_SSH_TARGET}" 'zpool status -x | grep -Eq "all pools are healthy|no pools available"'
}

check_m70_recovery() {
  log "checking M70 automation-admin recovery"

  run_check "M70 SSH responds" \
    ssh_readonly "${M70_SSH_TARGET}" 'hostname >/dev/null'

  run_check "M70 chronyd is started" \
    ssh_readonly "${M70_SSH_TARGET}" 'rc-service chronyd status | grep -q "status: started"'

  run_check "M70 chronyd reports normal leap status" \
    ssh_readonly "${M70_SSH_TARGET}" 'chronyc tracking | grep -q "Leap status.*Normal"'

  run_check "M70 OpenVPN FMT2 transport is started" \
    ssh_readonly "${M70_SSH_TARGET}" 'rc-service openvpn.fmt2 status | grep -q "status: started"'

  run_check "M70 FMT2 management subnet routes over tun-fmt2" \
    ssh_readonly "${M70_SSH_TARGET}" 'ip route get 172.18.20.4 | grep -q "dev tun-fmt2"'

  run_check "M70 ZFS pools report healthy" \
    ssh_readonly "${M70_SSH_TARGET}" 'zpool status -x | grep -Eq "all pools are healthy|no pools available"'

  if [[ "${SUN99_POWER_EXPECT_CYBERPOWER_USB}" == "1" ]]; then
    run_check "CyberPower CP1500PFCRM2U USB is visible on M70" \
      ssh_readonly "${M70_SSH_TARGET}" 'lsusb | grep -Ei "Cyber.?Power|0764:"'
  else
    run_warn_check "CyberPower CP1500PFCRM2U USB is not required yet" \
      ssh_readonly "${M70_SSH_TARGET}" 'lsusb | grep -Ei "Cyber.?Power|0764:"'
  fi
}

check_k10_recovery() {
  log "checking K10 post-outage reachability"

  run_check "K10 SSH responds" \
    ssh_readonly "${K10_SSH_TARGET}" 'hostname >/dev/null'

  run_check "K10 clock is in the current year" \
    ssh_readonly "${K10_SSH_TARGET}" 'test "$(date +%Y)" -ge 2026'

  run_warn_check "K10 SSSD is started or known firstboot enrollment blocker remains" \
    ssh_readonly "${K10_SSH_TARGET}" 'rc-service sssd status | grep -q "status: started"'
}

check_local_awareness() {
  log "checking local notification awareness path"

  run_check "local ntfy HTTP health responds" \
    curl -fsS "${SUN99_POWER_NTFY_URL%/}/v1/health"

  if [[ "${SUN99_POWER_NTFY_URL}" == http://* ]]; then
    local https_url="https://${SUN99_POWER_NTFY_URL#http://}"
    run_check "local ntfy HTTPS health responds" \
      curl -kfsS "${https_url%/}/v1/health"
  fi
}

check_power_endpoints() {
  log "checking SUN99 power and OOB endpoint visibility"

  run_check "AP7901 PDU ${AP7901_HOST} responds to ping" \
    ping -c 2 -W 2 "${AP7901_HOST}"

  if [[ -n "${SUN99_POWER_AP7901_SNMP_ARGS}" ]] && command -v snmpget > /dev/null 2>&1; then
    run_check "AP7901 pdu-rfc99-corectrl-p08-099241 SNMP sysName validates" \
      snmpget ${SUN99_POWER_AP7901_SNMP_ARGS} "${AP7901_HOST}" SNMPv2-MIB::sysName.0
  else
    warn "AP7901 SNMP validation skipped; set SUN99_POWER_AP7901_SNMP_ARGS from vaulted credentials"
  fi

  for host in ${APC_NETWORK_CANDIDATES}; do
    run_check "APC UPS/ATS/PDU candidate ${host} responds to ping" \
      ping -c 2 -W 2 "${host}"
    run_warn_check "APC UPS/ATS/PDU candidate ${host} HTTPS management responds" \
      curl -kfsSI --connect-timeout "${SUN99_POWER_CONNECT_TIMEOUT}" "https://${host}/"
  done

  run_warn_check "SUN99 edge switch ${SUN99_POWER_EDGE_SWITCH} responds to management HTTPS" \
    curl -kfsSI --connect-timeout "${SUN99_POWER_CONNECT_TIMEOUT}" "https://${SUN99_POWER_EDGE_SWITCH}/"
}

send_ntfy_summary() {
  local status="$1"
  local message="$2"

  [[ "${SUN99_POWER_NOTIFY}" == "1" ]] || return 0

  curl -fsS \
    -H "Title: SUN99 power recovery ${status}" \
    -H "Tags: power,sun99,recovery" \
    --data-binary "${message}" \
    "${SUN99_POWER_NTFY_URL%/}/${SUN99_POWER_NTFY_TOPIC}" > /dev/null ||
    warn "failed to publish ntfy summary"
}

main() {
  check_repo_artifacts

  if [[ "${SUN99_POWER_SKIP_LIVE}" == "1" ]]; then
    warn "SUN99_POWER_SKIP_LIVE=1; skipped SSH, curl, ping, and SNMP checks"
  else
    check_hasslehoff_recovery
    check_m70_recovery
    check_k10_recovery
    check_local_awareness
    check_power_endpoints
  fi

  log "summary: failures=${failures} warnings=${warnings}"

  if ((failures > 0)); then
    send_ntfy_summary "failed" "SUN99 power recovery gate failed: failures=${failures}, warnings=${warnings}."
    exit 1
  fi

  send_ntfy_summary "passed" "SUN99 power recovery gate passed: failures=0, warnings=${warnings}."
  exit 0
}

main "$@"
