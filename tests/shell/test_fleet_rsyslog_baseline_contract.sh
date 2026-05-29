#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
BASE_PACKAGES="${ANSIBLE_ROOT}/profile-package-lists/stage5-base-minimal-nox.packages"
BASE_PROFILE="${ANSIBLE_ROOT}/profile-definitions/base-minimal-nox.yml"
BASE_METADATA="${ANSIBLE_ROOT}/profile-definitions/base-minimal-nox.metadata.yml"
SERVICE_ATOMS="${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml"
POLICY="${ANSIBLE_ROOT}/fleet-readiness-definitions/rsyslog-baseline.yml"
AUDIT_PLAYBOOK="${ANSIBLE_ROOT}/playbooks/fleet-rsyslog-readiness-audit.yml"
SCRIPT="${REPO_ROOT}/scripts/audit-fleet-rsyslog-readiness.sh"
DOC="${REPO_ROOT}/docs/FLEET-RSYSLOG-READINESS.md"

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

require_fixed() {
  local pattern=$1
  local file=$2
  grep -Fq -- "${pattern}" "${file}" || fail "missing text ${pattern} in ${file}"
}

require_file "${BASE_PACKAGES}"
require_fixed 'app-admin/rsyslog' "${BASE_PACKAGES}"

require_file "${BASE_PROFILE}"
require_fixed 'app-admin/rsyslog elasticsearch normalize openssl relp rfc3195 rfc5424hmac snmp ssl usertools uuid xxhash -systemd' "${BASE_PROFILE}"
require_fixed 'rsyslog' "${BASE_PROFILE}"

require_file "${BASE_METADATA}"
require_fixed 'app-admin/rsyslog' "${BASE_METADATA}"

require_file "${SERVICE_ATOMS}"
require_fixed 'id: syslog-client' "${SERVICE_ATOMS}"
require_fixed 'app-admin/rsyslog' "${SERVICE_ATOMS}"
require_fixed 'rsyslog' "${SERVICE_ATOMS}"
require_fixed 'tcp/6514' "${SERVICE_ATOMS}"
require_fixed 'omelasticsearch' "${SERVICE_ATOMS}"

require_file "${POLICY}"
require_fixed 'rsyslog_required_on_all_hosts: true' "${POLICY}"
require_fixed 'required_gentoo_atom: app-admin/rsyslog' "${POLICY}"
require_fixed 'required_openrc_service: rsyslog' "${POLICY}"
require_fixed 'required_rsyslog_modules:' "${POLICY}"
require_fixed 'omelasticsearch' "${POLICY}"
require_fixed 'log-sun99-rsyslog.rfc1918.host' "${POLICY}"

require_file "${AUDIT_PLAYBOOK}"
require_fixed 'fleet-rsyslog-readiness-audit' "${AUDIT_PLAYBOOK}"
require_fixed 'rsyslogd' "${AUDIT_PLAYBOOK}"
require_fixed 'rc-service' "${AUDIT_PLAYBOOK}"
require_fixed 'omelasticsearch' "${AUDIT_PLAYBOOK}"

require_executable "${SCRIPT}"
bash -n "${SCRIPT}"
require_fixed 'with-ansible-vault-env.sh' "${SCRIPT}"
require_fixed 'fleet-rsyslog-readiness-audit.yml' "${SCRIPT}"

require_file "${DOC}"
require_fixed 'rsyslog is mandatory on every fleet host.' "${DOC}"
require_fixed 'Build rsyslog with the Elasticsearch output module everywhere.' "${DOC}"
require_fixed 'M70 failing this audit means the host is not converged to base-minimal-nox.' "${DOC}"
if grep -Fq 'Docker' "${DOC}" "${SCRIPT}" "${POLICY}"; then
  fail "Docker reference found in fleet rsyslog readiness artifacts"
fi

printf 'PASS: %s\n' "$(basename "$0")"
