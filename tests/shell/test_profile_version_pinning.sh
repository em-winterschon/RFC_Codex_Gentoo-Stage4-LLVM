#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
LOCK_FILE="${ANSIBLE_ROOT}/app-version-locks/stage5-service-apps.yml"
DOC="${REPO_ROOT}/docs/PACKAGE-VERSION-PINNING.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_grep() {
  local pattern=$1
  local file=$2
  grep -q -- "${pattern}" "${file}" || fail "missing pattern '${pattern}' in ${file}"
}

require_file "${LOCK_FILE}"
require_grep 'app_version_lock_version: 1' "${LOCK_FILE}"
require_grep 'sonatype-nexus-repository-oss' "${LOCK_FILE}"
require_grep '3.90.1-01' "${LOCK_FILE}"
require_grep 'netbox' "${LOCK_FILE}"
require_grep 'v4.5.9' "${LOCK_FILE}"
require_grep 'elasticsearch' "${LOCK_FILE}"
require_grep '9.3.1' "${LOCK_FILE}"
require_grep 'pin_gaps:' "${LOCK_FILE}"

for metadata in "${ANSIBLE_ROOT}"/profile-definitions/*.metadata.yml; do
  require_grep 'package_pins:' "${metadata}"
done

require_file "${DOC}"
require_grep 'app-version-locks/stage5-service-apps.yml' "${DOC}"
require_grep 'pin_gaps' "${DOC}"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
