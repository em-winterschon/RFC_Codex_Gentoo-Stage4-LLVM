#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_STAGE3_BUILD_TRACE:-0}" == '1' ]]; then
  set -x
fi

INSTANCE_NAME="${INSTANCE_NAME:-gentoo-stage4-testvm}"
STAGE3_TARGET="${STAGE3_TARGET:-amd64-llvm-openrc}"
STAGE3_PROFILE_PRESET="${STAGE3_PROFILE_PRESET:-base}"
STAGE3_MIRROR_ROOT="${STAGE3_MIRROR_ROOT:-https://distfiles.gentoo.org/releases}"
STAGE3_IMAGE_DIR="${STAGE3_IMAGE_DIR:-/opt/gentoo-virt-qemu/stage3}"
STAGE3_CACHE_DIR="${STAGE3_CACHE_DIR:-${STAGE3_IMAGE_DIR}/cache}"
STAGE3_IMAGE_OUTPUT_DIR="${STAGE3_IMAGE_OUTPUT_DIR:-${STAGE3_IMAGE_DIR}/images}"
STAGE3_BUILD_DIR="${STAGE3_BUILD_DIR:-${STAGE3_IMAGE_DIR}/build/${INSTANCE_NAME}}"
TARGET_ROOT_MNT="${TARGET_ROOT_MNT:-${STAGE3_BUILD_DIR}/rootfs}"
TARGET_EFI_MNT="${TARGET_EFI_MNT:-${TARGET_ROOT_MNT}/boot/efi}"
WORK_BOOTSTRAP_SCRIPT="${WORK_BOOTSTRAP_SCRIPT:-${STAGE3_BUILD_DIR}/bootstrap-stage3-vm.sh}"
QCOW_IMAGE="${QCOW_IMAGE:-${STAGE3_IMAGE_OUTPUT_DIR}/${INSTANCE_NAME}.qcow2}"
QCOW_SIZE_GIB="${QCOW_SIZE_GIB:-24}"
QCOW_ESP_SIZE_MIB="${QCOW_ESP_SIZE_MIB:-512}"
QEMU_IMG_BIN="${QEMU_IMG_BIN:-/usr/bin/qemu-img}"
QEMU_NBD_BIN="${QEMU_NBD_BIN:-/usr/bin/qemu-nbd}"
MODPROBE_BIN="${MODPROBE_BIN:-/sbin/modprobe}"
MKNOD_BIN="${MKNOD_BIN:-/usr/bin/mknod}"
SGDISK_BIN="${SGDISK_BIN:-/usr/bin/sgdisk}"
PARTPROBE_BIN="${PARTPROBE_BIN:-/usr/sbin/partprobe}"
PARTX_BIN="${PARTX_BIN:-/usr/bin/partx}"
MKFS_VFAT_BIN="${MKFS_VFAT_BIN:-/usr/sbin/mkfs.vfat}"
MKFS_EXT4_BIN="${MKFS_EXT4_BIN:-/usr/sbin/mkfs.ext4}"
NBD_DEVICE="${NBD_DEVICE:-/dev/nbd0}"
DEV_DIR="${DEV_DIR:-/dev}"
SYS_CLASS_BLOCK_DIR="${SYS_CLASS_BLOCK_DIR:-/sys/class/block}"
MOUNT_BIN="${MOUNT_BIN:-/usr/bin/mount}"
UMOUNT_BIN="${UMOUNT_BIN:-/usr/bin/umount}"
TAR_BIN="${TAR_BIN:-/usr/bin/tar}"
CHROOT_BIN="${CHROOT_BIN:-/usr/sbin/chroot}"
HOST_RESOLV_CONF="${HOST_RESOLV_CONF:-/etc/resolv.conf}"
PORTAGE_SYNC_COMMAND="${PORTAGE_SYNC_COMMAND:-emerge-webrsync}"
STAGE3_KERNEL_PACKAGE="${STAGE3_KERNEL_PACKAGE:-sys-kernel/gentoo-kernel-bin}"
STAGE3_BOOTLOADER_PACKAGE="${STAGE3_BOOTLOADER_PACKAGE:-sys-boot/grub}"
STAGE3_NETWORK_PACKAGE="${STAGE3_NETWORK_PACKAGE:-net-misc/dhcpcd}"
STAGE3_SSH_PACKAGE="${STAGE3_SSH_PACKAGE:-net-misc/openssh}"
STAGE3_NETWORK_SERVICE="${STAGE3_NETWORK_SERVICE:-dhcpcd}"
STAGE3_SSH_SERVICE="${STAGE3_SSH_SERVICE:-sshd}"
STAGE3_EXTRA_PACKAGES="${STAGE3_EXTRA_PACKAGES:-sys-fs/dosfstools sys-apps/gptfdisk sys-block/parted sys-fs/zfs sys-fs/zfs-kmod}"
STAGE3_MAKE_CONF_APPEND="${STAGE3_MAKE_CONF_APPEND-}"
STAGE3_PACKAGE_USE_APPEND="${STAGE3_PACKAGE_USE_APPEND-}"
STAGE3_PACKAGE_UNMASK_APPEND="${STAGE3_PACKAGE_UNMASK_APPEND-}"
STAGE3_HOST_DISTFILES_DIR="${STAGE3_HOST_DISTFILES_DIR-}"
STAGE3_HOST_BINPKG_DIR="${STAGE3_HOST_BINPKG_DIR-}"
STAGE3_GUEST_DISTFILES_DIR="${STAGE3_GUEST_DISTFILES_DIR:-/srv/build-cache/distfiles}"
STAGE3_GUEST_BINPKG_DIR="${STAGE3_GUEST_BINPKG_DIR:-/srv/build-cache/binpkgs}"
STAGE3_HOST_CACHE_ROOT="${STAGE3_HOST_CACHE_ROOT:-/srv/build-cache}"
STAGE3_HOST_CACHE_GROUP="${STAGE3_HOST_CACHE_GROUP:-portage}"
VM_HOSTNAME="${VM_HOSTNAME:-${INSTANCE_NAME}}"
VM_TIMEZONE="${VM_TIMEZONE:-UTC}"
VM_LOCALE="${VM_LOCALE:-en_US.UTF-8 UTF-8}"
VM_KEYMAP="${VM_KEYMAP:-us}"
VM_GRUB_TIMEOUT="${VM_GRUB_TIMEOUT:-1}"
VM_SERIAL_BAUD="${VM_SERIAL_BAUD:-115200}"
QEMU_STAGE3_BUILD_DRY_RUN="${QEMU_STAGE3_BUILD_DRY_RUN:-0}"
STAGE3_VERIFY_CHECKSUM="${STAGE3_VERIFY_CHECKSUM:-1}"
SSH_AUTHORIZED_KEY="${SSH_AUTHORIZED_KEY-}"
SSH_AUTHORIZED_KEY_FILE="${SSH_AUTHORIZED_KEY_FILE-}"
STAGE3_ROOT_PASSWORD_HASH="${STAGE3_ROOT_PASSWORD_HASH-}"
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
STAGE3_DEFAULT_HOST_TOOL_VARS='QEMU_IMG_BIN QEMU_NBD_BIN MODPROBE_BIN MKNOD_BIN SGDISK_BIN PARTPROBE_BIN PARTX_BIN MKFS_VFAT_BIN MKFS_EXT4_BIN MOUNT_BIN UMOUNT_BIN TAR_BIN CHROOT_BIN'
STAGE3_HOST_TOOL_VARS="${STAGE3_HOST_TOOL_VARS:-${STAGE3_DEFAULT_HOST_TOOL_VARS}}"
resolve_host_tool_paths() {
  local tool_name resolved_path

  for tool_name in ${STAGE3_HOST_TOOL_VARS}; do
    resolved_path="${!tool_name}"
    if [[ -x "${resolved_path}" ]]; then
      continue
    fi

    resolved_path="$(command -v "$(basename "${resolved_path}")" 2> /dev/null || true)"
    [[ -n "${resolved_path}" ]] || fail "Required host tool is not available: ${tool_name}"
    printf -v "${tool_name}" '%s' "${resolved_path}"
  done
}

log() {
  printf '[build-stage3-qcow] %s\n' "$*"
}

fail() {
  printf '[build-stage3-qcow] ERROR: %s\n' "$*" >&2
  exit 1
}

print_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

run_cmd() {
  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    print_cmd "$@"
    return 0
  fi

  "$@"
}

run_shell() {
  local shell_cmd="$1"

  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    printf '%s\n' "${shell_cmd}"
    return 0
  fi

  /bin/bash -c "${shell_cmd}"
}

supported_stage3_targets() {
  printf '%s\n' 'amd64-llvm-openrc arm64-llvm-openrc power9le-openrc'
}

supported_stage3_profile_presets() {
  printf '%s\n' 'base hardened-llvm-stage4'
}

validate_stage3_profile_preset() {
  case "${STAGE3_PROFILE_PRESET}" in
  base | hardened-llvm-stage4) ;;
  *)
    fail "Unsupported STAGE3_PROFILE_PRESET: ${STAGE3_PROFILE_PRESET} (supported: $(supported_stage3_profile_presets))"
    ;;
  esac
}

resolve_stage3_target() {
  case "${STAGE3_TARGET}" in
  amd64-llvm-openrc)
    STAGE3_RELEASE_ARCH='amd64'
    STAGE3_CURRENT_DIR='current-stage3-amd64-llvm-openrc'
    STAGE3_LATEST_TXT='latest-stage3-amd64-llvm-openrc.txt'
    STAGE3_GRUB_TARGET='x86_64-efi'
    STAGE3_HOST_ARCH='x86_64'
    STAGE3_LLVM_TARGETS='X86'
    ;;
  arm64-llvm-openrc)
    STAGE3_RELEASE_ARCH='arm64'
    STAGE3_CURRENT_DIR='current-stage3-arm64-llvm-openrc'
    STAGE3_LATEST_TXT='latest-stage3-arm64-llvm-openrc.txt'
    STAGE3_GRUB_TARGET='arm64-efi'
    STAGE3_HOST_ARCH='aarch64'
    STAGE3_LLVM_TARGETS='AArch64'
    ;;
  power9le-openrc)
    STAGE3_RELEASE_ARCH='ppc'
    STAGE3_CURRENT_DIR='current-stage3-power9le-openrc'
    STAGE3_LATEST_TXT='latest-stage3-power9le-openrc.txt'
    STAGE3_GRUB_TARGET='powerpc-ieee1275'
    STAGE3_HOST_ARCH='ppc64le'
    STAGE3_LLVM_TARGETS='PowerPC'
    ;;
  *)
    fail "Unsupported STAGE3_TARGET: ${STAGE3_TARGET} (supported: $(supported_stage3_targets))"
    ;;
  esac
}

stage3_profile_bootstrap_fragment() {
  case "${STAGE3_PROFILE_PRESET}" in
  base)
    return 0
    ;;
  hardened-llvm-stage4)
    cat << 'EOF'
cat >> /etc/portage/make.conf <<'MAKECONF_HARDENED'
COMMON_FLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3"
CFLAGS="${COMMON_FLAGS} -flto=thin"
CXXFLAGS="${COMMON_FLAGS} -flto=thin"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
LDFLAGS="-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=lld"
USE="${USE} -systemd"
FEATURES="${FEATURES} ccache distcc fail-clean"
QA_STRICT_EXECSTACK="set"
QA_STRICT_TEXTRELS="set"
QA_STRICT_FLAGS_IGNORED="set"
PORTAGE_TMPDIR="/var/tmp/portage-tmpfs"
PORTAGE_LOGDIR="/var/log/portage"
CCACHE_DIR="/var/cache/ccache"
CCACHE_SIZE="20G"
CCACHE_TEMPDIR="/var/tmp/portage-tmpfs/ccache-tmp"
CCACHE_PREFIX="distcc"
MAKECONF_HARDENED

cat > /etc/portage/package.use/00-llvm-stage4 <<'PKGUSE_LLVM'
llvm-core/clang-toolchain-symlinks native-symlinks -gcc-symlinks
llvm-core/lld-toolchain-symlinks native-symlinks
llvm-core/clang-linker-config default-lld
llvm-runtimes/clang-runtime compiler-rt default-compiler-rt default-lld sanitize
dev-util/ccache static-c++
sys-libs/glibc -clang
www-client/firefox clang
mail-client/thunderbird clang
dev-lang/spidermonkey clang
PKGUSE_LLVM

cat > /etc/portage/package.use/10-no-systemd <<'PKGUSE_NOSYSTEMD'
sys-auth/pambase elogind
net-misc/networkmanager elogind
sys-apps/accountsservice elogind
x11-base/xorg-server elogind
media-video/pipewire elogind
media-video/wireplumber elogind
sys-fs/udisks elogind
sys-process/procps elogind
PKGUSE_NOSYSTEMD

mkdir -p /etc/portage/package.mask
cat > /etc/portage/package.mask/00-no-systemd <<'PKGMASK_NOSYSTEMD'
sys-apps/systemd
PKGMASK_NOSYSTEMD

cat > /etc/portage/package.mask/20-gcc-required <<'PKGMASK_GCC'
# Add package atoms here only after LLVM/Clang and xira were attempted
# or were already known to be unsupported.
PKGMASK_GCC
EOF
    ;;
  esac
}

stage3_profile_repository_enable_list() {
  case "${STAGE3_PROFILE_PRESET}" in
  base) ;;
  hardened-llvm-stage4)
    printf '%s\n' guru xira without-systemd
    ;;
  esac
}

stage3_latest_info_url() {
  printf '%s/%s/autobuilds/%s/%s' \
    "${STAGE3_MIRROR_ROOT}" \
    "${STAGE3_RELEASE_ARCH}" \
    "${STAGE3_CURRENT_DIR}" \
    "${STAGE3_LATEST_TXT}"
}

find_fetch_tool() {
  if command -v curl > /dev/null 2>&1; then
    printf 'curl'
    return 0
  fi

  if command -v wget > /dev/null 2>&1; then
    printf 'wget'
    return 0
  fi

  fail 'Neither curl nor wget is available'
}

fetch_text() {
  local url="$1"

  case "$(find_fetch_tool)" in
  curl)
    curl -fsSL "${url}"
    ;;
  wget)
    wget -qO- "${url}"
    ;;
  esac
}

download_file() {
  local url="$1"
  local dest="$2"

  case "$(find_fetch_tool)" in
  curl)
    curl -fL -o "${dest}" "${url}"
    ;;
  wget)
    wget -O "${dest}" "${url}"
    ;;
  esac
}

ensure_dirs() {
  mkdir -p "${STAGE3_CACHE_DIR}" "${STAGE3_IMAGE_OUTPUT_DIR}" "${STAGE3_BUILD_DIR}" "${TARGET_ROOT_MNT}" "${TARGET_EFI_MNT}"
}

prepare_host_cache_permissions() {
  local host_path="$1"
  local cache_root_parent

  [[ -n "${host_path}" ]] || return 0
  mkdir -p "${host_path}"

  if getent group "${STAGE3_HOST_CACHE_GROUP}" > /dev/null 2>&1; then
    chgrp "${STAGE3_HOST_CACHE_GROUP}" "${host_path}" || true
    chmod 2775 "${host_path}" || true

    case "${host_path}" in
    "${STAGE3_HOST_CACHE_ROOT}"|"${STAGE3_HOST_CACHE_ROOT}"/*)
      cache_root_parent="$(dirname "${STAGE3_HOST_CACHE_ROOT}")"
      chmod a+x "${cache_root_parent}" || true
      mkdir -p "${STAGE3_HOST_CACHE_ROOT}"
      chgrp "${STAGE3_HOST_CACHE_GROUP}" "${STAGE3_HOST_CACHE_ROOT}" || true
      chmod 2775 "${STAGE3_HOST_CACHE_ROOT}" || true
      ;;
    esac
  else
    chmod 0755 "${host_path}" || true
  fi
}

prepare_guest_cache_mountpoint() {
  local guest_path="$1"
  local target_path="${TARGET_ROOT_MNT}${guest_path}"
  local relative_path="${guest_path#/}"
  local current_path="${TARGET_ROOT_MNT}"
  local path_parts=()
  local index

  mkdir -p "${target_path}"

  IFS='/' read -r -a path_parts <<< "${relative_path}"
  for ((index = 0; index < ${#path_parts[@]} - 1; index++)); do
    [[ -n "${path_parts[index]}" ]] || continue
    current_path="${current_path}/${path_parts[index]}"
    chmod a+x "${current_path}" || true
  done
}

resolve_stage3_artifacts() {
  local info_text

  info_text="$(fetch_text "$(stage3_latest_info_url)")"
  STAGE3_STAGE_TARBALL_NAME="$(printf '%s\n' "${info_text}" | grep -Eo 'stage3-[^[:space:]]+\.tar\.xz' | head -n1 || true)"
  [[ -n "${STAGE3_STAGE_TARBALL_NAME}" ]] || fail "Unable to parse stage3 tarball name from $(stage3_latest_info_url)"

  STAGE3_STAGE_TARBALL_URL="${STAGE3_MIRROR_ROOT}/${STAGE3_RELEASE_ARCH}/autobuilds/${STAGE3_CURRENT_DIR}/${STAGE3_STAGE_TARBALL_NAME}"
  STAGE3_STAGE_SHA256_URL="${STAGE3_STAGE_TARBALL_URL}.sha256"
  STAGE3_STAGE_TARBALL_PATH="${STAGE3_CACHE_DIR}/${STAGE3_STAGE_TARBALL_NAME}"
  STAGE3_STAGE_SHA256_PATH="${STAGE3_STAGE_TARBALL_PATH}.sha256"
}

ensure_stage3_downloads() {
  if [[ ! -f "${STAGE3_STAGE_TARBALL_PATH}" ]]; then
    log "Downloading ${STAGE3_STAGE_TARBALL_URL}"
    if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
      log "[DRY RUN] would download to ${STAGE3_STAGE_TARBALL_PATH}"
    else
      download_file "${STAGE3_STAGE_TARBALL_URL}" "${STAGE3_STAGE_TARBALL_PATH}"
    fi
  fi

  if [[ "${STAGE3_VERIFY_CHECKSUM}" != '1' ]]; then
    return 0
  fi

  if [[ ! -f "${STAGE3_STAGE_SHA256_PATH}" ]]; then
    log "Downloading ${STAGE3_STAGE_SHA256_URL}"
    if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
      log "[DRY RUN] would download to ${STAGE3_STAGE_SHA256_PATH}"
      return 0
    fi

    download_file "${STAGE3_STAGE_SHA256_URL}" "${STAGE3_STAGE_SHA256_PATH}"
  fi

  STAGE3_STAGE_SHA256="$(grep -Eo '[A-Fa-f0-9]{64}' "${STAGE3_STAGE_SHA256_PATH}" | head -n1 || true)"
  [[ -n "${STAGE3_STAGE_SHA256}" ]] || fail "Unable to parse checksum from ${STAGE3_STAGE_SHA256_PATH}"

  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  printf '%s  %s\n' "${STAGE3_STAGE_SHA256}" "${STAGE3_STAGE_TARBALL_PATH}" | sha256sum -c -
}

resolve_ssh_authorized_key() {
  local candidate

  if [[ -n "${SSH_AUTHORIZED_KEY}" ]]; then
    printf '%s' "${SSH_AUTHORIZED_KEY}"
    return 0
  fi

  if [[ -n "${SSH_AUTHORIZED_KEY_FILE}" ]]; then
    [[ -f "${SSH_AUTHORIZED_KEY_FILE}" ]] || fail "SSH_AUTHORIZED_KEY_FILE does not exist: ${SSH_AUTHORIZED_KEY_FILE}"
    sed -n '1p' "${SSH_AUTHORIZED_KEY_FILE}"
    return 0
  fi

  for candidate in "${HOME:-/root}/.ssh/id_ed25519.pub" "${HOME:-/root}/.ssh/id_rsa.pub"; do
    if [[ -f "${candidate}" ]]; then
      sed -n '1p' "${candidate}"
      return 0
    fi
  done

  fail 'No SSH authorized key available; set SSH_AUTHORIZED_KEY or SSH_AUTHORIZED_KEY_FILE'
}

validate_host_arch() {
  local host_arch

  host_arch="$(uname -m)"
  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  [[ "${host_arch}" == "${STAGE3_HOST_ARCH}" ]] || fail "STAGE3_TARGET=${STAGE3_TARGET} requires a ${STAGE3_HOST_ARCH} build host for non-dry-run bootstrap; current host is ${host_arch}"
}

nbd_partition() {
  printf '%sp1' "${NBD_DEVICE}"
}

nbd_root_partition() {
  printf '%sp2' "${NBD_DEVICE}"
}

ensure_block_device_node() {
  local block_name="$1"
  local dev_file="${SYS_CLASS_BLOCK_DIR}/${block_name}/dev"
  local device_path="${DEV_DIR}/${block_name}"
  local major_minor major minor

  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  [[ -r "${dev_file}" ]] || fail "Kernel block device is missing sysfs metadata: ${dev_file}"
  major_minor="$(< "${dev_file}")"
  major="${major_minor%%:*}"
  minor="${major_minor##*:}"
  [[ "${major}" =~ ^[0-9]+$ && "${minor}" =~ ^[0-9]+$ ]] || fail "Invalid major:minor in ${dev_file}: ${major_minor}"

  if [[ ! -b "${device_path}" ]]; then
    run_cmd "${MKNOD_BIN}" "${device_path}" b "${major}" "${minor}"
  fi
  run_cmd chmod 0660 "${device_path}"
}

ensure_nbd_device_nodes() {
  local nbd_name sys_path

  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  nbd_name="$(basename "${NBD_DEVICE}")"
  ensure_block_device_node "${nbd_name}"
  for sys_path in "${SYS_CLASS_BLOCK_DIR}/${nbd_name}"p*; do
    [[ -e "${sys_path}" ]] || continue
    ensure_block_device_node "$(basename "${sys_path}")"
  done
}

disconnect_nbd() {
  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  "${QEMU_NBD_BIN}" --disconnect "${NBD_DEVICE}" > /dev/null 2>&1 || true
}

cleanup_mounts() {
  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  "${UMOUNT_BIN}" -R "${TARGET_ROOT_MNT}" > /dev/null 2>&1 || true
}

cleanup() {
  cleanup_mounts
  disconnect_nbd
}

handle_signal() {
  local signal_name="$1"

  log "Received ${signal_name}; cleaning up"
  cleanup
  trap - EXIT
  exit 128
}

create_qcow_image() {
  log "Creating ${QCOW_IMAGE}"
  mkdir -p "$(dirname "${QCOW_IMAGE}")"
  run_cmd "${QEMU_IMG_BIN}" create -f qcow2 "${QCOW_IMAGE}" "${QCOW_SIZE_GIB}G"
}

attach_qcow_image() {
  log "Attaching ${QCOW_IMAGE} to ${NBD_DEVICE}"
  run_cmd "${MODPROBE_BIN}" nbd max_part=8
  ensure_nbd_device_nodes
  disconnect_nbd
  run_cmd "${QEMU_NBD_BIN}" --connect "${NBD_DEVICE}" "${QCOW_IMAGE}"
  run_cmd "${PARTPROBE_BIN}" "${NBD_DEVICE}"
}

partition_qcow_image() {
  log "Partitioning ${NBD_DEVICE}"
  run_cmd "${SGDISK_BIN}" --zap-all "${NBD_DEVICE}"
  run_cmd "${SGDISK_BIN}" --new=1:0:+"${QCOW_ESP_SIZE_MIB}"MiB --typecode=1:ef00 --change-name=1:gentooefi "${NBD_DEVICE}"
  run_cmd "${SGDISK_BIN}" --new=2:0:0 --typecode=2:8300 --change-name=2:gentooroot "${NBD_DEVICE}"
  run_cmd "${PARTPROBE_BIN}" "${NBD_DEVICE}"
  run_cmd "${PARTX_BIN}" -u "${NBD_DEVICE}"
  ensure_nbd_device_nodes
}

format_qcow_image() {
  log "Formatting QCOW partitions"
  run_cmd "${MKFS_VFAT_BIN}" -F 32 -n gentooefi "$(nbd_partition)"
  run_cmd "${MKFS_EXT4_BIN}" -F -L gentooroot "$(nbd_root_partition)"
}

mount_qcow_image() {
  log "Mounting QCOW root at ${TARGET_ROOT_MNT}"
  run_cmd "${MOUNT_BIN}" "$(nbd_root_partition)" "${TARGET_ROOT_MNT}"
  run_cmd "${MOUNT_BIN}" --mkdir "$(nbd_partition)" "${TARGET_EFI_MNT}"
}

mount_host_cache_dir() {
  local host_path="$1"
  local guest_path="$2"
  local target_path="${TARGET_ROOT_MNT}${guest_path}"

  [[ -n "${host_path}" ]] || return 0

  log "Bind-mounting host cache ${host_path} at ${guest_path}"
  prepare_host_cache_permissions "${host_path}"
  prepare_guest_cache_mountpoint "${guest_path}"
  run_cmd "${MOUNT_BIN}" --bind "${host_path}" "${target_path}"
}

mount_host_cache_dirs() {
  mount_host_cache_dir "${STAGE3_HOST_DISTFILES_DIR}" "${STAGE3_GUEST_DISTFILES_DIR}"
  mount_host_cache_dir "${STAGE3_HOST_BINPKG_DIR}" "${STAGE3_GUEST_BINPKG_DIR}"
}

extract_stage3() {
  log "Extracting ${STAGE3_STAGE_TARBALL_NAME}"
  run_cmd "${TAR_BIN}" xpf "${STAGE3_STAGE_TARBALL_PATH}" --xattrs-include='*.*' --numeric-owner -C "${TARGET_ROOT_MNT}"
  if [[ -f "${HOST_RESOLV_CONF}" ]]; then
    run_cmd cp "${HOST_RESOLV_CONF}" "${TARGET_ROOT_MNT}/etc/resolv.conf"
    run_cmd chmod 0644 "${TARGET_ROOT_MNT}/etc/resolv.conf"
  fi
}

render_bootstrap_script() {
  local ssh_key
  local stage3_profile_fragment
  local stage3_profile_repositories

  ssh_key="$(resolve_ssh_authorized_key)"
  stage3_profile_fragment="$(stage3_profile_bootstrap_fragment)"
  stage3_profile_repositories="$(stage3_profile_repository_enable_list | tr '\n' ' ')"
  mkdir -p "$(dirname "${WORK_BOOTSTRAP_SCRIPT}")"
  cat > "${WORK_BOOTSTRAP_SCRIPT}" << EOF
#!/usr/bin/env bash
set -euo pipefail

cat > /etc/fstab <<'FSTAB'
LABEL=gentooroot / ext4 defaults,noatime 0 1
LABEL=gentooefi /boot/efi vfat umask=0077 0 2
FSTAB

mkdir -p /boot/efi /root/.ssh /etc/portage
mkdir -p /etc/default
mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.mask
mkdir -p /etc/portage/package.unmask
mkdir -p /etc/portage/repos.conf
mkdir -p /var/db/repos/gentoo

if [[ -f /etc/resolv.conf ]]; then
  chmod 0644 /etc/resolv.conf || true
fi

cat >> /etc/portage/make.conf <<'MAKECONF'
CC="clang"
CXX="clang++"
LD="ld.lld"
LLVM_TARGETS="${STAGE3_LLVM_TARGETS}"
COMMON_FLAGS="-O2 -pipe"
COMMON_CFLAGS="\${COMMON_FLAGS}"
COMMON_CXXFLAGS="\${COMMON_FLAGS}"
ACCEPT_LICENSE="*"
MAKECONF

if [[ -n ${STAGE3_MAKE_CONF_APPEND@Q} ]]; then
  cat >> /etc/portage/make.conf <<'MAKECONF_EXTRA'
${STAGE3_MAKE_CONF_APPEND}
MAKECONF_EXTRA
fi

cat > /etc/portage/package.use/stage3-qcow-kernel <<'PKGUSE'
sys-kernel/installkernel dracut
PKGUSE

if [[ -n ${STAGE3_PACKAGE_USE_APPEND@Q} ]]; then
  cat > /etc/portage/package.use/stage3-extra <<'PKGUSE_EXTRA'
${STAGE3_PACKAGE_USE_APPEND}
PKGUSE_EXTRA
fi

if [[ -n ${STAGE3_PACKAGE_UNMASK_APPEND@Q} ]]; then
  cat > /etc/portage/package.unmask/stage3-extra <<'PKGUNMASK_EXTRA'
${STAGE3_PACKAGE_UNMASK_APPEND}
PKGUNMASK_EXTRA
fi

mkdir -p /dev/shm/portage-tmpfs /var/tmp/portage /var/tmp/portage-tmpfs /var/cache/binpkgs /var/log/portage
chmod 1777 /dev/shm/portage-tmpfs /var/tmp /var/tmp/portage /var/tmp/portage-tmpfs

cat > /etc/portage/repos.conf/gentoo.conf <<'REPOSCONF'
[DEFAULT]
main-repo = gentoo

[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
webrsync-gpg = yes
REPOSCONF

${stage3_profile_fragment}

cat > /etc/cmdline <<CMDLINE
root=LABEL=gentooroot rootfstype=ext4 console=tty0 console=ttyS0,${VM_SERIAL_BAUD}
CMDLINE

printf '%s\n' 'hostname="${VM_HOSTNAME}"' > /etc/conf.d/hostname
printf '%s\n' '${VM_TIMEZONE}' > /etc/timezone
printf '%s\n' 'keymap="${VM_KEYMAP}"' > /etc/conf.d/keymaps
printf '%s\n' '${VM_LOCALE}' > /etc/locale.gen

cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 ${VM_HOSTNAME}
HOSTS

grep -q 'ttyS0' /etc/inittab || printf 's0:12345:respawn:/sbin/agetty ${VM_SERIAL_BAUD} ttyS0 vt100\n' >> /etc/inittab

printf '%s\n' '${ssh_key}' > /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

if [[ -n ${STAGE3_ROOT_PASSWORD_HASH@Q} ]]; then
  usermod -p ${STAGE3_ROOT_PASSWORD_HASH@Q} root
else
  passwd -l root >/dev/null 2>&1 || true
fi

${PORTAGE_SYNC_COMMAND}
emerge --oneshot sys-apps/portage app-eselect/eselect-repository
for gentoo_overlay_repo in ${stage3_profile_repositories}; do
  eselect repository enable "\${gentoo_overlay_repo}"
  emaint sync -r "\${gentoo_overlay_repo}"
done
emerge ${STAGE3_KERNEL_PACKAGE} ${STAGE3_BOOTLOADER_PACKAGE} ${STAGE3_NETWORK_PACKAGE} ${STAGE3_SSH_PACKAGE} ${STAGE3_EXTRA_PACKAGES}

rc-update add ${STAGE3_NETWORK_SERVICE} default
rc-update add ${STAGE3_SSH_SERVICE} default

cat > /etc/default/grub <<'GRUB'
GRUB_TIMEOUT=${VM_GRUB_TIMEOUT}
GRUB_CMDLINE_LINUX="console=ttyS0,${VM_SERIAL_BAUD}"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=${VM_SERIAL_BAUD} --unit=0 --word=8 --parity=no --stop=1"
GRUB

grub-install --target=${STAGE3_GRUB_TARGET} --efi-directory=/boot/efi --bootloader-id=Gentoo --removable --recheck
grub-mkconfig -o /boot/grub/grub.cfg
EOF
  chmod 0755 "${WORK_BOOTSTRAP_SCRIPT}"
}

install_bootstrap_script() {
  run_cmd install -D -m 0755 "${WORK_BOOTSTRAP_SCRIPT}" "${TARGET_ROOT_MNT}/root/bootstrap-stage3-vm.sh"
}

run_bootstrap() {
  log "Mounting chroot pseudo-filesystems"
  mkdir -p "${TARGET_ROOT_MNT}/dev"
  run_cmd "${MOUNT_BIN}" -t tmpfs tmpfs -o mode=755,nosuid "${TARGET_ROOT_MNT}/dev"
  mkdir -p "${TARGET_ROOT_MNT}/dev/pts" "${TARGET_ROOT_MNT}/dev/shm"
  run_cmd "${MOUNT_BIN}" -t devpts devpts -o gid=5,mode=620,ptmxmode=666 "${TARGET_ROOT_MNT}/dev/pts"
  run_cmd "${MOUNT_BIN}" -t tmpfs tmpfs -o mode=1777,nosuid,nodev "${TARGET_ROOT_MNT}/dev/shm"
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/null" c 1 3
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/zero" c 1 5
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/full" c 1 7
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/random" c 1 8
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/urandom" c 1 9
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/tty" c 5 0
  mknod -m 600 "${TARGET_ROOT_MNT}/dev/console" c 5 1
  ln -sfn pts/ptmx "${TARGET_ROOT_MNT}/dev/ptmx"
  ln -sfn /proc/self/fd "${TARGET_ROOT_MNT}/dev/fd"
  ln -sfn fd/0 "${TARGET_ROOT_MNT}/dev/stdin"
  ln -sfn fd/1 "${TARGET_ROOT_MNT}/dev/stdout"
  ln -sfn fd/2 "${TARGET_ROOT_MNT}/dev/stderr"
  run_cmd "${MOUNT_BIN}" --bind /proc "${TARGET_ROOT_MNT}/proc"
  run_cmd "${MOUNT_BIN}" --bind /sys "${TARGET_ROOT_MNT}/sys"
  log "Running stage3 bootstrap inside chroot"
  run_cmd "${CHROOT_BIN}" "${TARGET_ROOT_MNT}" /bin/bash /root/bootstrap-stage3-vm.sh
}

main() {
  trap cleanup EXIT
  trap 'handle_signal HUP' HUP
  trap 'handle_signal INT' INT
  trap 'handle_signal TERM' TERM
  resolve_host_tool_paths
  validate_stage3_profile_preset
  resolve_stage3_target
  validate_host_arch
  ensure_dirs
  resolve_stage3_artifacts
  ensure_stage3_downloads
  create_qcow_image
  attach_qcow_image
  partition_qcow_image
  format_qcow_image
  mount_qcow_image
  extract_stage3
  mount_host_cache_dirs
  render_bootstrap_script
  install_bootstrap_script
  run_bootstrap
  log "Built stage3 QCOW image: ${QCOW_IMAGE}"
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
