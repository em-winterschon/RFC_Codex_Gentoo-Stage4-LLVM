#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PROFILE_DIR="${ANSIBLE_ROOT}/profile-definitions"
PACKAGE_LIST_DIR="${ANSIBLE_ROOT}/profile-package-lists"
SERVICE_ATOMS="${ANSIBLE_ROOT}/profile-service-atoms/stage5-role-service-atoms.yml"
DOC_FILE="${REPO_ROOT}/docs/ROLE-PACKAGE-TAXONOMY.md"
WIKI_FILE="${REPO_ROOT}/docs/wiki/Role-Package-Taxonomy.md"

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

for profile in \
  base-minimal-nox.yml \
  base-minimal-xorg-slim.yml \
  base-hypervisor-xen.yml \
  base-hypervisor-qemu-libvirt.yml \
  base-hypervisor-xen-qemu-libvirt.yml \
  virt-minimal.yml \
  virt-xorg.yml; do
  require_file "${PROFILE_DIR}/${profile}"
  require_file "${PROFILE_DIR}/${profile%.yml}.metadata.yml"
  require_grep '^gentoo_profile_definition:' "${PROFILE_DIR}/${profile}"
  require_grep '^gentoo_system_profile_metadata:' "${PROFILE_DIR}/${profile%.yml}.metadata.yml"
  require_grep 'package_pins:' "${PROFILE_DIR}/${profile%.yml}.metadata.yml"
done

for package_list in \
  stage5-base-minimal-nox.packages \
  stage5-base-minimal-xorg-slim.packages \
  stage5-base-hypervisor-common.packages \
  stage5-base-hypervisor-xen.packages \
  stage5-base-hypervisor-qemu-libvirt.packages \
  stage5-virt-minimal.packages \
  stage5-virt-xorg.packages; do
  require_file "${PACKAGE_LIST_DIR}/${package_list}"
done

for atom in \
  '^app-admin/rsyslog$' \
  '^net-misc/openssh$' \
  '^app-portage/gentoolkit$' \
  '^sys-apps/lm-sensors$' \
  '^sys-apps/ethtool$' \
  '^sys-apps/net-tools$' \
  '^sys-process/btop$' \
  '^sys-process/iotop-c$' \
  '^sys-process/time$' \
  '^sys-process/psmisc$' \
  '^sys-process/parallel$' \
  '^sys-process/wait_on_pid$' \
  '^sys-process/watchpid$' \
  '^sys-process/numad$' \
  '^sys-process/numactl$' \
  '^sys-process/daemontools$'; do
  require_grep "${atom}" "${PACKAGE_LIST_DIR}/stage5-base-minimal-nox.packages"
done

require_grep 'app-admin/logrotate -cron' "${PROFILE_DIR}/base-minimal-nox.yml"
require_grep 'app-admin/sudo -sendmail' "${PROFILE_DIR}/base-minimal-nox.yml"
require_grep 'sys-apps/smartmontools -daemon' "${PROFILE_DIR}/base-minimal-nox.yml"

for atom in \
  '^x11-base/xorg-server$' \
  '^x11-misc/slim$' \
  '^x11-apps/xinit$'; do
  require_grep "${atom}" "${PACKAGE_LIST_DIR}/stage5-base-minimal-xorg-slim.packages"
done

for atom in \
  '^=app-emulation/xen-4\.19\.3$' \
  '^=app-emulation/xen-tools-4\.19\.3$'; do
  require_grep "${atom}" "${PACKAGE_LIST_DIR}/stage5-base-hypervisor-xen.packages"
done

for atom in \
  '^=app-emulation/qemu-10\.2\.2$' \
  '^=app-emulation/libvirt-12\.0\.0$' \
  '^=app-emulation/guestfs-tools-1\.52\.3-r1$'; do
  require_grep "${atom}" "${PACKAGE_LIST_DIR}/stage5-base-hypervisor-qemu-libvirt.packages"
done

for atom in \
  '^=app-emulation/qemu-guest-agent-9\.2\.0$' \
  '^sys-apps/ethtool$'; do
  require_grep "${atom}" "${PACKAGE_LIST_DIR}/stage5-virt-minimal.packages"
done

require_file "${SERVICE_ATOMS}"
require_grep 'role_service_atoms_version: 1' "${SERVICE_ATOMS}"
require_grep 'base-minimal-nox:' "${SERVICE_ATOMS}"
require_grep 'base-hypervisor-xen-qemu-libvirt:' "${SERVICE_ATOMS}"
require_grep 'virt-xorg:' "${SERVICE_ATOMS}"
require_grep 'vm-container-services:' "${SERVICE_ATOMS}"
require_grep 'openrc_services:' "${SERVICE_ATOMS}"
require_grep 'libvirtd' "${SERVICE_ATOMS}"
require_grep 'xendomains' "${SERVICE_ATOMS}"
require_grep 'sshd' "${SERVICE_ATOMS}"
require_grep 'lm_sensors' "${PROFILE_DIR}/base-minimal-nox.yml"
require_grep 'lm_sensors' "${PROFILE_DIR}/base-minimal-nox.metadata.yml"

require_file "${DOC_FILE}"
require_file "${WIKI_FILE}"
require_grep 'base-minimal-nox' "${DOC_FILE}"
require_grep 'base-hypervisor-xen-qemu-libvirt' "${DOC_FILE}"
require_grep 'VM roles compose the same base-minimal package layer' "${DOC_FILE}"
require_grep 'base-minimal-nox' "${WIKI_FILE}"

printf 'PASS: %s\n' "$(basename "$0")"
