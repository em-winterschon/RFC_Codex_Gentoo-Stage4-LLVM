#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PLAN="${REPO_ROOT}/docs/superpowers/plans/2026-05-20-fmt2-r630-kolla-podman-rocky10.md"
FMT2_DOC="${REPO_ROOT}/docs/FMT2-R630-HCI-STAGED-REBUILD.md"
FMT2_WIKI="${REPO_ROOT}/docs/wiki/FMT2-R630-HCI-Staged-Rebuild.md"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

test -f "${PLAN}"

assert_file_contains "${PLAN}" 'Kolla-Ansible + Podman on Rocky Linux 10'
assert_file_contains "${PLAN}" 'kolla_container_engine: podman'
assert_file_contains "${PLAN}" 'kolla_base_distro: "rocky"'
assert_file_contains "${PLAN}" 'Rocky Linux 10'
assert_file_contains "${PLAN}" 'kolla-ansible bootstrap-servers'
assert_file_contains "${PLAN}" 'kolla-ansible prechecks'
assert_file_contains "${PLAN}" 'kolla-ansible deploy'
assert_file_contains "${PLAN}" 'kolla-ansible post-deploy'
assert_file_contains "${PLAN}" 'kolla-ansible validate-config'
assert_file_contains "${PLAN}" 'network_interface'
assert_file_contains "${PLAN}" 'api_interface'
assert_file_contains "${PLAN}" 'kolla_external_vip_interface'
assert_file_contains "${PLAN}" 'neutron_external_interface'
assert_file_contains "${PLAN}" 'eno1'
assert_file_contains "${PLAN}" 'eno2'
assert_file_contains "${PLAN}" 'eno3'
assert_file_contains "${PLAN}" 'eno4'
assert_file_contains "${PLAN}" 'enp130s0f0np0'
assert_file_contains "${PLAN}" 'enp130s0f1np1'
assert_file_contains "${PLAN}" 'OpenStack-Ansible + LXC fallback'
assert_file_contains "${PLAN}" 'Do not use native Gentoo OpenStack services'
assert_file_contains "${PLAN}" 'Do not use Rocky 9 for the first Kolla deployment'
assert_file_contains "${PLAN}" 'Do not wipe `ter`'
assert_file_contains "${PLAN}" 'SOL remains enabled'
assert_file_contains "${PLAN}" 'https://docs.openstack.org/kolla-ansible/latest/user/support-matrix.html'
assert_file_contains "${PLAN}" 'https://docs.openstack.org/kolla-ansible/2026.1/admin/advanced-configuration.html'
assert_file_contains "${PLAN}" 'https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html'
assert_file_contains "${PLAN}" 'https://docs.openstack.org/kolla-ansible/latest/admin/production-architecture-guide.html'

assert_file_contains "${FMT2_DOC}" 'Kolla-Ansible + Podman on Rocky Linux 10'
assert_file_contains "${FMT2_DOC}" '2026-05-20-fmt2-r630-kolla-podman-rocky10.md'
assert_file_contains "${FMT2_WIKI}" 'Kolla-Ansible + Podman on Rocky Linux 10'
assert_file_contains "${FMT2_WIKI}" '2026-05-20-fmt2-r630-kolla-podman-rocky10.md'

printf 'PASS: %s\n' "$(basename "$0")"
