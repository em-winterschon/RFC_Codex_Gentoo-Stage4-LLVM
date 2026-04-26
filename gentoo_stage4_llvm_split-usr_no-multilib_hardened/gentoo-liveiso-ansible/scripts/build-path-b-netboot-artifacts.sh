#!/usr/bin/env bash
set -euo pipefail

if [[ "${PATHB_TRACE:-0}" == '1' ]]; then
  set -x
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
HELPER_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/build-stage3-qcow.sh"

[[ -f "${HELPER_SCRIPT}" ]] || {
  printf '[build-path-b-netboot-artifacts] ERROR: helper script not found: %s\n' "${HELPER_SCRIPT}" >&2
  exit 1
}

PATHB_BUILD_DRY_RUN="${PATHB_BUILD_DRY_RUN:-0}"
export QEMU_STAGE3_BUILD_DRY_RUN="${QEMU_STAGE3_BUILD_DRY_RUN:-${PATHB_BUILD_DRY_RUN}}"
export STAGE3_TARGET="${STAGE3_TARGET:-amd64-llvm-openrc}"
export STAGE3_PROFILE_PRESET="${STAGE3_PROFILE_PRESET:-base}"

# shellcheck source=/dev/null
source "${HELPER_SCRIPT}"

PATHB_INSTANCE_NAME="${PATHB_INSTANCE_NAME:-gentoo-pathb-provisioner}"
PATHB_ROOT="${PATHB_ROOT:-/opt/gentoo-netboot/path-b}"
PATHB_CACHE_DIR="${PATHB_CACHE_DIR:-${PATHB_ROOT}/cache}"
PATHB_BUILD_DIR="${PATHB_BUILD_DIR:-${PATHB_ROOT}/build/${PATHB_INSTANCE_NAME}}"
PATHB_ARTIFACT_ROOT="${PATHB_ARTIFACT_ROOT:-${PATHB_ROOT}/artifacts}"
PATHB_INSTALLER_ARTIFACT_DIR="${PATHB_INSTALLER_ARTIFACT_DIR:-${PATHB_ARTIFACT_ROOT}/gentoo-installer}"
PATHB_RESCUE_ARTIFACT_DIR="${PATHB_RESCUE_ARTIFACT_DIR:-${PATHB_ARTIFACT_ROOT}/gentoo-rescue}"
PATHB_TARGET_ROOT_MNT="${PATHB_TARGET_ROOT_MNT:-${PATHB_BUILD_DIR}/rootfs}"
PATHB_WORK_BOOTSTRAP_SCRIPT="${PATHB_WORK_BOOTSTRAP_SCRIPT:-${PATHB_BUILD_DIR}/bootstrap-path-b.sh}"
TARGET_ROOT_MNT="${PATHB_TARGET_ROOT_MNT}"
WORK_BOOTSTRAP_SCRIPT="${PATHB_WORK_BOOTSTRAP_SCRIPT}"
PORTAGE_SYNC_COMMAND="${PATHB_PORTAGE_SYNC_COMMAND:-emerge --sync}"
PATHB_KERNEL_PACKAGE="${PATHB_KERNEL_PACKAGE:-sys-kernel/gentoo-kernel}"
PATHB_NETWORK_PACKAGE="${PATHB_NETWORK_PACKAGE:-net-misc/dhcpcd}"
PATHB_DRACUT_DHCP_PACKAGE="${PATHB_DRACUT_DHCP_PACKAGE:-net-misc/dhcp}"
PATHB_DRACUT_DM_PACKAGE="${PATHB_DRACUT_DM_PACKAGE:-sys-fs/lvm2}"
PATHB_SSH_PACKAGE="${PATHB_SSH_PACKAGE:-net-misc/openssh}"
PATHB_NETWORK_SERVICE="${PATHB_NETWORK_SERVICE:-dhcpcd}"
PATHB_REUSE_INITRAMFS_NETWORK="${PATHB_REUSE_INITRAMFS_NETWORK:-1}"
PATHB_SSH_SERVICE="${PATHB_SSH_SERVICE:-sshd}"
PATHB_EXTRA_PACKAGES="${PATHB_EXTRA_PACKAGES:-app-admin/sudo dev-lang/python sys-apps/iproute2 sys-fs/zfs sys-fs/zfs-kmod sys-fs/dosfstools sys-block/parted sys-apps/pciutils sys-apps/usbutils sys-apps/kmod}"
PATHB_HOSTNAME="${PATHB_HOSTNAME:-gentoo-pathb}"
PATHB_TIMEZONE="${PATHB_TIMEZONE:-UTC}"
PATHB_LOCALE="${PATHB_LOCALE:-en_US.UTF-8 UTF-8}"
PATHB_KEYMAP="${PATHB_KEYMAP:-us}"
PATHB_SERIAL_BAUD="${PATHB_SERIAL_BAUD:-115200}"
PATHB_ROOT_PASSWORD_HASH="${PATHB_ROOT_PASSWORD_HASH:-}"
MKSQUASHFS_BIN="${MKSQUASHFS_BIN:-/usr/bin/mksquashfs}"
PATHB_SQUASHFS_COMPRESSOR="${PATHB_SQUASHFS_COMPRESSOR:-zstd}"
PATHB_DEBUG_LOCAL_START="${PATHB_DEBUG_LOCAL_START:-0}"

ensure_pathb_dirs() {
  mkdir -p \
    "${PATHB_CACHE_DIR}" \
    "${PATHB_BUILD_DIR}" \
    "${PATHB_INSTALLER_ARTIFACT_DIR}" \
    "${PATHB_RESCUE_ARTIFACT_DIR}"
}

reset_rootfs() {
  rm -rf "${TARGET_ROOT_MNT}"
  mkdir -p "${TARGET_ROOT_MNT}"
}

render_pathb_bootstrap_script() {
  local ssh_key
  local stage3_profile_fragment
  local stage3_profile_repositories

  ssh_key="$(resolve_ssh_authorized_key)"
  stage3_profile_fragment="$(stage3_profile_bootstrap_fragment)"
  stage3_profile_repositories="$(stage3_profile_repository_enable_list | tr '\n' ' ')"

  mkdir -p "$(dirname "${WORK_BOOTSTRAP_SCRIPT}")"
  cat > "${WORK_BOOTSTRAP_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  /root/.ssh \
  /etc/default \
  /etc/portage/package.use \
  /etc/portage/package.mask \
  /etc/dracut.conf.d \
  /etc/portage/repos.conf \
  /etc/local.d \
  /var/db/repos/gentoo

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

cat > /etc/portage/package.use/path-b-dracut <<'PKGUSE'
sys-kernel/installkernel dracut -systemd
PKGUSE

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

cat > /etc/cmdline <<'CMDLINE'
ip=dhcp rd.neednet=1 ro console=tty0 console=ttyS0,${PATHB_SERIAL_BAUD}
CMDLINE

ln -sf /usr/share/zoneinfo/${PATHB_TIMEZONE} /etc/localtime
printf '%s\n' '${PATHB_TIMEZONE}' > /etc/timezone
printf 'hostname="%s"\n' '${PATHB_HOSTNAME}' > /etc/conf.d/hostname
printf 'keymap="%s"\n' '${PATHB_KEYMAP}' > /etc/conf.d/keymaps
printf '%s\n' '${PATHB_LOCALE}' > /etc/locale.gen

cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 ${PATHB_HOSTNAME}
HOSTS

if ! awk '/^[[:space:]]*[^#].*ttyS0/ {found=1} END { exit(found ? 0 : 1) }' /etc/inittab; then
  printf 's0:12345:respawn:/sbin/agetty -L ${PATHB_SERIAL_BAUD} ttyS0 vt100\n' >> /etc/inittab
fi

touch /etc/securetty
grep -Eq '^[[:space:]]*ttyS0([[:space:]]+.*)?$' /etc/securetty || printf 'ttyS0\n' >> /etc/securetty

printf '%s\n' '${ssh_key}' > /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

if [[ -n ${PATHB_ROOT_PASSWORD_HASH@Q} ]]; then
  usermod -p ${PATHB_ROOT_PASSWORD_HASH@Q} root
else
  passwd -l root >/dev/null 2>&1 || true
fi

${PORTAGE_SYNC_COMMAND}
emerge --oneshot sys-apps/portage app-eselect/eselect-repository
for gentoo_overlay_repo in ${stage3_profile_repositories}; do
  eselect repository enable "\${gentoo_overlay_repo}"
  emaint sync -r "\${gentoo_overlay_repo}"
done

emerge \
  ${PATHB_KERNEL_PACKAGE} \
  ${PATHB_NETWORK_PACKAGE} \
  ${PATHB_DRACUT_DHCP_PACKAGE} \
  ${PATHB_DRACUT_DM_PACKAGE} \
  ${PATHB_SSH_PACKAGE} \
  dracut \
  ${PATHB_EXTRA_PACKAGES}

ssh-keygen -A

if [[ "${PATHB_REUSE_INITRAMFS_NETWORK}" == '1' ]]; then
cat > /etc/local.d/pathb-network-handoff.start <<'LOCALNET'
#!/usr/bin/env bash
set +e

boot_iface="$(ip route show default 2>/dev/null | awk 'NR==1 { print $5 }')"

if [[ -n "${boot_iface}" ]]; then
  mapfile -t boot_ipv4_addrs < <(ip -o -4 addr show dev "${boot_iface}" scope global 2>/dev/null | awk '{ print $4 }')

  if (( ${#boot_ipv4_addrs[@]} > 1 )); then
    for stale_addr in "${boot_ipv4_addrs[@]:1}"; do
      ip addr del "${stale_addr}" dev "${boot_iface}" >/dev/null 2>&1 || true
    done
  fi

  mapfile -t boot_default_routes < <(ip route show default dev "${boot_iface}" 2>/dev/null)
  if (( ${#boot_default_routes[@]} > 1 )); then
    for stale_route in "${boot_default_routes[@]:1}"; do
      ip route del ${stale_route} >/dev/null 2>&1 || true
    done
  fi
fi

pkill dhcpcd >/dev/null 2>&1 || true
LOCALNET
chmod 0755 /etc/local.d/pathb-network-handoff.start
fi

if [[ "${PATHB_DEBUG_LOCAL_START}" == '1' ]]; then
cat > /etc/local.d/pathb-debug.start <<'LOCALDEBUG'
#!/usr/bin/env bash
set +e
exec >/dev/ttyS0 2>&1
echo
echo "[path-b-debug] local.d reached"
date
hostname
ip -brief addr || true
rc-status default || true
ss -ltnp || true
rc-service sshd status || true
rc-service sshd start || true
rc-service dhcpcd status || true
ss -ltnp || true
echo "[path-b-debug] local.d complete"
LOCALDEBUG
chmod 0755 /etc/local.d/pathb-debug.start
fi

if [[ "${PATHB_REUSE_INITRAMFS_NETWORK}" != '1' ]]; then
  rc-update add ${PATHB_NETWORK_SERVICE} default
fi
rc-update add ${PATHB_SSH_SERVICE} default

cat > /etc/dracut.conf.d/path-b-live.conf <<'DRACUT'
hostonly="no"
use_fstab="no"
add_dracutmodules+=" dmsquash-live livenet network url-lib "
filesystems+=" squashfs overlay ext4 vfat "
compress="zstd"
DRACUT

kernel_version="\$(ls -1 /lib/modules | sort -V | tail -n1)"
dracut --force --no-hostonly \
  --add "dmsquash-live livenet network url-lib" \
  --filesystems "squashfs overlay ext4 vfat" \
  "/boot/initramfs-\${kernel_version}.img" "\${kernel_version}"
EOF
  chmod 0755 "${WORK_BOOTSTRAP_SCRIPT}"
}

install_pathb_bootstrap_script() {
  install -D -m 0755 "${WORK_BOOTSTRAP_SCRIPT}" "${TARGET_ROOT_MNT}/root/bootstrap-path-b.sh"
}

run_pathb_bootstrap() {
  mkdir -p "${TARGET_ROOT_MNT}/dev" "${TARGET_ROOT_MNT}/dev/pts" "${TARGET_ROOT_MNT}/dev/shm"
  run_cmd "${MOUNT_BIN}" -t devtmpfs devtmpfs "${TARGET_ROOT_MNT}/dev"
  run_cmd "${MOUNT_BIN}" -t devpts devpts "${TARGET_ROOT_MNT}/dev/pts"
  run_cmd "${MOUNT_BIN}" -t tmpfs tmpfs "${TARGET_ROOT_MNT}/dev/shm"
  rm -f "${TARGET_ROOT_MNT}/dev/null" "${TARGET_ROOT_MNT}/dev/zero" "${TARGET_ROOT_MNT}/dev/random" "${TARGET_ROOT_MNT}/dev/urandom" "${TARGET_ROOT_MNT}/dev/tty"
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/null" c 1 3
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/zero" c 1 5
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/random" c 1 8
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/urandom" c 1 9
  mknod -m 666 "${TARGET_ROOT_MNT}/dev/tty" c 5 0
  ln -sfn /proc/self/fd "${TARGET_ROOT_MNT}/dev/fd"
  ln -sfn fd/0 "${TARGET_ROOT_MNT}/dev/stdin"
  ln -sfn fd/1 "${TARGET_ROOT_MNT}/dev/stdout"
  ln -sfn fd/2 "${TARGET_ROOT_MNT}/dev/stderr"
  run_cmd "${MOUNT_BIN}" --bind /proc "${TARGET_ROOT_MNT}/proc"
  run_cmd "${MOUNT_BIN}" --bind /sys "${TARGET_ROOT_MNT}/sys"
  run_cmd "${CHROOT_BIN}" "${TARGET_ROOT_MNT}" /bin/bash /root/bootstrap-path-b.sh
}

resolve_built_kernel_version() {
  ls -1 "${TARGET_ROOT_MNT}/lib/modules" | sort -V | tail -n1
}

copy_variant_artifacts() {
  local variant_dir="$1"
  local kernel_version="$2"
  local squashfs_source="$3"

  mkdir -p "${variant_dir}"
  install -m 0644 "${TARGET_ROOT_MNT}/boot/vmlinuz-${kernel_version}" "${variant_dir}/vmlinuz"
  install -m 0644 "${TARGET_ROOT_MNT}/boot/initramfs-${kernel_version}.img" "${variant_dir}/initramfs.img"
  cp -f "${squashfs_source}" "${variant_dir}/rootfs.squashfs"
  cp -f "${squashfs_source}" "${variant_dir}/rootfs.img"
}

resolve_mksquashfs_compressor() {
  local supported

  supported="$("${MKSQUASHFS_BIN}" -help 2>&1 || true)"
  if printf '%s\n' "${supported}" | grep -Eq "\\b${PATHB_SQUASHFS_COMPRESSOR}\\b"; then
    printf '%s\n' "${PATHB_SQUASHFS_COMPRESSOR}"
    return
  fi

  if printf '%s\n' "${supported}" | grep -Eq "\\bgzip\\b"; then
    log "mksquashfs compressor '${PATHB_SQUASHFS_COMPRESSOR}' is unavailable; falling back to gzip"
    printf '%s\n' "gzip"
    return
  fi

  printf '%s\n' "${PATHB_SQUASHFS_COMPRESSOR}"
}

create_rootfs_artifacts() {
  local kernel_version
  local squashfs_path
  local squashfs_compressor

  kernel_version="$(resolve_built_kernel_version)"
  squashfs_path="${PATHB_BUILD_DIR}/rootfs.squashfs"
  squashfs_compressor="$(resolve_mksquashfs_compressor)"

  run_cmd "${MKSQUASHFS_BIN}" \
    "${TARGET_ROOT_MNT}" \
    "${squashfs_path}" \
    -noappend \
    -comp "${squashfs_compressor}" \
    -wildcards \
    -e dev/\* proc/\* sys/\* run/\* tmp/\* var/tmp/\* boot/efi/\*

  copy_variant_artifacts "${PATHB_INSTALLER_ARTIFACT_DIR}" "${kernel_version}" "${squashfs_path}"
  copy_variant_artifacts "${PATHB_RESCUE_ARTIFACT_DIR}" "${kernel_version}" "${squashfs_path}"
}

main() {
  trap cleanup EXIT

  resolve_host_tool_paths
  validate_stage3_profile_preset
  resolve_stage3_target
  validate_host_arch
  ensure_pathb_dirs
  reset_rootfs
  resolve_stage3_artifacts
  ensure_stage3_downloads
  extract_stage3
  render_pathb_bootstrap_script
  install_pathb_bootstrap_script
  run_pathb_bootstrap
  create_rootfs_artifacts
  log "Built Path B netboot artifacts under ${PATHB_ARTIFACT_ROOT}"
  log '[COMPLETE]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
