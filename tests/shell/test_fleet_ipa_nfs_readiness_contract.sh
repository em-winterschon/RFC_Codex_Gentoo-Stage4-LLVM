#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
BASE_PACKAGES="${ANSIBLE_ROOT}/profile-package-lists/stage5-base-minimal-nox.packages"
NFS_PROFILE="${ANSIBLE_ROOT}/profile-definitions/nfs-storage-client.yml"
NFS_DEFAULTS="${ANSIBLE_ROOT}/roles/nfs_storage_client/defaults/main.yml"
NFS_FSTAB="${ANSIBLE_ROOT}/roles/nfs_storage_client/templates/fstab.j2"
NFS_CONF="${ANSIBLE_ROOT}/roles/nfs_storage_client/templates/nfs.conf.j2"
AUDIT_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/fleet-ipa-nfs-readiness-audit.yml"
POLICY="${ANSIBLE_ROOT}/fleet-readiness-definitions/ipa-nfs-baseline.yml"
SCRIPT="${REPO_ROOT}/scripts/audit-fleet-ipa-nfs-readiness.sh"
DOC="${REPO_ROOT}/docs/FLEET-IPA-NFS-READINESS.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_executable() {
  [[ -x "$1" ]] || fail "not executable: $1"
}

require_grep() {
  local pattern=$1
  local file=$2
  grep -Eq -- "${pattern}" "${file}" || fail "missing pattern ${pattern} in ${file}"
}

require_fixed() {
  local pattern=$1
  local file=$2
  grep -Fq -- "${pattern}" "${file}" || fail "missing text ${pattern} in ${file}"
}

require_file "${BASE_PACKAGES}"
for atom in \
  'sys-auth/sssd' \
  'app-crypt/mit-krb5' \
  'net-nds/openldap' \
  'app-misc/ca-certificates' \
  'net-fs/nfs-utils' \
  'net-nds/rpcbind' \
  'sys-apps/keyutils'; do
  require_grep "^${atom}$" "${BASE_PACKAGES}"
done

require_file "${NFS_PROFILE}"
require_fixed 'default: nfsv4_2_tcp' "${NFS_PROFILE}"
require_fixed 'lacp_default: nfsv4_2_tcp_multipath' "${NFS_PROFILE}"
require_fixed 'non_lacp_default: nfsv4_1_tcp' "${NFS_PROFILE}"
require_fixed 'Floating home directories require FreeIPA UID/GID parity before enablement.' "${NFS_PROFILE}"
require_fixed 'nofail' "${NFS_PROFILE}"
require_fixed 'soft' "${NFS_PROFILE}"

require_file "${NFS_DEFAULTS}"
require_fixed 'nfs_storage_client_protocol_default: nfsv4_2_tcp' "${NFS_DEFAULTS}"
require_fixed 'nfs_storage_client_non_lacp_protocol_default: nfsv4_1_tcp' "${NFS_DEFAULTS}"
require_fixed 'nfs_storage_client_lacp_protocol_default: nfsv4_2_tcp_multipath' "${NFS_DEFAULTS}"
require_fixed 'nfs_storage_client_fstab_safety_options:' "${NFS_DEFAULTS}"
require_fixed '  - nofail' "${NFS_DEFAULTS}"
require_fixed '  - soft' "${NFS_DEFAULTS}"

require_file "${NFS_FSTAB}"
require_fixed 'nofail' "${NFS_FSTAB}"
require_fixed 'soft' "${NFS_FSTAB}"

require_file "${NFS_CONF}"
require_fixed "resolved_nfs_storage_client.protocol_default in ['nfsv4_2_tcp', 'nfsv4_2_tcp_multipath', 'nfsv4_tcp', 'nfs_rdma']" "${NFS_CONF}"
require_fixed "resolved_nfs_storage_client.protocol_default == 'nfsv4_1_tcp'" "${NFS_CONF}"

require_file "${POLICY}"
require_fixed 'freeipa_client_required: true' "${POLICY}"
require_fixed 'nfs_home_mount_required: true' "${POLICY}"
require_fixed 'default_nfs_protocol_lacp: nfsv4_2_tcp_multipath' "${POLICY}"
require_fixed 'default_nfs_protocol_non_lacp: nfsv4_1_tcp' "${POLICY}"
require_fixed 'fstab_required_options: [nofail, soft]' "${POLICY}"
require_fixed 'freeipa_admin_cli_required_on_admin_hosts: true' "${POLICY}"
require_fixed 'gentoo_freeipa_cli_note:' "${POLICY}"

require_file "${AUDIT_PLAYBOOK}"
require_fixed 'fleet-ipa-nfs-readiness-audit' "${AUDIT_PLAYBOOK}"
require_fixed 'sssctl' "${AUDIT_PLAYBOOK}"
require_fixed 'getent' "${AUDIT_PLAYBOOK}"
require_fixed 'findmnt' "${AUDIT_PLAYBOOK}"
require_fixed 'nfsvers' "${AUDIT_PLAYBOOK}"
require_fixed 'nofail' "${AUDIT_PLAYBOOK}"
require_fixed 'soft' "${AUDIT_PLAYBOOK}"

require_executable "${SCRIPT}"
bash -n "${SCRIPT}"
require_fixed 'ssh -o BatchMode=yes -o ConnectTimeout=8 -l verwalterin ipa01.rfc1918.host' "${SCRIPT}"
require_fixed 'with-ansible-vault-env.sh' "${SCRIPT}"
require_fixed 'ansible-playbook' "${SCRIPT}"
require_fixed 'fleet-ipa-nfs-readiness-audit.yml' "${SCRIPT}"

require_file "${DOC}"
require_fixed 'FreeIPA client readiness is mandatory fleet baseline.' "${DOC}"
require_fixed 'FreeIPA admin CLI mutation capability is mandatory on admin hosts, not necessarily every Gentoo client.' "${DOC}"
require_fixed 'NFSv4.2 with multipath is the default for LACP-capable hosts.' "${DOC}"
require_fixed 'NFSv4.1 is the default for non-LACP hosts.' "${DOC}"
require_fixed 'NASA NFS boot mounts must use `nofail,soft`.' "${DOC}"
require_fixed 'SUN99 QNAP can serve low-latency floating homes and sync with FMT2 NASA.' "${DOC}"
if grep -Fq 'Docker' "${DOC}" "${SCRIPT}" "${POLICY}"; then
  fail "Docker reference found in fleet IPA/NFS readiness artifacts"
fi

printf 'PASS: %s\n' "$(basename "$0")"
