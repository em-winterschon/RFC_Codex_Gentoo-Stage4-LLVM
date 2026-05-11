#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/build-stage3-qcow.sh"

# shellcheck disable=SC1091
# shellcheck source=../../gentoo-virt-qemu/build-stage3-qcow.sh
source "${BUILD_SCRIPT}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected to find '${needle}' in '${haystack}'"
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  [[ "${actual}" == "${expected}" ]] || fail "expected '${expected}', got '${actual}'"
}

mark_stage3_builder_globals_used() {
  : "${STAGE3_MIRROR_ROOT-}" \
    "${STAGE3_TARGET-}" \
    "${STAGE3_PROFILE_PRESET-}" \
    "${STAGE3_CACHE_DIR-}" \
    "${TARGET_EFI_MNT-}" \
    "${QCOW_IMAGE-}" \
    "${QEMU_STAGE3_BUILD_DRY_RUN-}" \
    "${STAGE3_VERIFY_CHECKSUM-}" \
    "${SSH_AUTHORIZED_KEY-}" \
    "${SSH_AUTHORIZED_KEY_FILE-}" \
    "${STAGE3_ROOT_PASSWORD_HASH-}" \
    "${PORTAGE_SYNC_COMMAND-}" \
    "${STAGE3_MAKE_CONF_APPEND-}" \
    "${STAGE3_PACKAGE_USE_APPEND-}" \
    "${STAGE3_PACKAGE_UNMASK_APPEND-}" \
    "${STAGE3_HOST_DISTFILES_DIR-}" \
    "${STAGE3_HOST_BINPKG_DIR-}" \
    "${STAGE3_GUEST_DISTFILES_DIR-}" \
    "${STAGE3_GUEST_BINPKG_DIR-}" \
    "${STAGE3_HOST_CACHE_ROOT-}" \
    "${STAGE3_HOST_CACHE_GROUP-}" \
    "${STAGE3_LATEST_TXT-}" \
    "${STAGE3_LLVM_TARGETS-}" \
    "${STAGE3_STAGE_TARBALL_NAME-}" \
    "${STAGE3_STAGE_TARBALL_URL-}" \
    "${STAGE3_STAGE_SHA256_URL-}" \
    "${STAGE3_STAGE_TARBALL_PATH-}" \
    "${STAGE3_STAGE_SHA256_PATH-}" \
    "${STAGE3_STAGE_SHA256-}" \
    "${QEMU_NBD_BIN-}" \
    "${MODPROBE_BIN-}" \
    "${MKNOD_BIN-}" \
    "${SGDISK_BIN-}" \
    "${PARTPROBE_BIN-}" \
    "${PARTX_BIN-}" \
    "${MKFS_VFAT_BIN-}" \
    "${MKFS_EXT4_BIN-}" \
    "${UMOUNT_BIN-}" \
    "${TAR_BIN-}"
}

make_fake_host_tools() {
  local temp_dir="$1"
  local tool_dir="${temp_dir}/fake-tools"
  local tool
  mkdir -p "${tool_dir}"

  for tool in \
    qemu-img \
    qemu-nbd \
    modprobe \
    mknod \
    sgdisk \
    partprobe \
    partx \
    mkfs.vfat \
    mkfs.ext4 \
    mount \
    umount \
    tar \
    chroot; do
    cat > "${tool_dir}/${tool}" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${tool_dir}/${tool}"
  done

  printf '%s\n' "${tool_dir}"
}

reset_builder_state() {
  INSTANCE_NAME='gentoo-stage4-testvm'
  STAGE3_TARGET='amd64-llvm-openrc'
  STAGE3_PROFILE_PRESET='base'
  STAGE3_MIRROR_ROOT='https://distfiles.gentoo.org/releases'
  STAGE3_IMAGE_DIR='/tmp/stage3'
  STAGE3_CACHE_DIR="${STAGE3_IMAGE_DIR}/cache"
  STAGE3_IMAGE_OUTPUT_DIR="${STAGE3_IMAGE_DIR}/images"
  STAGE3_BUILD_DIR="${STAGE3_IMAGE_DIR}/build/${INSTANCE_NAME}"
  TARGET_ROOT_MNT="${STAGE3_BUILD_DIR}/rootfs"
  TARGET_EFI_MNT="${TARGET_ROOT_MNT}/boot/efi"
  WORK_BOOTSTRAP_SCRIPT="${STAGE3_BUILD_DIR}/bootstrap-stage3-vm.sh"
  QCOW_IMAGE="${STAGE3_IMAGE_OUTPUT_DIR}/${INSTANCE_NAME}.qcow2"
  QEMU_STAGE3_BUILD_DRY_RUN='1'
  STAGE3_VERIFY_CHECKSUM='1'
  SSH_AUTHORIZED_KEY='ssh-ed25519 AAAATestKey codex@test'
  SSH_AUTHORIZED_KEY_FILE=''
  STAGE3_ROOT_PASSWORD_HASH=''
  PORTAGE_SYNC_COMMAND='emerge-webrsync'
  STAGE3_MAKE_CONF_APPEND=''
  STAGE3_PACKAGE_USE_APPEND=''
  STAGE3_PACKAGE_UNMASK_APPEND=''
  STAGE3_HOST_DISTFILES_DIR=''
  STAGE3_HOST_BINPKG_DIR=''
  STAGE3_GUEST_DISTFILES_DIR='/srv/build-cache/distfiles'
  STAGE3_GUEST_BINPKG_DIR='/srv/build-cache/binpkgs'
  STAGE3_HOST_CACHE_ROOT='/srv/build-cache'
  STAGE3_HOST_CACHE_GROUP='portage'
  STAGE3_RELEASE_ARCH=''
  STAGE3_CURRENT_DIR=''
  STAGE3_LATEST_TXT=''
  STAGE3_GRUB_TARGET=''
  STAGE3_HOST_ARCH=''
  STAGE3_LLVM_TARGETS=''
  STAGE3_STAGE_TARBALL_NAME=''
  STAGE3_STAGE_TARBALL_URL=''
  STAGE3_STAGE_SHA256_URL=''
  STAGE3_STAGE_TARBALL_PATH=''
  STAGE3_STAGE_SHA256_PATH=''
  STAGE3_STAGE_SHA256=''
  QEMU_IMG_BIN='/usr/bin/qemu-img'
  QEMU_NBD_BIN='/usr/bin/qemu-nbd'
  MODPROBE_BIN='/sbin/modprobe'
  MKNOD_BIN='/usr/bin/mknod'
  SGDISK_BIN='/usr/bin/sgdisk'
  PARTPROBE_BIN='/usr/sbin/partprobe'
  PARTX_BIN='/usr/bin/partx'
  MKFS_VFAT_BIN='/usr/sbin/mkfs.vfat'
  MKFS_EXT4_BIN='/usr/sbin/mkfs.ext4'
  MOUNT_BIN='/usr/bin/mount'
  UMOUNT_BIN='/usr/bin/umount'
  TAR_BIN='/usr/bin/tar'
  CHROOT_BIN='/usr/sbin/chroot'
  NBD_DEVICE='/dev/nbd0'
  DEV_DIR='/dev'
  SYS_CLASS_BLOCK_DIR='/sys/class/block'
  mark_stage3_builder_globals_used
}

test_resolve_stage3_target_maps_supported_enums() {
  reset_builder_state
  STAGE3_TARGET='amd64-llvm-openrc'
  resolve_stage3_target
  assert_equals "${STAGE3_CURRENT_DIR}" 'current-stage3-amd64-llvm-openrc'
  assert_equals "${STAGE3_GRUB_TARGET}" 'x86_64-efi'

  reset_builder_state
  STAGE3_TARGET='arm64-llvm-openrc'
  resolve_stage3_target
  assert_equals "${STAGE3_CURRENT_DIR}" 'current-stage3-arm64-llvm-openrc'
  assert_equals "${STAGE3_HOST_ARCH}" 'aarch64'

  reset_builder_state
  STAGE3_TARGET='power9le-openrc'
  resolve_stage3_target
  assert_equals "${STAGE3_CURRENT_DIR}" 'current-stage3-power9le-openrc'
  assert_equals "${STAGE3_RELEASE_ARCH}" 'ppc'
}

test_resolve_stage3_target_rejects_invalid_enum() {
  local output status

  reset_builder_state
  STAGE3_TARGET='amd64-openrc-cloudbanana'

  set +e
  output="$(resolve_stage3_target 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '1'
  assert_contains "${output}" 'Unsupported STAGE3_TARGET'
}

test_validate_stage3_profile_preset_rejects_invalid_enum() {
  local output status

  reset_builder_state
  STAGE3_PROFILE_PRESET='definitely-not-real'

  set +e
  output="$(validate_stage3_profile_preset 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '1'
  assert_contains "${output}" 'Unsupported STAGE3_PROFILE_PRESET'
}

test_main_dry_run_prints_stage3_build_plan() {
  local temp_dir tool_dir old_path output status bootstrap
  temp_dir="$(mktemp -d)"
  tool_dir="$(make_fake_host_tools "${temp_dir}")"
  old_path="${PATH}"
  PATH="${tool_dir}:${PATH}"

  reset_builder_state
  STAGE3_IMAGE_DIR="${temp_dir}"
  STAGE3_CACHE_DIR="${STAGE3_IMAGE_DIR}/cache"
  STAGE3_IMAGE_OUTPUT_DIR="${STAGE3_IMAGE_DIR}/images"
  STAGE3_BUILD_DIR="${STAGE3_IMAGE_DIR}/build/${INSTANCE_NAME}"
  TARGET_ROOT_MNT="${STAGE3_BUILD_DIR}/rootfs"
  TARGET_EFI_MNT="${TARGET_ROOT_MNT}/boot/efi"
  WORK_BOOTSTRAP_SCRIPT="${STAGE3_BUILD_DIR}/bootstrap-stage3-vm.sh"
  QCOW_IMAGE="${STAGE3_IMAGE_OUTPUT_DIR}/${INSTANCE_NAME}.qcow2"
  HOST_RESOLV_CONF="${temp_dir}/resolv.conf"
  printf 'nameserver 1.1.1.1\n' > "${HOST_RESOLV_CONF}"

  fetch_text() {
    cat << 'EOF'
stage3-amd64-llvm-openrc-20260420T120000Z.tar.xz 12345
EOF
  }
  fetch_text > /dev/null

  set +e
  output="$(main 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '0'
  assert_contains "${output}" 'current-stage3-amd64-llvm-openrc'
  assert_contains "${output}" 'qemu-img create -f qcow2'
  assert_contains "${output}" 'qemu-nbd --connect'
  assert_contains "${output}" 'modprobe nbd max_part=8'
  assert_contains "${output}" 'sgdisk --zap-all /dev/nbd0'
  assert_contains "${output}" 'sgdisk --new=1:0:+512MiB --typecode=1:ef00'
  assert_contains "${output}" 'partx -u /dev/nbd0'
  assert_contains "${output}" 'ptmxmode=666'
  assert_contains "${output}" 'mode=1777'
  assert_contains "${output}" 'chmod 0644'
  assert_contains "${output}" '[COMPLETE]'
  bootstrap="$(cat "${WORK_BOOTSTRAP_SCRIPT}")"
  assert_contains "${bootstrap}" 'grub-install --target=x86_64-efi'
  assert_contains "${bootstrap}" 'CC="clang"'
  assert_contains "${bootstrap}" 'chmod 0644 /etc/resolv.conf'
  assert_contains "${bootstrap}" 'sys-kernel/installkernel dracut'
  assert_contains "${bootstrap}" 'sys-fs/dosfstools sys-apps/gptfdisk sys-block/parted sys-fs/zfs sys-fs/zfs-kmod'
  assert_contains "${bootstrap}" 'root=LABEL=gentooroot rootfstype=ext4 console=tty0 console=ttyS0,115200'
  assert_contains "${bootstrap}" 'keymap="us"'
  assert_contains "${bootstrap}" 'emerge --oneshot sys-apps/portage app-eselect/eselect-repository'
  assert_contains "${bootstrap}" 'rc-update add dhcpcd default'
  assert_contains "${bootstrap}" 'rc-update add sshd default'
  PATH="${old_path}"
  rm -rf "${temp_dir}"
}

test_hardened_profile_preset_renders_profile_specific_portage_config() {
  local temp_dir tool_dir old_path bootstrap output status
  temp_dir="$(mktemp -d)"
  tool_dir="$(make_fake_host_tools "${temp_dir}")"
  old_path="${PATH}"
  PATH="${tool_dir}:${PATH}"

  reset_builder_state
  STAGE3_PROFILE_PRESET='hardened-llvm-stage4'
  STAGE3_IMAGE_DIR="${temp_dir}"
  STAGE3_CACHE_DIR="${STAGE3_IMAGE_DIR}/cache"
  STAGE3_IMAGE_OUTPUT_DIR="${STAGE3_IMAGE_DIR}/images"
  STAGE3_BUILD_DIR="${STAGE3_IMAGE_DIR}/build/${INSTANCE_NAME}"
  TARGET_ROOT_MNT="${STAGE3_BUILD_DIR}/rootfs"
  TARGET_EFI_MNT="${TARGET_ROOT_MNT}/boot/efi"
  WORK_BOOTSTRAP_SCRIPT="${STAGE3_BUILD_DIR}/bootstrap-stage3-vm.sh"
  QCOW_IMAGE="${STAGE3_IMAGE_OUTPUT_DIR}/${INSTANCE_NAME}.qcow2"

  fetch_text() {
    cat << 'EOF'
stage3-amd64-llvm-openrc-20260420T120000Z.tar.xz 12345
EOF
  }
  fetch_text > /dev/null

  set +e
  output="$(main 2>&1)"
  status=$?
  set -e

  assert_equals "${status}" '0'
  bootstrap="$(cat "${WORK_BOOTSTRAP_SCRIPT}")"
  # shellcheck disable=SC2016
  assert_contains "${bootstrap}" 'FEATURES="${FEATURES} ccache distcc fail-clean"'
  assert_contains "${bootstrap}" 'cat > /etc/portage/package.use/00-llvm-stage4'
  assert_contains "${bootstrap}" 'cat > /etc/portage/package.mask/00-no-systemd'
  # shellcheck disable=SC2016
  assert_contains "${bootstrap}" 'eselect repository enable "${gentoo_overlay_repo}"'
  assert_contains "${bootstrap}" 'guru xira without-systemd'
  PATH="${old_path}"
  rm -rf "${temp_dir}"
}

test_ensure_nbd_device_nodes_creates_missing_dev_nodes_from_sysfs() {
  local temp_dir mknod_log
  temp_dir="$(mktemp -d)"
  mknod_log="${temp_dir}/mknod.log"

  mkdir -p "${temp_dir}/dev" "${temp_dir}/sys/class/block/nbd0" "${temp_dir}/sys/class/block/nbd0p1" "${temp_dir}/sys/class/block/nbd0p2"
  printf '%s\n' '43:0' > "${temp_dir}/sys/class/block/nbd0/dev"
  printf '%s\n' '43:1' > "${temp_dir}/sys/class/block/nbd0p1/dev"
  printf '%s\n' '43:2' > "${temp_dir}/sys/class/block/nbd0p2/dev"
  cat > "${temp_dir}/mknod" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MKNOD_LOG}"
: > "$1"
EOF
  chmod +x "${temp_dir}/mknod"

  reset_builder_state
  QEMU_STAGE3_BUILD_DRY_RUN='0'
  NBD_DEVICE="${temp_dir}/dev/nbd0"
  DEV_DIR="${temp_dir}/dev"
  SYS_CLASS_BLOCK_DIR="${temp_dir}/sys/class/block"
  MKNOD_BIN="${temp_dir}/mknod"
  export MKNOD_LOG="${mknod_log}"

  ensure_nbd_device_nodes

  assert_contains "$(cat "${mknod_log}")" "${temp_dir}/dev/nbd0 b 43 0"
  assert_contains "$(cat "${mknod_log}")" "${temp_dir}/dev/nbd0p1 b 43 1"
  assert_contains "$(cat "${mknod_log}")" "${temp_dir}/dev/nbd0p2 b 43 2"
  rm -rf "${temp_dir}"
}

test_mount_host_cache_dirs_renders_bind_mounts() {
  local temp_dir output
  temp_dir="$(mktemp -d)"

  reset_builder_state
  TARGET_ROOT_MNT="${temp_dir}/rootfs"
  STAGE3_HOST_DISTFILES_DIR="${temp_dir}/host-distfiles"
  STAGE3_HOST_BINPKG_DIR="${temp_dir}/host-binpkgs"
  STAGE3_GUEST_DISTFILES_DIR='/srv/build-cache/distfiles'
  STAGE3_GUEST_BINPKG_DIR='/srv/build-cache/binpkgs'

  output="$(mount_host_cache_dirs 2>&1)"

  assert_contains "${output}" "mount --bind ${STAGE3_HOST_DISTFILES_DIR} ${TARGET_ROOT_MNT}${STAGE3_GUEST_DISTFILES_DIR}"
  assert_contains "${output}" "mount --bind ${STAGE3_HOST_BINPKG_DIR} ${TARGET_ROOT_MNT}${STAGE3_GUEST_BINPKG_DIR}"
  rm -rf "${temp_dir}"
}

test_prepare_host_cache_permissions_marks_cache_root_portage_writable() {
  local temp_dir cache_root cache_dir
  temp_dir="$(mktemp -d)"

  reset_builder_state
  cache_root="${temp_dir}/build-cache"
  cache_dir="${cache_root}/distfiles"
  STAGE3_HOST_CACHE_ROOT="${cache_root}"
  STAGE3_HOST_CACHE_GROUP='portage'

  prepare_host_cache_permissions "${cache_dir}"

  [[ -d "${cache_dir}" ]] || fail "cache dir was not created"
  [[ -x "${cache_root}" ]] || fail "cache root is not traversable"
  [[ -w "${cache_dir}" ]] || fail "cache dir is not writable"
  rm -rf "${temp_dir}"
}

test_render_bootstrap_script_includes_extra_portage_fragments() {
  local temp_dir bootstrap
  temp_dir="$(mktemp -d)"

  reset_builder_state
  STAGE3_LLVM_TARGETS='X86'
  STAGE3_MAKE_CONF_APPEND=$'MAKEOPTS="-j48 -l64"\nUSE="${USE} X dbus spice -systemd"\nVIDEO_CARDS="${VIDEO_CARDS} qxl modesetting"'
  STAGE3_PACKAGE_USE_APPEND=$'app-emulation/spice-vdagent gtk -systemd\nx11-base/xorg-server xorg elogind udev -systemd'
  STAGE3_PACKAGE_UNMASK_APPEND=$'>=dev-python/pyqt5-5.15.11'
  WORK_BOOTSTRAP_SCRIPT="${temp_dir}/bootstrap-stage3-vm.sh"

  render_bootstrap_script

  bootstrap="$(cat "${WORK_BOOTSTRAP_SCRIPT}")"
  assert_contains "${bootstrap}" 'MAKEOPTS="-j48 -l64"'
  assert_contains "${bootstrap}" 'USE="${USE} X dbus spice -systemd"'
  assert_contains "${bootstrap}" 'VIDEO_CARDS="${VIDEO_CARDS} qxl modesetting"'
  assert_contains "${bootstrap}" 'mkdir -p /dev/shm/portage-tmpfs /var/tmp/portage /var/tmp/portage-tmpfs /var/cache/binpkgs /var/log/portage'
  assert_contains "${bootstrap}" 'chmod 1777 /dev/shm/portage-tmpfs /var/tmp /var/tmp/portage /var/tmp/portage-tmpfs'
  assert_contains "${bootstrap}" 'cat > /etc/portage/package.use/stage3-extra'
  assert_contains "${bootstrap}" 'app-emulation/spice-vdagent gtk -systemd'
  assert_contains "${bootstrap}" 'x11-base/xorg-server xorg elogind udev -systemd'
  assert_contains "${bootstrap}" 'cat > /etc/portage/package.unmask/stage3-extra'
  assert_contains "${bootstrap}" '>=dev-python/pyqt5-5.15.11'
  rm -rf "${temp_dir}"
}

test_resolve_host_tool_paths_falls_back_to_command_v() {
  local temp_dir tool_dir old_path
  temp_dir="$(mktemp -d)"
  tool_dir="$(make_fake_host_tools "${temp_dir}")"
  old_path="${PATH}"
  PATH="${tool_dir}:${PATH}"

  reset_builder_state
  QEMU_IMG_BIN='/not-real/qemu-img'
  QEMU_NBD_BIN='/not-real/qemu-nbd'
  MODPROBE_BIN='/not-real/modprobe'
  MKNOD_BIN='/not-real/mknod'
  SGDISK_BIN='/not-real/sgdisk'
  PARTPROBE_BIN='/not-real/partprobe'
  PARTX_BIN='/not-real/partx'
  MKFS_VFAT_BIN='/not-real/mkfs.vfat'
  MKFS_EXT4_BIN='/not-real/mkfs.ext4'
  MOUNT_BIN='/not-real/mount'
  UMOUNT_BIN='/not-real/umount'
  TAR_BIN='/not-real/tar'
  CHROOT_BIN='/not-real/chroot'

  resolve_host_tool_paths

  [[ "${QEMU_IMG_BIN}" == */qemu-img ]] || fail "QEMU_IMG_BIN was not resolved"
  [[ "${MKNOD_BIN}" == */mknod ]] || fail "MKNOD_BIN was not resolved"
  [[ "${MOUNT_BIN}" == */mount ]] || fail "MOUNT_BIN was not resolved"
  [[ "${CHROOT_BIN}" == */chroot ]] || fail "CHROOT_BIN was not resolved"
  PATH="${old_path}"
  rm -rf "${temp_dir}"
}

test_resolve_stage3_target_maps_supported_enums
test_resolve_stage3_target_rejects_invalid_enum
test_validate_stage3_profile_preset_rejects_invalid_enum
test_main_dry_run_prints_stage3_build_plan
test_hardened_profile_preset_renders_profile_specific_portage_config
test_ensure_nbd_device_nodes_creates_missing_dev_nodes_from_sysfs
test_mount_host_cache_dirs_renders_bind_mounts
test_prepare_host_cache_permissions_marks_cache_root_portage_writable
test_render_bootstrap_script_includes_extra_portage_fragments
test_resolve_host_tool_paths_falls_back_to_command_v

printf 'PASS: %s\n' "$(basename "$0")"
