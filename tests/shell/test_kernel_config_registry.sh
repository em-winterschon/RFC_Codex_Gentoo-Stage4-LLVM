#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
REGISTRY="${ANSIBLE_ROOT}/kernel-config/kernel-profile-map.yml"
CPU_PROFILES="${ANSIBLE_ROOT}/vars/cpu_profiles.yml"
DOC="${REPO_ROOT}/docs/KERNEL-CONFIG-ARCHITECTURE.md"
WIKI_DOC="${REPO_ROOT}/docs/wiki/Kernel-Config-Architecture.md"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    printf 'missing required file: %s\n' "${path}" >&2
    exit 1
  fi
}

require_grep() {
  local pattern="$1"
  local path="$2"
  if ! grep -Eq "${pattern}" "${path}"; then
    printf 'missing pattern %q in %s\n' "${pattern}" "${path}" >&2
    exit 1
  fi
}

require_file "${REGISTRY}"
require_file "${CPU_PROFILES}"
require_file "${DOC}"
require_file "${WIKI_DOC}"

for fragment in \
  fragments/base/basic-minimal.config \
  fragments/machine/metal-host.config \
  fragments/machine/virtual-guest.config \
  fragments/machine/hypervisor-qemu-libvirt.config \
  fragments/machine/hypervisor-xen.config \
  fragments/hardware/optane-nvdimm.config \
  fragments/hardware/intel-qat-c3000.config \
  fragments/hardware/gpu-universal-xorg.config \
  fragments/storage/nfs-client.config \
  fragments/storage/rdma-storage-fabric.config \
  fragments/storage/nvmeof-initiator.config \
  fragments/storage/zfs-host.config \
  fragments/network/roce-v2-host.config \
  fragments/observability/redfish-ipmi.config; do
  require_file "${ANSIBLE_ROOT}/kernel-config/${fragment}"
done

BASE="${ANSIBLE_ROOT}/kernel-config/fragments/base/basic-minimal.config"
OPTANE="${ANSIBLE_ROOT}/kernel-config/fragments/hardware/optane-nvdimm.config"
QAT_C3000="${ANSIBLE_ROOT}/kernel-config/fragments/hardware/intel-qat-c3000.config"

require_grep '^CONFIG_DEVTMPFS=y$' "${BASE}"
require_grep '^CONFIG_EFI_STUB=y$' "${BASE}"
require_grep '^CONFIG_BLK_DEV_INITRD=y$' "${BASE}"
require_grep '^CONFIG_SQUASHFS_ZLIB=y$' "${BASE}"
require_grep '^CONFIG_OVERLAY_FS=y$' "${BASE}"

require_grep '^CONFIG_ACPI_NFIT=m$' "${OPTANE}"
require_grep '^CONFIG_LIBNVDIMM=m$' "${OPTANE}"
require_grep '^CONFIG_DEV_DAX_PMEM=m$' "${OPTANE}"

require_grep '^CONFIG_CRYPTO_DEV_QAT=m$' "${QAT_C3000}"
require_grep '^CONFIG_CRYPTO_DEV_QAT_C3XXX=m$' "${QAT_C3000}"
require_grep '^CONFIG_CRYPTO_DEV_QAT_C3XXXVF=m$' "${QAT_C3000}"
require_grep '^CONFIG_QAT_VFIO_PCI=m$' "${QAT_C3000}"

require_grep 'optane-nvdimm:' "${REGISTRY}"
require_grep 'intel-qat-c3000:' "${REGISTRY}"
require_grep 'fragments/hardware/intel-qat-c3000.config' "${REGISTRY}"
require_grep 'x12again' "${REGISTRY}"
require_grep 'prinzessin' "${REGISTRY}"
require_grep 'coherence-ce-node:' "${REGISTRY}"
require_grep 'storage-node:' "${REGISTRY}"
require_grep 'nfs-storage-client:' "${REGISTRY}"
require_grep 'rdma-storage-fabric:' "${REGISTRY}"

require_grep 'cpuid2cpuflags_capture_required:' "${CPU_PROFILES}"
require_grep 'cpu_flags_x86_override:' "${CPU_PROFILES}"
require_grep 'source_provenance:' "${CPU_PROFILES}"

require_grep '/tmp/docs/cpu-arch/RFC1918-CPU-Architectures.md' "${DOC}"
require_grep 'Path-B' "${DOC}"
require_grep 'Optane NVDIMM' "${DOC}"
require_grep 'Intel C3000 QAT' "${DOC}"
require_grep 'cpuid2cpuflags' "${DOC}"
require_grep 'kernel-profile-map.yml' "${WIKI_DOC}"

printf 'PASS: %s\n' "$(basename "$0")"
