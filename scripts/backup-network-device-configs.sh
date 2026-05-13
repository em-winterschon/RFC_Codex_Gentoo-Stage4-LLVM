#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
INVENTORY="${NETWORK_CONFIG_BACKUP_INVENTORY:-${ANSIBLE_DIR}/inventories/local-network/hosts.yml}"
VAULT_WRAPPER="${NETWORK_CONFIG_BACKUP_VAULT_WRAPPER:-${REPO_ROOT}/scripts/with-ansible-vault-env.sh}"
STAGE_SCRIPT="${REPO_ROOT}/scripts/stage-encrypted-network-config-backups.py"
OUTPUT_ROOT="${NETWORK_CONFIG_BACKUP_OUTPUT_ROOT:-${REPO_ROOT}/encrypted-backups/network-devices}"
ROUTEROS_ROOT="${NETWORK_CONFIG_BACKUP_ROUTEROS_ROOT:-/root/operator-private/routeros/state-snapshots}"
SWOS_ROOT="${NETWORK_CONFIG_BACKUP_SWOS_ROOT:-/root/operator-private/swos}"
ROUTEROS_MANUAL_ROOT="${NETWORK_CONFIG_BACKUP_ROUTEROS_MANUAL_ROOT:-/root/operator-private/routeros}"

COLLECT=1
DRY_RUN=0
INCLUDE_ALL=0
GIT_ADD=0
GIT_COMMIT=0
GIT_PUSH=0
COMMIT_MESSAGE="${NETWORK_CONFIG_BACKUP_COMMIT_MESSAGE:-chore: sync encrypted network device config backups}"

usage() {
  cat << EOF
Usage: $(basename "$0") [options]

Collect RouterOS/SwOS config backups into operator-private storage, encrypt the
backup artifacts with ansible-vault, and optionally stage/commit/push the
encrypted files into git.

Options:
  --skip-collect     Do not run RouterOS/SwOS collection playbooks.
  --include-all      Encrypt all timestamped snapshots, not only latest per host.
  --git-add          Run git add for encrypted backup artifacts.
  --git-commit       Commit staged encrypted backup artifacts.
  --git-push         Push the current branch after committing.
  --sync-git         Equivalent to --git-add --git-commit --git-push.
  --message TEXT     Commit message for --git-commit.
  --dry-run          Print actions and selected artifacts without collecting,
                     encrypting, committing, or pushing.
  -h, --help         Show this help.

Environment overrides:
  NETWORK_CONFIG_BACKUP_INVENTORY
  NETWORK_CONFIG_BACKUP_OUTPUT_ROOT
  NETWORK_CONFIG_BACKUP_ROUTEROS_ROOT
  NETWORK_CONFIG_BACKUP_ROUTEROS_MANUAL_ROOT
  NETWORK_CONFIG_BACKUP_SWOS_ROOT
  NETWORK_CONFIG_BACKUP_VAULT_WRAPPER
  NETWORK_CONFIG_BACKUP_COMMIT_MESSAGE
EOF
}

log() {
  printf '[network-config-backup] %s\n' "$*"
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '[network-config-backup] DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --skip-collect)
    COLLECT=0
    ;;
  --include-all)
    INCLUDE_ALL=1
    ;;
  --git-add)
    GIT_ADD=1
    ;;
  --git-commit)
    GIT_COMMIT=1
    ;;
  --git-push)
    GIT_PUSH=1
    ;;
  --sync-git)
    GIT_ADD=1
    GIT_COMMIT=1
    GIT_PUSH=1
    ;;
  --message)
    shift
    [[ "$#" -gt 0 ]] || {
      printf 'ERROR: --message requires text\n' >&2
      exit 2
    }
    COMMIT_MESSAGE="$1"
    ;;
  --dry-run)
    DRY_RUN=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'ERROR: unknown option: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

if [[ "${DRY_RUN}" -eq 1 ]]; then
  COLLECT=0
fi

if [[ "${COLLECT}" -eq 1 ]]; then
  log "collecting RouterOS snapshots with sensitive export enabled"
  (
    cd "${ANSIBLE_DIR}"
    export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-${ANSIBLE_DIR}/ansible.cfg}"
    export ANSIBLE_STDOUT_CALLBACK="${ANSIBLE_STDOUT_CALLBACK:-default}"
    run "${VAULT_WRAPPER}" ansible-playbook \
      -i "${INVENTORY}" \
      playbooks/routeros-state-snapshot.yml \
      -e routeros_snapshot_include_sensitive_export=true
  )

  log "collecting SwOS snapshots including backup.swb"
  (
    cd "${ANSIBLE_DIR}"
    export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-${ANSIBLE_DIR}/ansible.cfg}"
    export ANSIBLE_STDOUT_CALLBACK="${ANSIBLE_STDOUT_CALLBACK:-default}"
    run "${VAULT_WRAPPER}" ansible-playbook \
      -i "${INVENTORY}" \
      playbooks/swos-state-snapshot.yml
  )
else
  log "skipping live collection"
fi

stage_args=(
  "${STAGE_SCRIPT}"
  --routeros-root "${ROUTEROS_ROOT}"
  --routeros-manual-root "${ROUTEROS_MANUAL_ROOT}"
  --swos-root "${SWOS_ROOT}"
  --output-root "${OUTPUT_ROOT}"
  --vault-wrapper "${VAULT_WRAPPER}"
  --fail-when-empty
)

if [[ "${INCLUDE_ALL}" -eq 1 ]]; then
  stage_args+=(--include-all)
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  stage_args+=(--dry-run)
fi

log "staging encrypted backups under ${OUTPUT_ROOT}"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  python3 "${stage_args[@]}"
else
  run python3 "${stage_args[@]}"
fi

if [[ "${GIT_ADD}" -eq 1 ]]; then
  log "staging encrypted backup artifacts in git"
  run git -C "${REPO_ROOT}" add "${OUTPUT_ROOT#${REPO_ROOT}/}"
fi

if [[ "${GIT_COMMIT}" -eq 1 ]]; then
  log "committing encrypted backup artifact updates"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    run git -C "${REPO_ROOT}" commit -m "${COMMIT_MESSAGE}"
  elif git -C "${REPO_ROOT}" diff --cached --quiet; then
    log "no staged encrypted backup changes to commit"
  else
    git -C "${REPO_ROOT}" commit -m "${COMMIT_MESSAGE}"
  fi
fi

if [[ "${GIT_PUSH}" -eq 1 ]]; then
  log "pushing current branch"
  run git -C "${REPO_ROOT}" push
fi
