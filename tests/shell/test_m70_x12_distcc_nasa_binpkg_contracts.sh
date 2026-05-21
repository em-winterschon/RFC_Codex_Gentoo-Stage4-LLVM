#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  test -f "${file}" || fail "missing file ${file}"
  grep -Fq -- "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_file_contains_regex() {
  local file=$1
  local pattern=$2
  test -f "${file}" || fail "missing file ${file}"
  grep -Eq -- "${pattern}" "${file}" || fail "expected ${file} to match ${pattern}"
}

m70_host_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/admin_sun99_forge_099070.yml"
x12_host_vars="${ANSIBLE_ROOT}/inventories/local-network/host_vars/x12again_workstation_xen_coherent.yml"
contracts="${ANSIBLE_ROOT}/vars/gentoo_binpkg_contracts.yml"
doc="${REPO_ROOT}/docs/M70-X12-DISTCC-NASA-BINPKG.md"
wiki_doc="${REPO_ROOT}/docs/wiki/M70-X12-Distcc-NASA-Binpkg.md"

assert_file_contains "${m70_host_vars}" 'profile_distcc_farm:'
assert_file_contains "${m70_host_vars}" 'client_enabled: true'
assert_file_contains "${m70_host_vars}" 'address: 172.16.99.108'
assert_file_contains "${m70_host_vars}" 'slots: 48'
assert_file_contains "${m70_host_vars}" 'compression: true'
assert_file_contains "${m70_host_vars}" 'makeopts_jobs: "16 -l12"'
assert_file_contains "${m70_host_vars}" 'portage_pkgdir: /srv/build-cache/binpkgs'
assert_file_contains "${m70_host_vars}" 'portage_buildpkg_enabled: true'
assert_file_contains "${m70_host_vars}" 'portage_getbinpkg_enabled: true'
assert_file_contains "${m70_host_vars}" 'portage_usepkg_enabled: true'
assert_file_contains "${m70_host_vars}" 'nasa_binpkg_publish_root: /mnt/nasa/forge/gentoo-binpkgs'
assert_file_contains "${m70_host_vars}" 'baseline-portable-openrc-llvm'

assert_file_contains "${x12_host_vars}" 'profile_distcc_farm:'
assert_file_contains "${x12_host_vars}" 'worker_enabled: true'
assert_file_contains "${x12_host_vars}" 'listen_address: 172.16.99.108'
assert_file_contains "${x12_host_vars}" 'allowed_client_cidrs:'
assert_file_contains "${x12_host_vars}" '172.16.99.70/32'
assert_file_contains "${x12_host_vars}" 'jobs: 48'
assert_file_contains "${x12_host_vars}" 'service_user: distcc'
assert_file_contains "${x12_host_vars}" 'worker_metadata:'
assert_file_contains "${x12_host_vars}" 'cpu_class: x12-icelake-server'

assert_file_contains "${contracts}" 'gentoo_binpkg_repository_root: /mnt/nasa/forge/gentoo-binpkgs'
assert_file_contains "${contracts}" 'baseline-portable-openrc-llvm'
assert_file_contains "${contracts}" 'm70-goldmont-openrc-llvm'
assert_file_contains "${contracts}" 'k10-raptorlake-openrc-llvm'
assert_file_contains "${contracts}" 'x12-icelake-server-openrc-llvm'
assert_file_contains "${contracts}" 'r630-broadwell-openrc-llvm'
assert_file_contains "${contracts}" 'avoid_cpu_flags:'
assert_file_contains "${contracts}" 'avx512'
assert_file_contains "${contracts}" 'intel_sha'

assert_file_contains "${doc}" 'P0 durable build-cache contract'
assert_file_contains "${doc}" 'X12AGAIN is a distcc worker only'
assert_file_contains "${doc}" 'Do not build directly into NFS'
assert_file_contains "${doc}" 'baseline-portable-openrc-llvm'
assert_file_contains "${doc}" 'r630-broadwell-openrc-llvm'
assert_file_contains "${doc}" 'Broadwell R630 hosts must not consume M70 packages that require Intel SHA'
assert_file_contains "${doc}" 'emaint binhost --fix'
assert_file_contains "${doc}" 'scripts/sync-binpkgs-to-repo.sh'
assert_file_contains "${doc}" '/mnt/nasa/forge/gentoo-binpkgs/contracts/x86_64-pc-linux-gnu'
assert_file_contains_regex "${doc}" 'PORTAGE_BINHOST=.*baseline-portable-openrc-llvm'

assert_file_contains "${wiki_doc}" 'P0 durable build-cache contract'
assert_file_contains "${wiki_doc}" 'X12AGAIN is a distcc worker only'

assert_file_contains "${SCRIPT_DIR}/run-tests.sh" 'test_m70_x12_distcc_nasa_binpkg_contracts.sh'

printf 'PASS: %s\n' "$(basename "$0")"
