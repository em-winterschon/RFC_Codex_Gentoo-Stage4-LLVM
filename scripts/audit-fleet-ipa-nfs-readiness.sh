#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
INVENTORY="${INVENTORY:-${ANSIBLE_ROOT}/inventories/local-network/hosts.yml}"
PLAYBOOK="${ANSIBLE_ROOT}/playbooks/fleet-ipa-nfs-readiness-audit.yml"
VAULT_WRAPPER="${REPO_ROOT}/scripts/with-ansible-vault-env.sh"
VAULT_ENV_FILE="${ANSIBLE_VAULT_ENV_FILE:-${HOME}/.ssh/vault/ANSIBLE_VARS.ENV}"
LIMIT_ARGS=()

usage() {
  cat <<'USAGE'
Usage: audit-fleet-ipa-nfs-readiness.sh [--inventory PATH] [--limit PATTERN]

Runs the read-only FreeIPA client and NFS floating-home readiness audit.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      INVENTORY="${2:?missing --inventory value}"
      shift 2
      ;;
    --limit)
      LIMIT_ARGS=(--limit "${2:?missing --limit value}")
      shift 2
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
done

printf 'FreeIPA admin connectivity probe syntax from M70:\n'
printf '  ssh -o BatchMode=yes -o ConnectTimeout=8 -l verwalterin ipa01.rfc1918.host <cmd>\n'
printf '  ssh -o BatchMode=yes -o ConnectTimeout=8 -l root ipa01.rfc1918.host <cmd>\n'

if [[ -x "${VAULT_WRAPPER}" && -r "${VAULT_ENV_FILE}" ]]; then
  exec "${VAULT_WRAPPER}" ansible-playbook -i "${INVENTORY}" "${PLAYBOOK}" "${LIMIT_ARGS[@]}"
fi

exec ansible-playbook -i "${INVENTORY}" "${PLAYBOOK}" "${LIMIT_ARGS[@]}"
