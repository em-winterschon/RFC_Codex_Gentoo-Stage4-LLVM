#!/usr/bin/env bash
set -euo pipefail

HOST="${WATCH_VM_SERIAL_HOST:-127.0.0.1}"
PORT="${WATCH_VM_SERIAL_PORT:-}"
MODE="${WATCH_VM_SERIAL_MODE:-telnet}"
PRINT_ONLY=0
VM_NAME=''

usage() {
  cat << 'EOF'
Usage: watch-vm-serial.sh [--vm NAME] [--host HOST] [--port PORT] [--mode telnet|socat|nc] [--print]

Convenience wrapper for watching a QEMU TCP serial console without having to
remember raw `telnet` / `socat` / `nc` commands.

Options:
  --vm NAME     Known VM mapping:
                routeros | simple-guest | container-services | binpkg-repository | elasticsearch-test
  --host HOST   TCP host to connect to. Default: 127.0.0.1
  --port PORT   TCP port to connect to. Overrides --vm mapping.
  --mode MODE   telnet (default), socat, or nc
  --print       Print the resolved command instead of executing it.
  -h, --help    Show this help text.

Known mappings:
  routeros           -> 127.0.0.1:5001
  simple-guest       -> 127.0.0.1:5002
  container-services -> 127.0.0.1:5003
  binpkg-repository  -> 127.0.0.1:5004
  elasticsearch-test -> 127.0.0.1:5005

Notes:
  - `telnet` is the safest default because it is easier to exit cleanly.
  - With `telnet`, use Ctrl-] then `quit` to disconnect.
  - `socat` is useful for raw output, but it may leave the terminal in raw mode.
    If that happens, run `stty sane`.
EOF
}

log() {
  printf '[watch-vm-serial] %s\n' "$*"
}

fail() {
  printf '[watch-vm-serial] ERROR: %s\n' "$*" >&2
  exit 1
}

print_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

resolve_vm_defaults() {
  case "${VM_NAME}" in
  '') ;;
  routeros)
    HOST='127.0.0.1'
    PORT='5001'
    ;;
  simple-guest)
    HOST='127.0.0.1'
    PORT='5002'
    ;;
  container-services)
    HOST='127.0.0.1'
    PORT='5003'
    ;;
  binpkg-repository)
    HOST='127.0.0.1'
    PORT='5004'
    ;;
  elasticsearch-test)
    HOST='127.0.0.1'
    PORT='5005'
    ;;
  *)
    fail "Unknown --vm value: ${VM_NAME} (supported: routeros, simple-guest, container-services, binpkg-repository, elasticsearch-test)"
    ;;
  esac
}

require_command() {
  [[ "${PRINT_ONLY}" == '1' ]] && return 0
  command -v "$1" > /dev/null 2>&1 || fail "Required command is missing: $1"
}

build_command() {
  case "${MODE}" in
  telnet)
    require_command telnet
    printf '%s\0%s\0%s\0' telnet "${HOST}" "${PORT}"
    ;;
  socat)
    require_command socat
    printf '%s\0%s\0' socat "-,rawer,echo=0"
    printf '%s\0' "tcp:${HOST}:${PORT}"
    ;;
  nc)
    require_command nc
    printf '%s\0%s\0%s\0' nc "${HOST}" "${PORT}"
    ;;
  *)
    fail "Unsupported --mode value: ${MODE} (supported: telnet, socat, nc)"
    ;;
  esac
}

while (($# > 0)); do
  case "$1" in
  --vm)
    VM_NAME="${2:?missing value for --vm}"
    shift 2
    ;;
  --host)
    HOST="${2:?missing value for --host}"
    shift 2
    ;;
  --port)
    PORT="${2:?missing value for --port}"
    shift 2
    ;;
  --mode)
    MODE="${2:?missing value for --mode}"
    shift 2
    ;;
  --print)
    PRINT_ONLY=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    fail "Unknown argument: $1"
    ;;
  esac
done

resolve_vm_defaults
[[ -n "${PORT}" ]] || fail 'No TCP port resolved; use --vm or --port'

mapfile -d '' -t WATCH_CMD < <(build_command)

if [[ "${PRINT_ONLY}" == '1' ]]; then
  print_cmd "${WATCH_CMD[@]}"
  exit 0
fi

log "Connecting to ${HOST}:${PORT} using ${MODE}"
exec "${WATCH_CMD[@]}"
