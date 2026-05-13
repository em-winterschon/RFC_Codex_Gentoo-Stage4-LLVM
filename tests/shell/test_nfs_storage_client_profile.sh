#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PROFILE_DIR="${ANSIBLE_ROOT}/profile-definitions"
PACKAGE_LIST_DIR="${ANSIBLE_ROOT}/profile-package-lists"
ROLE_DIR="${ANSIBLE_ROOT}/roles/nfs_storage_client"
DOC_FILE="${REPO_ROOT}/docs/NFS-STORAGE-CLIENT.md"
WIKI_FILE="${REPO_ROOT}/docs/wiki/NFS-Storage-Client.md"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q "${pattern}" "${file}"
}

test -f "${PROFILE_DIR}/nfs-storage-client.yml"
test -f "${PROFILE_DIR}/nfs-storage-client.metadata.yml"
test -f "${PACKAGE_LIST_DIR}/stage5-storage-nfs-client.packages"

assert_file_contains "${PROFILE_DIR}/nfs-storage-client.yml" '^gentoo_profile_definition:'
assert_file_contains "${PROFILE_DIR}/nfs-storage-client.metadata.yml" '^gentoo_system_profile_metadata:'
assert_file_contains "${PROFILE_DIR}/nfs-storage-client.yml" 'nfsv3_tcp_default'
assert_file_contains "${PROFILE_DIR}/nfs-storage-client.yml" 'nfsv4_tcp_rbac_uid_gid'
assert_file_contains "${PROFILE_DIR}/nfs-storage-client.yml" 'nfs_tcp'
assert_file_contains "${PROFILE_DIR}/nfs-storage-client.yml" 'nfs_rdma'
assert_file_contains "${PROFILE_DIR}/nfs-storage-client.yml" 'nfs_multipath'
assert_file_contains "${PROFILE_DIR}/nfs-storage-client.yml" 'aaa-domain-client'

for package_atom in \
  '^net-fs/nfs-utils$' \
  '^net-nds/rpcbind$' \
  '^sys-cluster/rdma-core$' \
  '^sys-fs/multipath-tools$'; do
  assert_file_contains "${PACKAGE_LIST_DIR}/stage5-storage-nfs-client.packages" "${package_atom}"
done

for kernel_symbol in \
  CONFIG_NFS_FS \
  CONFIG_NFS_V3 \
  CONFIG_NFS_V4 \
  CONFIG_NFS_V4_1 \
  CONFIG_NFS_V4_2 \
  CONFIG_ROOT_NFS \
  CONFIG_SUNRPC_XPRT_RDMA \
  CONFIG_NFS_V4_1_IMPLEMENTATION_ID_DOMAIN \
  CONFIG_DM_MULTIPATH; do
  assert_file_contains "${PROFILE_DIR}/nfs-storage-client.yml" "${kernel_symbol}"
done

test -f "${ROLE_DIR}/defaults/main.yml"
test -f "${ROLE_DIR}/tasks/main.yml"
test -f "${ROLE_DIR}/templates/idmapd.conf.j2"
test -f "${ROLE_DIR}/templates/nfs.conf.j2"
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nfs_storage_client_protocol_default: nfsv3_tcp'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nfs_storage_client_enable_rdma: false'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nfs_storage_client_enable_multipath: false'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nfs_storage_client_nconnect: 4'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'rpcbind'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'rpc.statd'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'nfsclient'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'netmount'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'idmapd.conf'
assert_file_contains "${ROLE_DIR}/templates/nfs.conf.j2" 'rdma-port'
assert_file_contains "${ROLE_DIR}/templates/nfs.conf.j2" 'vers4.2'
assert_file_contains "${ROLE_DIR}/templates/idmapd.conf.j2" 'Domain ='

test -f "${DOC_FILE}"
test -f "${WIKI_FILE}"
assert_file_contains "${DOC_FILE}" 'NFSv3 over TCP remains the default'
assert_file_contains "${DOC_FILE}" 'NFSv4 requires centralized AAA'
assert_file_contains "${DOC_FILE}" 'NFS-RDMA'
assert_file_contains "${DOC_FILE}" 'Issue #117'
assert_file_contains "${DOC_FILE}" 'Containers do not inherit this profile by default'
assert_file_contains "${WIKI_FILE}" 'NFSv3 over TCP remains the default'
assert_file_contains "${WIKI_FILE}" 'Issue #117'

printf 'PASS: %s\n' "$(basename "$0")"
