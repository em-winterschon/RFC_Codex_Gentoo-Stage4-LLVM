#!/usr/bin/env bash
set -euo pipefail

if [[ "${QEMU_STAGE3_BUILD_TRACE:-0}" == '1' ]]; then
  set -x
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_NAME="${INSTANCE_NAME:-gentoo-stage4-testvm}"
STAGE3_TARGET="${STAGE3_TARGET:-amd64-llvm-openrc}"
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
SGDISK_BIN="${SGDISK_BIN:-/usr/bin/sgdisk}"
PARTPROBE_BIN="${PARTPROBE_BIN:-/usr/sbin/partprobe}"
PARTX_BIN="${PARTX_BIN:-/usr/bin/partx}"
MKFS_VFAT_BIN="${MKFS_VFAT_BIN:-/usr/sbin/mkfs.vfat}"
MKFS_EXT4_BIN="${MKFS_EXT4_BIN:-/usr/sbin/mkfs.ext4}"
NBD_DEVICE="${NBD_DEVICE:-/dev/nbd0}"
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
STAGE3_EXTRA_PACKAGES="${STAGE3_EXTRA_PACKAGES:-sys-fs/dosfstools}"
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
GPT_ESP_TYPE_GUID='c12a7328-f81f-11d2-ba4b-00a0c93ec93b'
GPT_LINUX_FS_TYPE_GUID='0fc63daf-8483-4772-8e79-3d69d8477de4'

resolve_host_tool_paths() {
  local tool_name resolved_path

  for tool_name in \
    QEMU_IMG_BIN \
    QEMU_NBD_BIN \
    MODPROBE_BIN \
    SGDISK_BIN \
    PARTPROBE_BIN \
    PARTX_BIN \
    MKFS_VFAT_BIN \
    MKFS_EXT4_BIN \
    MOUNT_BIN \
    UMOUNT_BIN \
    TAR_BIN \
    CHROOT_BIN; do
    resolved_path="${!tool_name}"
    if [[ -x "${resolved_path}" ]]; then
      continue
    fi

    resolved_path="$(command -v "$(basename "${resolved_path}")" 2>/dev/null || true)"
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

stage3_latest_info_url() {
  printf '%s/%s/autobuilds/%s/%s' \
    "${STAGE3_MIRROR_ROOT}" \
    "${STAGE3_RELEASE_ARCH}" \
    "${STAGE3_CURRENT_DIR}" \
    "${STAGE3_LATEST_TXT}"
}

find_fetch_tool() {
  if command -v curl >/dev/null 2>&1; then
    printf 'curl'
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
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

disconnect_nbd() {
  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  "${QEMU_NBD_BIN}" --disconnect "${NBD_DEVICE}" >/dev/null 2>&1 || true
}

cleanup_mounts() {
  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' ]]; then
    return 0
  fi

  "${UMOUNT_BIN}" -R "${TARGET_ROOT_MNT}" >/dev/null 2>&1 || true
}

cleanup() {
  cleanup_mounts
  disconnect_nbd
}

create_qcow_image() {
  log "Creating ${QCOW_IMAGE}"
  mkdir -p "$(dirname "${QCOW_IMAGE}")"
  run_cmd "${QEMU_IMG_BIN}" create -f qcow2 "${QCOW_IMAGE}" "${QCOW_SIZE_GIB}G"
}

attach_qcow_image() {
  run_cmd "${MODPROBE_BIN}" nbd max_part=8
  disconnect_nbd
  run_cmd "${QEMU_NBD_BIN}" --connect "${NBD_DEVICE}" "${QCOW_IMAGE}"
  run_cmd "${PARTPROBE_BIN}" "${NBD_DEVICE}"
}

partition_qcow_image() {
  run_cmd "${SGDISK_BIN}" --zap-all "${NBD_DEVICE}"
  run_cmd "${SGDISK_BIN}" --new=1:0:+"${QCOW_ESP_SIZE_MIB}"MiB --typecode=1:ef00 --change-name=1:gentooefi "${NBD_DEVICE}"
  run_cmd "${SGDISK_BIN}" --new=2:0:0 --typecode=2:8300 --change-name=2:gentooroot "${NBD_DEVICE}"
  run_cmd "${PARTPROBE_BIN}" "${NBD_DEVICE}"
  run_cmd "${PARTX_BIN}" -u "${NBD_DEVICE}"
}

format_qcow_image() {
  run_cmd "${MKFS_VFAT_BIN}" -F 32 -n gentooefi "$(nbd_partition)"
  run_cmd "${MKFS_EXT4_BIN}" -F -L gentooroot "$(nbd_root_partition)"
}

mount_qcow_image() {
  run_cmd "${MOUNT_BIN}" "$(nbd_root_partition)" "${TARGET_ROOT_MNT}"
  run_cmd "${MOUNT_BIN}" --mkdir "$(nbd_partition)" "${TARGET_EFI_MNT}"
}

extract_stage3() {
  run_cmd "${TAR_BIN}" xpf "${STAGE3_STAGE_TARBALL_PATH}" --xattrs-include='*.*' --numeric-owner -C "${TARGET_ROOT_MNT}"
  if [[ -f "${HOST_RESOLV_CONF}" ]]; then
    run_cmd cp "${HOST_RESOLV_CONF}" "${TARGET_ROOT_MNT}/etc/resolv.conf"
    run_cmd chmod 0644 "${TARGET_ROOT_MNT}/etc/resolv.conf"
  fi
}

render_bootstrap_script() {
  local ssh_key

  ssh_key="$(resolve_ssh_authorized_key)"
  mkdir -p "$(dirname "${WORK_BOOTSTRAP_SCRIPT}")"
  cat >"${WORK_BOOTSTRAP_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cat > /etc/fstab <<'FSTAB'
LABEL=gentooroot / ext4 defaults,noatime 0 1
LABEL=gentooefi /boot/efi vfat umask=0077 0 2
FSTAB

mkdir -p /boot/efi /root/.ssh /etc/portage
mkdir -p /etc/default
mkdir -p /etc/portage/package.use

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
MAKECONF

cat > /etc/portage/package.use/stage3-qcow-kernel <<'PKGUSE'
sys-kernel/installkernel dracut
PKGUSE

cat > /etc/cmdline <<CMDLINE
root=LABEL=gentooroot rootfstype=ext4 console=tty0 console=ttyS0,${VM_SERIAL_BAUD}
CMDLINE

printf '%s\n' 'hostname="${VM_HOSTNAME}"' > /etc/conf.d/hostname
printf '%s\n' '${VM_TIMEZONE}' > /etc/timezone
printf '%s\n' '${VM_KEYMAP}' > /etc/conf.d/keymaps
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
emerge --oneshot sys-apps/portage
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
  run_cmd "${MOUNT_BIN}" --bind /dev "${TARGET_ROOT_MNT}/dev"
  run_cmd "${MOUNT_BIN}" --bind /proc "${TARGET_ROOT_MNT}/proc"
  run_cmd "${MOUNT_BIN}" --bind /sys "${TARGET_ROOT_MNT}/sys"
  run_cmd "${CHROOT_BIN}" "${TARGET_ROOT_MNT}" /bin/bash /root/bootstrap-stage3-vm.sh
}

main() {
  trap cleanup EXIT
  resolve_host_tool_paths
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
  render_bootstrap_script
  install_bootstrap_script
  run_bootstrap
  log "Built stage3 QCOW image: ${QCOW_IMAGE}"
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
