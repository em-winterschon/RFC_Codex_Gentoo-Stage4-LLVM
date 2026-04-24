#!/usr/bin/env bash
set -euo pipefail

if [[ "${VALIDATOR_TRACE:-0}" == '1' ]]; then
  set -x
fi

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_DATE="2026-0421"
VERSION_NUMBER="0.1.0"

MODE="${MODE:-build-dry-run}"
WORKING_DIR="${WORKING_DIR:-${REPO_ROOT}}"
BUILDER_SCRIPT_REL="${BUILDER_SCRIPT_REL:-gentoo-virt-qemu/build-stage3-qcow.sh}"
LAUNCHER_SCRIPT_REL="${LAUNCHER_SCRIPT_REL:-gentoo-virt-qemu/qemu-launch-stage3-vm.sh}"
INSTANCE_NAME="${INSTANCE_NAME:-gentoo-stage4-testvm}"
STAGE3_IMAGE_DIR="${STAGE3_IMAGE_DIR:-/opt/gentoo-virt-qemu/stage3}"
QCOW_IMAGE="${QCOW_IMAGE:-${STAGE3_IMAGE_DIR}/images/${INSTANCE_NAME}.qcow2}"
SSH_PUBKEY="${SSH_PUBKEY:-/root/.ssh/id_ed25519.pub}"
QEMU_SERIAL_MODE="${QEMU_SERIAL_MODE:-pty}"
WAIT_FOR_SSH="${WAIT_FOR_SSH:-0}"
LOG_DIR="${LOG_DIR:-/tmp}"
LOG_FILE="${LOG_FILE-}"
LOG_TIMESTAMP="${LOG_TIMESTAMP-}"
LOG_INITIALIZED=0

EXIT_USAGE=64
EXIT_PREREQ=65
EXIT_BUILD_DRY_RUN=20
EXIT_BUILD=30
EXIT_LAUNCH=40

BUILDER_SCRIPT=''
LAUNCHER_SCRIPT=''

# Next Tasks
# 1. Extract the logging and exit-code helpers into a shared shell library once another
#    repo validator needs the same conventions.
# 2. Add VM lifecycle cleanup so launch/full modes can boot, validate, and tear down
#    the guest automatically without leaving stale QEMU processes behind.
# 3. Add guest-side assertions over SSH or serial after launch, including OpenRC sshd
#    readiness and storage-role prerequisites for the Ansible workflow.
# 4. Emit machine-readable validation summaries (JSON or JUnit XML) for CI ingestion.

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Validate the llvm/openrc stage3 qcow builder and stage3 VM launcher.

Options:
  --mode MODE          One of: build-dry-run, build, launch, full, suite
  --working-dir PATH   Repo checkout to operate in
  --ssh-pubkey PATH    SSH public key used by build modes
  --serial-mode MODE   Launcher serial mode for launch/full (none, stdio, pty, tcp, file)
  --wait-for-ssh N     WAIT_FOR_SSH value forwarded to the launcher
  --log-dir PATH       Directory for validator logs
  --log-file PATH      Explicit validator log path
  --trace              Enable shell tracing for this validator
  --help               Show this help

Modes:
  build-dry-run        Dry-run the stage3 qcow builder only
  build                Run the real stage3 qcow builder
  launch               Launch the stage3 VM from the existing qcow image
  full                 Run dry-run builder, real builder, then launch
  suite                Alias for build-dry-run
EOF
}

log() {
  printf '[validate-llvm-qcow-builder] %s\n' "$*"
}

fail() {
  local exit_code="$1"
  shift
  printf '[validate-llvm-qcow-builder] ERROR(%s): %s\n' "${exit_code}" "$*" >&2
  exit "${exit_code}"
}

log_timestamp() {
  if [[ -n "${LOG_TIMESTAMP}" ]]; then
    printf '%s' "${LOG_TIMESTAMP}"
    return 0
  fi

  TZ=UTC date +"%Y-%m%d-%H%M_%s.UTC%z"
}

default_log_file() {
  printf '%s/%s.%s-%s.%s.log' \
    "${LOG_DIR}" \
    "${SCRIPT_NAME}" \
    "${PPID}" \
    "$$" \
    "$(log_timestamp)"
}

setup_logging() {
  if [[ "${LOG_INITIALIZED}" == '1' ]]; then
    return 0
  fi

  if [[ -z "${LOG_FILE}" ]]; then
    LOG_FILE="$(default_log_file)"
  fi

  mkdir -p "$(dirname "${LOG_FILE}")"
  exec > >(tee -a "${LOG_FILE}") 2>&1
  LOG_INITIALIZED=1
  log "Log file: ${LOG_FILE}"
}

supported_modes() {
  printf '%s\n' 'build-dry-run build launch full suite'
}

validate_mode() {
  case "${MODE}" in
    suite)
      MODE='build-dry-run'
      ;;
    build-dry-run|build|launch|full)
      ;;
    *)
      fail "${EXIT_USAGE}" "Unsupported mode: ${MODE} (supported: $(supported_modes))"
      ;;
  esac
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
    --mode)
      [[ $# -ge 2 ]] || fail "${EXIT_USAGE}" '--mode requires a value'
      MODE="$2"
      shift 2
      ;;
    --working-dir)
      [[ $# -ge 2 ]] || fail "${EXIT_USAGE}" '--working-dir requires a value'
      WORKING_DIR="$2"
      shift 2
      ;;
    --ssh-pubkey)
      [[ $# -ge 2 ]] || fail "${EXIT_USAGE}" '--ssh-pubkey requires a value'
      SSH_PUBKEY="$2"
      shift 2
      ;;
    --serial-mode)
      [[ $# -ge 2 ]] || fail "${EXIT_USAGE}" '--serial-mode requires a value'
      QEMU_SERIAL_MODE="$2"
      shift 2
      ;;
    --wait-for-ssh)
      [[ $# -ge 2 ]] || fail "${EXIT_USAGE}" '--wait-for-ssh requires a value'
      WAIT_FOR_SSH="$2"
      shift 2
      ;;
    --log-dir)
      [[ $# -ge 2 ]] || fail "${EXIT_USAGE}" '--log-dir requires a value'
      LOG_DIR="$2"
      shift 2
      ;;
    --log-file)
      [[ $# -ge 2 ]] || fail "${EXIT_USAGE}" '--log-file requires a value'
      LOG_FILE="$2"
      shift 2
      ;;
    --trace)
      VALIDATOR_TRACE=1
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      fail "${EXIT_USAGE}" "Unknown argument: $1"
      ;;
    esac
  done
}

resolve_scripts() {
  BUILDER_SCRIPT="${WORKING_DIR}/${BUILDER_SCRIPT_REL}"
  LAUNCHER_SCRIPT="${WORKING_DIR}/${LAUNCHER_SCRIPT_REL}"
}

require_real_mode_root() {
  if [[ "${VALIDATOR_SKIP_ROOT_CHECK:-0}" == '1' ]]; then
    return 0
  fi

  case "${MODE}" in
    build|launch|full)
      [[ "${EUID}" -eq 0 ]] || fail "${EXIT_PREREQ}" "Mode ${MODE} requires root"
      ;;
  esac
}

validate_inputs() {
  [[ -d "${WORKING_DIR}" ]] || fail "${EXIT_PREREQ}" "Working directory does not exist: ${WORKING_DIR}"
  [[ -f "${BUILDER_SCRIPT}" && -r "${BUILDER_SCRIPT}" ]] || fail "${EXIT_PREREQ}" "Builder script is missing or not readable: ${BUILDER_SCRIPT}"
  [[ -f "${LAUNCHER_SCRIPT}" && -r "${LAUNCHER_SCRIPT}" ]] || fail "${EXIT_PREREQ}" "Launcher script is missing or not readable: ${LAUNCHER_SCRIPT}"

  case "${MODE}" in
    build-dry-run|build|full)
      [[ -f "${SSH_PUBKEY}" ]] || fail "${EXIT_PREREQ}" "SSH public key does not exist: ${SSH_PUBKEY}"
      ;;
  esac
}

current_qemu_processes() {
  if [[ -n "${QEMU_PROCESS_LIST-}" ]]; then
    printf '%s\n' "${QEMU_PROCESS_LIST}"
    return 0
  fi

  pgrep -af qemu-system-x86_64 2>/dev/null || true
}

running_qemu_for_qcow() {
  local process_list
  process_list="$(current_qemu_processes)"
  [[ "${process_list}" == *"file=${QCOW_IMAGE},"* ]]
}

validate_runtime_state() {
  case "${MODE}" in
  build | full)
    if running_qemu_for_qcow; then
      fail "${EXIT_PREREQ}" "QCOW image is in use by a running QEMU process: ${QCOW_IMAGE}"
    fi
    ;;
  esac

  case "${MODE}" in
  launch)
    if running_qemu_for_qcow; then
      fail "${EXIT_PREREQ}" "Stage3 VM is already running from QCOW image: ${QCOW_IMAGE}"
    fi
    ;;
  esac
}

print_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

run_step() {
  local label="$1"
  local exit_code="$2"
  shift 2

  log "${label}"
  print_cmd "$@"
  (
    cd "${WORKING_DIR}"
    "$@"
  ) || fail "${exit_code}" "${label} failed"
}

run_build_dry_run() {
  run_step \
    'Stage3 builder dry-run' \
    "${EXIT_BUILD_DRY_RUN}" \
    env \
    "QEMU_STAGE3_BUILD_DRY_RUN=1" \
    "SSH_AUTHORIZED_KEY_FILE=${SSH_PUBKEY}" \
    bash \
    "${BUILDER_SCRIPT}"
}

run_build() {
  run_step \
    'Stage3 builder real run' \
    "${EXIT_BUILD}" \
    env \
    "SSH_AUTHORIZED_KEY_FILE=${SSH_PUBKEY}" \
    bash \
    "${BUILDER_SCRIPT}"
}

run_launch() {
  run_step \
    'Stage3 VM launch' \
    "${EXIT_LAUNCH}" \
    env \
    "QEMU_SERIAL_MODE=${QEMU_SERIAL_MODE}" \
    "WAIT_FOR_SSH=${WAIT_FOR_SSH}" \
    bash \
    "${LAUNCHER_SCRIPT}"
}

run_mode() {
  case "${MODE}" in
  build-dry-run)
    run_build_dry_run
    ;;
  build)
    run_build
    ;;
  launch)
    run_launch
    ;;
  full)
    run_build_dry_run
    run_build
    run_launch
    ;;
  esac
}

main() {
  parse_args "$@"
  if [[ "${VALIDATOR_TRACE:-0}" == '1' ]]; then
    set -x
  fi
  setup_logging
  validate_mode
  resolve_scripts
  require_real_mode_root
  validate_inputs
  validate_runtime_state

  log "Version: ${VERSION_DATE}.${VERSION_NUMBER}"
  log "Mode: ${MODE}"
  log "Working directory: ${WORKING_DIR}"
  log "Builder: ${BUILDER_SCRIPT}"
  log "Launcher: ${LAUNCHER_SCRIPT}"
  log "QCOW image: ${QCOW_IMAGE}"

  run_mode

  log 'Validation completed successfully'
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
