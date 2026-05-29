#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
ROLE_DIR="${ANSIBLE_ROOT}/roles/nvidia_doca_ofed"
MATRIX="${REPO_ROOT}/docs/workflows/doca-host-source-of-truth.yml"
DOC="${REPO_ROOT}/docs/RDMA-DOCA-HOST-SOURCE-GATE.md"
WIKI="${REPO_ROOT}/docs/wiki/RDMA-DOCA-Host-Source-Gate.md"
BUILDER="${REPO_ROOT}/scripts/fmt2-build-mlnx-ofed-rhel-kernel.sh"
LANE_BUILDER="${REPO_ROOT}/scripts/fmt2-doca-repo-lane-build.sh"

assert_file_contains() {
  local file=$1
  local pattern=$2
  if ! grep -q -- "${pattern}" "${file}"; then
    printf 'FAIL: %s missing pattern: %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

for file in \
  "${MATRIX}" \
  "${DOC}" \
  "${WIKI}" \
  "${LANE_BUILDER}" \
  "${ROLE_DIR}/defaults/main.yml" \
  "${ROLE_DIR}/tasks/main.yml" \
  "${BUILDER}"; do
  test -f "${file}"
done

assert_file_contains "${MATRIX}" 'kind: DocaHostSourceOfTruth'
assert_file_contains "${MATRIX}" 'doca_host_version: 3.3.0'
assert_file_contains "${MATRIX}" 'legacy_doca_version: 2.9.4'
assert_file_contains "${MATRIX}" 'https://docs.nvidia.com/doca/sdk/DOCA-Host-Installation-and-DKMS-Management-Guide/index.html'
assert_file_contains "${MATRIX}" 'https://docs.nvidia.com/doca/sdk/General-Support/index.html'
assert_file_contains "${MATRIX}" 'https://docs.nvidia.com/doca/archive/2-9-4/general-support/index.html'
assert_file_contains "${MATRIX}" 'doca-2.9.4-cx4-rocky9.6'
assert_file_contains "${MATRIX}" '5.14.0-570.12.1.el9_6.x86_64'
assert_file_contains "${MATRIX}" 'Rocky Linux 10'
assert_file_contains "${MATRIX}" '6.12.0-124.8.1.el10_1.x86_64'
assert_file_contains "${MATRIX}" 'kernel.org'
assert_file_contains "${MATRIX}" '6.18'
assert_file_contains "${MATRIX}" 'doca-ofed-only'
assert_file_contains "${MATRIX}" 'BlueField-2'
assert_file_contains "${MATRIX}" 'ConnectX-5'
assert_file_contains "${MATRIX}" 'ConnectX-4'
assert_file_contains "${MATRIX}" 'legacy-doca-2.9-lts-build-lane'
assert_file_contains "${MATRIX}" 'nasa-yum-repo-doca-host/doca-2.9.4/el9/x86_64'
assert_file_contains "${MATRIX}" 'nasa-yum-repo-doca-host/doca-3.3.0/el10/x86_64'
assert_file_contains "${MATRIX}" 'issue: 111'

assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_supported_doca_host_version: 3.3.0'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_repo_package_type: auto'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_repo_rpm_url: ""'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_repo_rpm_path: ""'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_supported_kernel_targets:'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'rocky10-doca-3.3.0'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'rocky9.6-doca-2.9.4-connectx4'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'kernel.org-6.18-doca-ofed-only'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_legacy_connectx4_policy: legacy-doca-2.9-lts-build-lane'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nvidia_doca_ofed_artifact_root: /srv/stage/doca-host'

assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'Assert DOCA/OFED repository package type is explicit for apply'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'nvidia_doca_ofed_repo_package_type in'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'Install NVIDIA DOCA/OFED RPM repository package'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'ansible.builtin.dnf:'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'Refresh dnf cache after NVIDIA repository installation'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'Install NVIDIA DOCA/OFED packages with dnf'

assert_file_contains "${BUILDER}" 'DOCA_HOST_VERSION'
assert_file_contains "${BUILDER}" 'DOCA_HOST_ARTIFACT_ROOT'
assert_file_contains "${BUILDER}" 'PUBLISH_DIR'
assert_file_contains "${BUILDER}" 'publish-artifacts'
assert_file_contains "${LANE_BUILDER}" 'DOCA_LANE'
assert_file_contains "${LANE_BUILDER}" 'doca-2.9.4-cx4-rocky9.6'
assert_file_contains "${LANE_BUILDER}" 'doca-3.3.0-bf2-cx5-rocky10.1'
assert_file_contains "${LANE_BUILDER}" 'NASA_REPO_ROOT'
assert_file_contains "${LANE_BUILDER}" 'createrepo_c'
assert_file_contains "${LANE_BUILDER}" 'APPLY_REPO_SYNC'

assert_file_contains "${DOC}" 'Rocky Linux 10 is the primary current DOCA host lane'
assert_file_contains "${DOC}" 'DOCA 2.9.4 LTS is the ConnectX-4 lane'
assert_file_contains "${DOC}" 'kernel.org 6.18'
assert_file_contains "${DOC}" 'doca-ofed-only'
assert_file_contains "${DOC}" 'ConnectX-4 firmware must be updated before the DOCA 2.9.4 lane is evaluated'
assert_file_contains "${WIKI}" 'Issue #111'

printf 'PASS: %s\n' "$(basename "$0")"
