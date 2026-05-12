#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
OVERLAY_ROOT="${REPO_ROOT}/container-image-definitions/overlays/gentoo-stage4-image-fixes"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

profile="${ANSIBLE_ROOT}/profile-definitions/vm-coherence-ce-node.yml"
metadata="${ANSIBLE_ROOT}/profile-definitions/vm-coherence-ce-node.metadata.yml"
packages="${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-coherence-ce-node.packages"
role="${ANSIBLE_ROOT}/roles/coherence_ce_service"
service_atoms="${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml"
ebuild="${OVERLAY_ROOT}/dev-java/oracle-coherence-ce/oracle-coherence-ce-9999.ebuild"

test -f "${profile}"
test -f "${metadata}"
test -f "${packages}"
test -d "${role}"
test -f "${ebuild}"

assert_file_contains "${profile}" 'vm-coherence-ce-node'
assert_file_contains "${profile}" 'coherence_ce_service'
assert_file_contains "${metadata}" 'https://github.com/oracle/coherence'
assert_file_contains "${metadata}" 'disabled by default'
assert_file_contains "${packages}" '^virtual/jre$'
assert_file_contains "${service_atoms}" 'vm-coherence-ce-node'
assert_file_contains "${service_atoms}" 'coherence-ce-cache-node'
assert_file_contains "${role}/defaults/main.yml" 'coherence_ce_service_enabled: false'
assert_file_contains "${role}/tasks/main.yml" 'coherence_ce_service_mutation_enabled'
assert_file_contains "${role}/templates/coherence-ce.confd.j2" 'COHERENCE_CE_CLUSTER_NAME'
assert_file_contains "${role}/templates/coherence-ce.initd.j2" 'coherence.management.http.port'
assert_file_contains "${OVERLAY_ROOT}/profiles/categories" '^dev-java$'
assert_file_contains "${OVERLAY_ROOT}/profiles/package.mask" 'dev-java/oracle-coherence-ce'
assert_file_contains "${ebuild}" 'EGIT_REPO_URI="https://github.com/oracle/coherence.git"'
assert_file_contains "${ebuild}" 'pinned Jenkins build workflow'

printf 'PASS: %s\n' "$(basename "$0")"
