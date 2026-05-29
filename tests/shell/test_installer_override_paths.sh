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
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected '${needle}' in ${path}"
}

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${path}"; then
    fail "did not expect '${needle}' in ${path}"
  fi
}

assert_file_not_contains_token() {
  local path="$1"
  local token="$2"
  if grep -Eq "(^|[[:space:]'\\\"])${token}($|[[:space:]'\\\"])" "${path}"; then
    fail "did not expect token '${token}' in ${path}"
  fi
}

test_portage_override_paths_exist() {
  assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml" "resolved_portage_env_files"
  assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml" "resolved_portage_package_env_files"
  assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml" "resolved_portage_package_accept_keywords_files"
  assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml" "resolved_kernel_config_fragment_files"
  assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml" "gentoo_profile_definition.env_files"
  assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml" "gentoo_profile_definition.package_env_files"
  assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml" "package_accept_keywords_files"
  assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml" "kernel_config_fragment_files"
  assert_file_contains "${ANSIBLE_ROOT}/roles/portage/tasks/main.yml" "/etc/portage/env"
  assert_file_contains "${ANSIBLE_ROOT}/roles/portage/tasks/main.yml" "/etc/portage/package.env"
  assert_file_contains "${ANSIBLE_ROOT}/roles/portage/tasks/main.yml" "/etc/portage/package.accept_keywords"
  assert_file_contains "${ANSIBLE_ROOT}/roles/kernel_config/tasks/main.yml" "/etc/kernel/config.d"
  assert_file_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" "zfs_package_atom"
  assert_file_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" "zfs_kmod_package_atom"
}

test_qemu_alias_inventory_uses_source_kernel_path() {
  assert_file_contains "${ANSIBLE_ROOT}/inventories/qemu-alias/group_vars/install_targets.yml" "kernel_strategy: gentoo-kernel"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/qemu-alias/group_vars/install_targets.yml" "kernel_package_atom_override: =sys-kernel/gentoo-kernel-6.18.18"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/qemu-alias/group_vars/install_targets.yml" "zfs_package_atom: =sys-fs/zfs-2.3.6"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/qemu-alias/group_vars/install_targets.yml" "zfs_kmod_package_atom: =sys-fs/zfs-kmod-2.3.6"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/qemu-alias/group_vars/install_targets.yml" "portage_package_accept_keywords_files: {}"
  assert_file_contains "${ANSIBLE_ROOT}/inventories/qemu-alias/group_vars/install_targets.yml" "kernel_config_fragment_files:"
}

test_boot_commandline_templates_do_not_regress_console_typo() {
  assert_file_contains "${ANSIBLE_ROOT}/roles/boot/defaults/main.yml" "console=tty0"
  assert_file_contains "${ANSIBLE_ROOT}/roles/boot/defaults/main.yml" "install_kernel_cmdline | default('ro console=tty0 console=ttyS0,115200')"
  assert_file_not_contains "${ANSIBLE_ROOT}/roles/boot/defaults/main.yml" "root=[^"
  assert_file_contains "${ANSIBLE_ROOT}/roles/boot/defaults/main.yml" "reject('match', '^root=')"
  assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" "console=tty0"
  assert_file_not_contains_token "${ANSIBLE_ROOT}/roles/boot/defaults/main.yml" "sole=tty0"
  assert_file_not_contains_token "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" "sole=tty0"
  assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" "zgenhostid -f"
  assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" "install_items+=\" /etc/hostid \""
  assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" "spl_hostid="
  assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" "argv:"
  assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" "org.zfsbootmenu:commandline={{ zfsbootmenu_root_commandline_effective }}"
  assert_file_not_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" "src: /etc/hostid"
}

test_profile_parent_template_is_resume_safe() {
  local parent_template="${ANSIBLE_ROOT}/roles/profile/templates/parent.j2"

  assert_file_contains "${parent_template}" "resolved_profile_parents | default(profile_parents | default([]))"
}

test_llvm_clang_portage_profile_exists() {
  local profile="${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml"
  local metadata="${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.metadata.yml"

  assert_file_contains "${profile}" "profile_id: llvm-clang-hardened-portage"
  assert_file_contains "${profile}" "LDFLAGS=\"-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=lld\""
  assert_file_contains "${profile}" "CC=gcc"
  assert_file_contains "${profile}" "no-lto.conf"
  assert_file_contains "${profile}" 'CFLAGS="${COMMON_FLAGS}"'
  assert_file_contains "${profile}" "dev-vcs/git no-lto.conf"
  assert_file_contains "${profile}" "dev-libs/icu no-lto.conf"
  assert_file_contains "${profile}" "dev-libs/libnl no-lto.conf"
  assert_file_contains "${profile}" "dev-libs/nss no-lto.conf"
  assert_file_contains "${profile}" "dev-util/glslang no-lto.conf"
  assert_file_contains "${profile}" "dev-util/spirv-tools no-lto.conf"
  assert_file_contains "${profile}" "dev-util/spirv-llvm-translator no-lto.conf"
  assert_file_contains "${profile}" "media-libs/mesa no-lto.conf"
  assert_file_contains "${profile}" "sys-libs/binutils-libs no-lto.conf"
  assert_file_contains "${profile}" "net-misc/curl no-lto.conf"
  assert_file_contains "${profile}" "app-editors/vim-core no-lto.conf"
  assert_file_contains "${profile}" "x11-base/xorg-server no-lto.conf"
  assert_file_contains "${profile}" "net-fs/samba no-lto.conf"
  assert_file_contains "${profile}" "sys-libs/glibc gcc-compat.conf"
  assert_file_contains "${profile}" "llvm-core/clang-toolchain-symlinks native-symlinks -gcc-symlinks"
  assert_file_contains "${profile}" "sys-apps/systemd-utils acl kmod tmpfiles udev -boot -kernel-install -sysusers -ukify"
  assert_file_contains "${profile}" "21-minimal-systemd-utils"

  assert_file_contains "${metadata}" "validated_alias_mode_2026_04_25"
  assert_file_contains "${metadata}" "kernel_package_atom_override: =sys-kernel/gentoo-kernel-6.18.18"
  assert_file_contains "${metadata}" "zfs_package_atom: =sys-fs/zfs-2.3.6"
  assert_file_contains "${metadata}" "zfs_kmod_package_atom: =sys-fs/zfs-kmod-2.3.6"
}

test_profile_make_conf_fragments_are_portage_parse_safe() {
  local profile_dir="${ANSIBLE_ROOT}/profile-definitions"

  if grep -R '\${STAGE5_BINPKG_PKGDIR:-' "${profile_dir}"; then
    fail "profile make_conf_append fragments must not use shell-default PKGDIR expansion; Portage rejects it while parsing make.conf"
  fi
}

test_portage_override_paths_exist
test_qemu_alias_inventory_uses_source_kernel_path
test_boot_commandline_templates_do_not_regress_console_typo
test_profile_parent_template_is_resume_safe
test_llvm_clang_portage_profile_exists
test_profile_make_conf_fragments_are_portage_parse_safe

printf 'PASS: %s\n' "$(basename "$0")"
