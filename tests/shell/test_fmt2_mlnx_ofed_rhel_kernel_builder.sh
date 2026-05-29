#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/fmt2-build-mlnx-ofed-rhel-kernel.sh"
DOC="${REPO_ROOT}/docs/FMT2-R630-HCI-STAGED-REBUILD.md"
RDMA_DOC="${REPO_ROOT}/docs/RDMA-STORAGE-FABRIC-PLAN.md"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

test -f "${SCRIPT}"
test -x "${SCRIPT}" || test -r "${SCRIPT}"

assert_file_contains "${SCRIPT}" 'OFED_SHA256'
assert_file_contains "${SCRIPT}" '6401c0e49f12da0bceb1b03037e39eed2b11e3624dcba139485d2e1631ce5682'
assert_file_contains "${SCRIPT}" 'APPLY_CREATE_BUILDROOT'
assert_file_contains "${SCRIPT}" 'APPLY_BUILD'
assert_file_contains "${SCRIPT}" 'systemd-nspawn'
assert_file_contains "${SCRIPT}" '--kernel-only --build-only'
assert_file_contains "${SCRIPT}" 'OFED_EXTRA_ARGS'
assert_file_contains "${SCRIPT}" '--distro'
assert_file_contains "${SCRIPT}" 'rhel8.9'
assert_file_contains "${SCRIPT}" 'mlnx-ofed-buildroot'
assert_file_contains "${DOC}" 'MLNX_OFED diagnostic-only source-build path'
assert_file_contains "${DOC}" '6.3.8-1.el8.elrepo.x86_64'
assert_file_contains "${DOC}" '4.18.0-513.5.1.el8_9'
assert_file_contains "${DOC}" 'diagnostic-only'
assert_file_contains "${RDMA_DOC}" 'The DOCA/OFED build path now splits into two isolated lanes'
assert_file_contains "${RDMA_DOC}" 'DOCA 2.9.4 LTS for ConnectX-4'
assert_file_contains "${RDMA_DOC}" 'DOCA Host 3.3.0 for BlueField-2 and ConnectX-5'

printf 'PASS: %s\n' "$(basename "$0")"
