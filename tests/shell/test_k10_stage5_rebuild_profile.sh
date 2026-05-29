#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
HOST_VARS="${ANSIBLE_ROOT}/inventories/local-network/host_vars/gmktek_nucbox_k10_stage5_candidate.yml"
PROFILE="${ANSIBLE_ROOT}/profile-definitions/metal-workstation-basic-xorg.yml"
PROFILE_METADATA="${ANSIBLE_ROOT}/profile-definitions/metal-workstation-basic-xorg.metadata.yml"
MANIFEST="${ANSIBLE_ROOT}/netboot-image-manifests/k10-stage5-workstation.yml"
LIVEISO_PREPARE="${ANSIBLE_ROOT}/roles/liveiso_prepare/tasks/main.yml"
RECOVERY_SCRIPT="${ANSIBLE_ROOT}/scripts/k10-local-emerge-resume.sh"
RUN_TESTS="${REPO_ROOT}/tests/shell/run-tests.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_contains() {
  local path="$1"
  local needle="$2"
  assert_file "${path}"
  grep -Fq -- "${needle}" "${path}" || fail "missing '${needle}' in ${path}"
}

assert_not_contains() {
  local path="$1"
  local needle="$2"
  assert_file "${path}"
  if grep -Fq -- "${needle}" "${path}"; then
    fail "unexpected '${needle}' in ${path}"
  fi
}

assert_before() {
  local path="$1"
  local first="$2"
  local second="$3"
  assert_file "${path}"
  local first_line second_line
  first_line="$(grep -Fn -- "${first}" "${path}" | head -n1 | cut -d: -f1 || true)"
  second_line="$(grep -Fn -- "${second}" "${path}" | head -n1 | cut -d: -f1 || true)"
  [[ -n "${first_line}" ]] || fail "missing '${first}' in ${path}"
  [[ -n "${second_line}" ]] || fail "missing '${second}' in ${path}"
  ((first_line < second_line)) || fail "'${first}' must appear before '${second}' in ${path}"
}

assert_file "${HOST_VARS}"
assert_file "${PROFILE}"
assert_file "${PROFILE_METADATA}"
assert_file "${MANIFEST}"
assert_file "${LIVEISO_PREPARE}"
assert_file "${RECOVERY_SCRIPT}"

assert_contains "${RUN_TESTS}" "test_k10_stage5_rebuild_profile.sh"

assert_contains "${PROFILE}" "profile_id: metal-workstation-basic-xorg"
assert_contains "${PROFILE}" "stage5-base-minimal-nox.packages"
assert_contains "${PROFILE}" "stage5-base-minimal-xorg-slim.packages"
assert_contains "${PROFILE}" "stage5-metal-intel-platform.packages"
assert_contains "${PROFILE}" "stage5-domain-client-freeipa-minimal.packages"
assert_contains "${PROFILE}" "stage5-secure-firstboot-enrollment.packages"
assert_contains "${PROFILE}" 'ACCEPT_LICENSE="* *.*"'
assert_not_contains "${PROFILE}" "stage5-domain-client.packages"
assert_not_contains "${PROFILE}" '${STAGE5_BINPKG_PKGDIR:-'
assert_contains "${PROFILE}" 'FEATURES="${FEATURES} -ccache -distcc buildpkg parallel-install merge-sync"'
assert_contains "${PROFILE}" "VIDEO_CARDS=\"intel i915 modesetting fbdev\""
assert_contains "${PROFILE}" "dev-python/pillow -truetype"
assert_contains "${PROFILE}" "app-admin/sudo -sendmail"
assert_contains "${PROFILE}" "sys-apps/smartmontools -daemon"
assert_contains "${PROFILE}" "-wayland"
assert_contains "${PROFILE_METADATA}" "id: metal-workstation-basic-xorg"
assert_contains "${PROFILE_METADATA}" "Intel display-only Xorg"

assert_contains "${HOST_VARS}" "stage5_profile: metal-workstation-basic-xorg"
assert_contains "${HOST_VARS}" "liveiso_work_dir: /root/gentoo-liveiso-work/k10-stage5"
assert_contains "${HOST_VARS}" "install_target_root: /mnt/gentoo"
assert_contains "${HOST_VARS}" "storage_confirm_destroy: true"
assert_contains "${HOST_VARS}" "storage_layout: zfs-mirror"
assert_contains "${HOST_VARS}" "boot_create_efi_nvram_entry: false"
assert_contains "${HOST_VARS}" "portage_cpu_profile: intel_core_i9_13900hk"
assert_contains "${HOST_VARS}" "gpu_stack: intel"
assert_contains "${HOST_VARS}" "kernel_strategy: gentoo-kernel-bin"
assert_contains "${HOST_VARS}" "installer_prerequisites:"
assert_contains "${HOST_VARS}" "sys-apps/gptfdisk"
assert_contains "${HOST_VARS}" 'portage_accept_license: "* *.*"'
assert_contains "${HOST_VARS}" "portage_makeopts_jobs: 1"
assert_contains "${HOST_VARS}" "portage_emerge_jobs: 1"
assert_contains "${HOST_VARS}" "portage_load_average: 1"
assert_contains "${HOST_VARS}" "nvme-Force_MP600_230179710001314900AD"
assert_contains "${HOST_VARS}" "nvme-Force_MP600_2301797100013149004C"
assert_contains "${HOST_VARS}" "metal-workstation-basic-xorg.yml"
assert_contains "${HOST_VARS}" "hardened-llvm-stage4-split-usr.yml"
assert_contains "${HOST_VARS}" "llvm-clang-hardened-portage.yml"
assert_contains "${HOST_VARS}" "base-minimal-nox.yml"
assert_not_contains "${HOST_VARS}" "aaa-domain-client.yml"
assert_not_contains "${HOST_VARS}" "net-fs/samba"
assert_before "${HOST_VARS}" "base-minimal-nox.yml" "base-minimal-xorg-slim.yml"
assert_contains "${HOST_VARS}" "interface_name: enp4s0"
assert_contains "${HOST_VARS}" "mac_address: \"84:47:09:5F:21:64\""
assert_contains "${HOST_VARS}" "addresses:"
assert_contains "${HOST_VARS}" "172.16.99.156/24"
assert_contains "${HOST_VARS}" "gateway4: 172.16.99.1"
assert_contains "${HOST_VARS}" "console=tty0 console=ttyS0,115200"

assert_contains "${MANIFEST}" "role_script: roles/workstation-validation.ipxe"
assert_contains "${MANIFEST}" "installer_prerequisites:"
assert_contains "${MANIFEST}" "sys-apps/gptfdisk"
assert_contains "${MANIFEST}" "boot_create_efi_nvram_entry: false"

assert_contains "${LIVEISO_PREPARE}" "Install LiveISO installer prerequisites"
assert_contains "${LIVEISO_PREPARE}" "installer_prerequisites | default([])"
assert_before "${LIVEISO_PREPARE}" "Install LiveISO installer prerequisites" "Check required commands exist on the LiveISO"

assert_contains "${RECOVERY_SCRIPT}" 'FEATURES="-distcc -ccache buildpkg parallel-install merge-sync -fail-clean"'
assert_contains "${RECOVERY_SCRIPT}" "k10-resume-markers"
assert_contains "${RECOVERY_SCRIPT}" "K10_REBOOT_ON_SUCCESS"
assert_contains "${RECOVERY_SCRIPT}" "net-misc/networkmanager"
assert_not_contains "${RECOVERY_SCRIPT}" "net-fs/samba"
assert_not_contains "${RECOVERY_SCRIPT}" "sys-process/anacron"

printf 'PASS: %s\n' "$(basename "$0")"
