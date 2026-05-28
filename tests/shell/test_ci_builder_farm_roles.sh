#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -q -- "${pattern}" "${file}"
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2
  ! grep -q -- "${pattern}" "${file}"
}

assert_first_before() {
  local file=$1
  local first=$2
  local second=$3
  local first_line
  local second_line

  first_line=$(grep -n -- "${first}" "${file}" | head -n1 | cut -d: -f1)
  second_line=$(grep -n -- "${second}" "${file}" | head -n1 | cut -d: -f1)
  test -n "${first_line}"
  test -n "${second_line}"
  test "${first_line}" -lt "${second_line}"
}

for role_dir in \
  jenkins_controller \
  distcc_farm \
  kernel_config; do
  test -d "${ANSIBLE_ROOT}/roles/${role_dir}"
  test -f "${ANSIBLE_ROOT}/roles/${role_dir}/tasks/main.yml"
done

for profile in \
  vm-jenkins-controller.yml \
  metal-builder-farm-node.yml \
  hardware-intel-qat-c3000.yml; do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${profile}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${profile}" '^gentoo_profile_definition:'
done

for metadata in \
  vm-jenkins-controller.metadata.yml \
  metal-builder-farm-node.metadata.yml; do
  test -f "${ANSIBLE_ROOT}/profile-definitions/${metadata}"
  assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/${metadata}" '^gentoo_system_profile_metadata:'
done

for package_list in \
  stage5-virtual-host-jenkins-controller.packages \
  stage5-metal-host-builder-farm-node.packages; do
  test -f "${ANSIBLE_ROOT}/profile-package-lists/${package_list}"
done

assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'jenkins_controller'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'distcc_farm'
assert_first_before "${ANSIBLE_ROOT}/playbooks/install.yml" 'distcc_farm' 'system_packages'
assert_first_before "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'distcc_farm' 'system_packages'
assert_first_before "${ANSIBLE_ROOT}/playbooks/install.yml" 'kernel_config' 'system_packages'
assert_first_before "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'kernel_config' 'system_packages'
assert_file_contains "${ANSIBLE_ROOT}/roles/kernel_config/tasks/main.yml" '/etc/kernel/config.d'
assert_file_contains "${ANSIBLE_ROOT}/roles/kernel_config/tasks/main.yml" 'resolved_kernel_config_fragment_files'
assert_file_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" 'Verify distcc client policy before system package build'
assert_file_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" 'system_packages_distcc_farm.makeopts_jobs'
test -f "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2"
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/tasks/main.yml" 'Render distcc client compiler wrappers'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/tasks/main.yml" 'Render distcc worker compiler whitelist entries'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/make.conf.distcc.j2" 'DISTCC_FALLBACK="0"'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/make.conf.distcc.j2" 'PATH="/usr/local/libexec/distcc-farm/bin:${PATH}"'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/make.conf.distcc.j2" 'FEATURES="${FEATURES} distcc"'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/make.conf.distcc.j2" 'makeopts_load'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/hosts.j2" '{% if not loop.last %} {% endif %}'
assert_file_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" 'portageq envvar FEATURES'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/tasks/main.yml" 'x86_64-pc-linux-gnu-gcc'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/tasks/main.yml" 'x86_64-pc-linux-gnu-clang-21'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'DISTCC_CLIENT_RUNTIME_DIR'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'run_native_probe=true'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'has_compile_action'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'has_preprocess_only_action'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'real_compiler="$(command -v -- "${compiler_name}")"'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'CMakeFiles/CMakeScratch/TryCompile'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'meson-private/tmp'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" '.conf_check_'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'config-temp'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'config_.*/config_.*\.c'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'zfs-.*/build/.*\.c'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'config_.*\.c'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'PWD:-'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'zfs-.*/build'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'lib/test_fortify'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'test.c|test.cc|test.cpp'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" '"/usr/lib/distcc/bin"'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'filtered_path:-/usr/local/sbin:/usr/local/bin:/usr/bin:/opt/bin'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'has_dependency_flag'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'has_dependency_file_flag'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/templates/distcc-client-wrapper.sh.j2" 'distcc_args=("-MF" "${output_file%.*}.d"'
assert_file_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" 'stage4-system-packages-emerge.log'
assert_file_not_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" 'emerge --verbose --oneshot'
assert_file_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" 'sanitized tail follows'
assert_file_contains "${ANSIBLE_ROOT}/roles/system_packages/tasks/main.yml" 'tr -cd'
assert_file_contains "${ANSIBLE_ROOT}/roles/portage/tasks/main.yml" '95-universal-netboot-microcode.conf'
assert_file_contains "${ANSIBLE_ROOT}/roles/portage/tasks/main.yml" 'hostonly="no"'
assert_file_contains "${ANSIBLE_ROOT}/roles/portage/tasks/main.yml" 'early_microcode="yes"'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/defaults/main.yml" "reject('match', '^root=')"
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" 'dracut --force --no-hostonly --early-microcode'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" 'org.zfsbootmenu:commandline={{ zfsbootmenu_root_commandline_effective }}'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" 'Mirror ZFSBootMenu EFI files to additional ESPs'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" 'esp_partitions[1:]'
assert_file_contains "${ANSIBLE_ROOT}/roles/boot/tasks/main.yml" 'rsync -a --delete'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'Write OpenRC hostname fallback'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'dest: "{{ install_target_root }}/etc/conf.d/hostname"'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'hostname="{{ install_hostname }}"'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'Write hosts file'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" '127.0.1.1'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'fqdn | default'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'Ensure installkernel command line directory exists'
assert_file_contains "${ANSIBLE_ROOT}/roles/chroot_base/tasks/main.yml" 'dest: "{{ install_target_root }}/etc/kernel/cmdline"'
assert_file_contains "${ANSIBLE_ROOT}/roles/platform_profile/tasks/main.yml" 'Check profile OpenRC service init scripts'
assert_file_contains "${ANSIBLE_ROOT}/roles/platform_profile/tasks/main.yml" '/etc/init.d/{{ openrc_service_name }}'
assert_file_contains "${ANSIBLE_ROOT}/roles/platform_profile/tasks/main.yml" 'selectattr('"'"'stat.exists'"'"')'
assert_file_contains "${ANSIBLE_ROOT}/roles/platform_profile/tasks/main.yml" 'Deferring profile OpenRC service enable'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/hardware-intel-qat-c3000.yml" 'qat_c3xxx'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/hardware-intel-qat-c3000.yml" 'CONFIG_CRYPTO_DEV_QAT_C3XXX=m'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/hardware-intel-qat-c3000.yml" 'dev-libs/openssl asm'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" 'profile-definitions/hardware-intel-qat-c3000.yml'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" 'qat-accelerated-crypto'
assert_file_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-base-minimal-nox.packages" '^net-misc/dhcp$'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/base-minimal-nox.yml" 'net-misc/dhcp client -server'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'net-misc/dhcp client -server'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" '^  cpp_mode: false$'
assert_file_contains "${ANSIBLE_ROOT}/roles/distcc_farm/defaults/main.yml" '^distcc_farm_default_cpp_mode: false$'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" '^portage_emerge_jobs: 2$'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" '^portage_load_average: 12$'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" '^  makeopts_jobs: 16$'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" '^  makeopts_load: 12$'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" '10.200.99.23'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" 'needs durable Podman/OCI persistence'
assert_file_contains "${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml" 'gentoo:default/linux/amd64/23.0/no-multilib/hardened'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" '-distcc -network-sandbox'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'dev-lang/go distcc-cgo-probe-fallback.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'DISTCC_FALLBACK="1"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'app-crypt/age go-toolchain-native-cc.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'dev-build/cmake configure-native-cc.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'net-dns/bind bind-clang21-warnings.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'Wno-error=parentheses-equality'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'net-mail/mailutils mailutils-clang-format-security.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'Wno-error=format-security'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'sys-block/ndctl ndctl-lld-undefined-version.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'Wl,--undefined-version'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'sys-cluster/slurm slurm-bfd-no-thinlto.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'CFLAGS="${COMMON_FLAGS}"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'CXXFLAGS="${COMMON_FLAGS}"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'sys-kernel/gentoo-kernel gentoo-kernel-clang21-hosttools.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'CFLAGS="${COMMON_FLAGS} -Wno-error=misleading-indentation -Wno-error=unused-value -Wno-error=parentheses-equality"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'CXXFLAGS="${COMMON_FLAGS} -Wno-error=misleading-indentation -Wno-error=unused-value -Wno-error=parentheses-equality"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'BUILD_CFLAGS="${CFLAGS}"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'BUILD_CXXFLAGS="${CXXFLAGS}"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'KCFLAGS="${KCFLAGS} -Wno-error=unused-command-line-argument"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'KCPPFLAGS="${KCPPFLAGS} -Wno-error=unused-command-line-argument"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'sys-fs/zfs-kmod zfs-kmod-distcc-kbuild.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'KERNEL_CC="x86_64-pc-linux-gnu-clang-21"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'MODULES_EXTRA_EMAKE="${MODULES_EXTRA_EMAKE} V=0 KBUILD_VERBOSE=0"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'sys-kernel/gentoo-kernel/gentoo-kernel-6.18-clang21-subcmd-astrcatf.patch'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'a/tools/lib/subcmd/subcmd-util.h'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'sys-kernel/gentoo-kernel/gentoo-kernel-6.18-clang21-special-build-flags.patch'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'a/arch/x86/realmode/rm/Makefile'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'a/drivers/firmware/efi/libstub/Makefile'
assert_file_not_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'app-emulation/libguestfs perl-cbuilder-clang-ld.conf'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'app-emulation/libguestfs/libguestfs-1.56.2-perl-module-build-ld-driver.patch'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" '@@ -56 +56 @@ all-local: Build'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" '@@ -59 +59 @@ clean-local: Build'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" '@@ -62 +62 @@ Build: Build.PL'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'LD=clang ./Build'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'LD=clang $(PERL) Build.PL --config ld=clang --prefix "@prefix@"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/llvm-clang-hardened-portage.yml" 'CPP="clang -E"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/hardened-llvm-stage4.yml" 'CPP="clang -E"'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/base-hypervisor-qemu-libvirt.yml" 'sys-cluster/rdma-core -python'
assert_file_contains "${ANSIBLE_ROOT}/profile-definitions/slurm-worker-node.yml" 'sys-cluster/rdma-core -python'
assert_file_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-base-hypervisor-common.packages" '^sys-firmware/intel-microcode$'
assert_file_contains "${ANSIBLE_ROOT}/profile-package-lists/stage5-base-hypervisor-common.packages" '^sys-kernel/linux-firmware$'
test -f "${ANSIBLE_ROOT}/roles/identity/defaults/main.yml"
assert_file_contains "${ANSIBLE_ROOT}/roles/identity/defaults/main.yml" '^install_root_authorized_keys_seed_enabled: true$'
assert_file_contains "${ANSIBLE_ROOT}/roles/identity/defaults/main.yml" '^install_root_authorized_keys_source_file: /root/.ssh/authorized_keys$'
assert_file_contains "${ANSIBLE_ROOT}/roles/identity/tasks/main.yml" 'Validate controller root authorized_keys source'
assert_file_contains "${ANSIBLE_ROOT}/roles/identity/tasks/main.yml" 'Seed target root authorized_keys from controller source'
assert_file_contains "${ANSIBLE_ROOT}/roles/identity/tasks/main.yml" 'dest: "{{ install_target_root }}/root/.ssh/authorized_keys"'
assert_file_contains "${ANSIBLE_ROOT}/roles/identity/tasks/main.yml" "mode: '0600'"
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'ci_controllers:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/hosts.yml" 'builder_farm_nodes:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/host_vars/vm-jenkins-controller.yml" '^profile_definition_files:'
assert_file_contains "${ANSIBLE_ROOT}/inventories/examples/group_vars/builder_farm_nodes.yml" '^profile_definition_files:'

printf 'PASS: %s\n' "$(basename "$0")"
