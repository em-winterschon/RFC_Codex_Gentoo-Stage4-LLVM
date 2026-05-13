#!/usr/bin/env bash
set -euo pipefail

if [[ "${PATHB_TRACE:-0}" == '1' ]]; then
  set -x
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ANSIBLE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER_SCRIPT="${REPO_ROOT}/gentoo-virt-qemu/build-stage3-qcow.sh"
PATHB_STAGE3_CACHE_DIR_EXPLICIT="${STAGE3_CACHE_DIR+x}"

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
if [[ -z "${PATHB_STAGE3_CACHE_DIR_EXPLICIT}" ]]; then
  STAGE3_CACHE_DIR="${PATHB_CACHE_DIR}"
fi
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
PATHB_EXTRA_PACKAGES="${PATHB_EXTRA_PACKAGES:-app-admin/sudo dev-lang/python sys-apps/iproute2 sys-kernel/linux-firmware sys-fs/zfs sys-fs/zfs-kmod sys-fs/dosfstools sys-block/parted sys-apps/pciutils sys-apps/usbutils sys-apps/kmod}"
PATHB_PACKAGE_USE_APPEND="${PATHB_PACKAGE_USE_APPEND:-}"
PATHB_ACCEPT_LICENSE="${PATHB_ACCEPT_LICENSE:-*.*}"
PATHB_FEATURES="${PATHB_FEATURES:-buildpkg -binpkg-request-signature -network-sandbox}"
PATHB_MAKEOPTS="${PATHB_MAKEOPTS:--j56 -l64}"
PATHB_EMERGE_DEFAULT_OPTS="${PATHB_EMERGE_DEFAULT_OPTS:---buildpkg=y --usepkg=y --with-bdeps=y --complete-graph=y --autounmask=y --autounmask-backtrack=y --autounmask-continue=y --autounmask-unrestricted-atoms=y --autounmask-use=y --autounmask-write=y --binpkg-respect-use=y --jobs=8 --load-average=64}"
PATHB_PORTAGE_TMPDIR="${PATHB_PORTAGE_TMPDIR:-/var/tmp/portage}"
PATHB_ENABLE_HOST_CACHE_BINDS="${PATHB_ENABLE_HOST_CACHE_BINDS:-1}"
PATHB_HOST_DISTFILES_DIR="${PATHB_HOST_DISTFILES_DIR:-/srv/build-cache/distfiles}"
PATHB_HOST_BINPKG_DIR="${PATHB_HOST_BINPKG_DIR:-/srv/build-cache/binpkgs}"
PATHB_GUEST_DISTFILES_DIR="${PATHB_GUEST_DISTFILES_DIR:-/srv/build-cache/distfiles}"
PATHB_GUEST_BINPKG_DIR="${PATHB_GUEST_BINPKG_DIR:-/srv/build-cache/binpkgs}"
PATHB_PROFILE_DEFINITION_FILES="${PATHB_PROFILE_DEFINITION_FILES:-}"
PATHB_PROFILE_PACKAGE_LIST_FILES="${PATHB_PROFILE_PACKAGE_LIST_FILES:-}"
PATHB_OPENRC_SERVICES_EXTRA="${PATHB_OPENRC_SERVICES_EXTRA:-}"
PATHB_PROFILE_PYTHON="${PATHB_PROFILE_PYTHON:-python3}"
PATHB_HOSTNAME="${PATHB_HOSTNAME:-gentoo-pathb}"
PATHB_TIMEZONE="${PATHB_TIMEZONE:-UTC}"
PATHB_LOCALE="${PATHB_LOCALE:-en_US.UTF-8 UTF-8}"
PATHB_KEYMAP="${PATHB_KEYMAP:-us}"
PATHB_SERIAL_BAUD="${PATHB_SERIAL_BAUD:-115200}"
PATHB_ROOT_PASSWORD_HASH="${PATHB_ROOT_PASSWORD_HASH:-}"
MKSQUASHFS_BIN="${MKSQUASHFS_BIN:-/usr/bin/mksquashfs}"
PATHB_SQUASHFS_COMPRESSOR="${PATHB_SQUASHFS_COMPRESSOR:-zstd}"
PATHB_INITRAMFS_COMPRESSOR="${PATHB_INITRAMFS_COMPRESSOR:-gzip}"

ensure_pathb_dirs() {
  mkdir -p \
    "${PATHB_CACHE_DIR}" \
    "${PATHB_BUILD_DIR}" \
    "${PATHB_INSTALLER_ARTIFACT_DIR}" \
    "${PATHB_RESCUE_ARTIFACT_DIR}"
}

cleanup_mounts() {
  local mount_list
  local mount_target

  if [[ "${QEMU_STAGE3_BUILD_DRY_RUN}" == '1' || ! -e "${TARGET_ROOT_MNT}" ]]; then
    return 0
  fi

  mount_list="$(mktemp)"
  findmnt -Rrn -o TARGET "${TARGET_ROOT_MNT}" 2> /dev/null | sort -r > "${mount_list}" || true
  while IFS= read -r mount_target; do
    "${UMOUNT_BIN}" "${mount_target}" > /dev/null 2>&1 || "${UMOUNT_BIN}" -l "${mount_target}" > /dev/null 2>&1 || true
  done < "${mount_list}"
  rm -f "${mount_list}"
}

resolve_ansible_path() {
  local input_path="$1"

  case "${input_path}" in
  /*)
    printf '%s\n' "${input_path}"
    ;;
  *)
    printf '%s\n' "${ANSIBLE_ROOT}/${input_path}"
    ;;
  esac
}

profile_definition_query() {
  local query="$1"
  shift

  "${PATHB_PROFILE_PYTHON}" - "${ANSIBLE_ROOT}" "${query}" "$@" << 'PY'
import pathlib
import sys

try:
    import yaml
except ImportError as exc:
    raise SystemExit("PyYAML is required to read Path B profile definition files") from exc

root = pathlib.Path(sys.argv[1])
query = sys.argv[2]
profile_paths = sys.argv[3:]

for raw_path in profile_paths:
    path = pathlib.Path(raw_path)
    if not path.is_absolute():
        path = root / path
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    profile = data.get("gentoo_profile_definition") or {}
    if query == "package-list-files":
        for item in profile.get("package_list_files", []) or []:
            print(item)
    elif query == "package-atoms":
        for item in profile.get("package_atoms", []) or []:
            print(item)
    elif query == "package-use-files":
        for name, content in (profile.get("package_use_files", {}) or {}).items():
            print(f"# {path.name}:{name}")
            print(str(content).rstrip())
    elif query == "openrc-services-enable":
        for item in profile.get("openrc_services_enable", []) or []:
            print(item)
    else:
        raise SystemExit(f"Unsupported profile definition query: {query}")
PY
}

read_pathb_package_list_atoms() {
  local package_list_file
  local package_list_path
  local line

  for package_list_file in "$@"; do
    package_list_path="$(resolve_ansible_path "${package_list_file}")"
    [[ -f "${package_list_path}" ]] || fail "Path B profile package list is missing: ${package_list_file}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -n "${line}" ]] || continue
      printf '%s\n' "${line}"
    done < "${package_list_path}"
  done
}

append_multiline_value() {
  local variable_name="$1"
  local addition="$2"
  local current_value="${!variable_name}"

  [[ -n "${addition}" ]] || return 0

  if [[ -n "${current_value}" ]]; then
    printf -v "${variable_name}" '%s\n%s' "${current_value}" "${addition}"
  else
    printf -v "${variable_name}" '%s' "${addition}"
  fi
}

append_word_list_value() {
  local variable_name="$1"
  local addition="$2"
  local current_value="${!variable_name}"

  [[ -n "${addition}" ]] || return 0

  addition="$(printf '%s\n' "${addition}" | awk 'NF { print }' | tr '\n' ' ')"
  addition="${addition%"${addition##*[![:space:]]}"}"
  [[ -n "${addition}" ]] || return 0

  if [[ -n "${current_value}" ]]; then
    printf -v "${variable_name}" '%s %s' "${current_value}" "${addition}"
  else
    printf -v "${variable_name}" '%s' "${addition}"
  fi
}

resolve_pathb_profile_inputs() {
  local profile_files=()
  local package_list_files=()
  local profile_package_lists
  local profile_package_atoms
  local profile_package_use
  local profile_openrc_services
  local package_list_atoms

  if [[ -n "${PATHB_PROFILE_DEFINITION_FILES}" ]]; then
    read -r -a profile_files <<< "${PATHB_PROFILE_DEFINITION_FILES}"
    profile_package_lists="$(profile_definition_query package-list-files "${profile_files[@]}")"
    profile_package_atoms="$(profile_definition_query package-atoms "${profile_files[@]}")"
    profile_package_use="$(profile_definition_query package-use-files "${profile_files[@]}")"
    profile_openrc_services="$(profile_definition_query openrc-services-enable "${profile_files[@]}")"

    append_word_list_value PATHB_PROFILE_PACKAGE_LIST_FILES "${profile_package_lists}"
    append_word_list_value PATHB_EXTRA_PACKAGES "${profile_package_atoms}"
    append_multiline_value PATHB_PACKAGE_USE_APPEND "${profile_package_use}"
    append_word_list_value PATHB_OPENRC_SERVICES_EXTRA "${profile_openrc_services}"
  fi

  if [[ -n "${PATHB_PROFILE_PACKAGE_LIST_FILES}" ]]; then
    read -r -a package_list_files <<< "${PATHB_PROFILE_PACKAGE_LIST_FILES}"
    package_list_atoms="$(read_pathb_package_list_atoms "${package_list_files[@]}")"
    append_word_list_value PATHB_EXTRA_PACKAGES "${package_list_atoms}"
  fi
}

reset_rootfs() {
  local stale_target

  cleanup_mounts
  if [[ -e "${TARGET_ROOT_MNT}" ]]; then
    stale_target="${TARGET_ROOT_MNT}.stale.$(date -u +%Y%m%dT%H%M%SZ)"
    if mv "${TARGET_ROOT_MNT}" "${stale_target}"; then
      printf '[build-path-b-netboot-artifacts] WARN: quarantined stale rootfs at %s\n' "${stale_target}" >&2
    else
      rm -rf "${TARGET_ROOT_MNT}"
    fi
  fi
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
  cat > "${WORK_BOOTSTRAP_SCRIPT}" << EOF
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
ACCEPT_LICENSE="${PATHB_ACCEPT_LICENSE}"
FEATURES="${PATHB_FEATURES}"
MAKEOPTS="${PATHB_MAKEOPTS}"
EMERGE_DEFAULT_OPTS="${PATHB_EMERGE_DEFAULT_OPTS}"
PKGDIR="${PATHB_GUEST_BINPKG_DIR}"
DISTDIR="${PATHB_GUEST_DISTFILES_DIR}"
PORTAGE_TMPDIR="${PATHB_PORTAGE_TMPDIR}"
MAKECONF

mkdir -p \
  "${PATHB_GUEST_DISTFILES_DIR}" \
  "${PATHB_GUEST_BINPKG_DIR}" \
  "${PATHB_PORTAGE_TMPDIR}"
chmod 1777 "${PATHB_PORTAGE_TMPDIR}"

cat > /etc/portage/package.use/path-b-dracut <<'PKGUSE'
sys-kernel/installkernel dracut -systemd
PKGUSE

if [[ -n ${PATHB_PACKAGE_USE_APPEND@Q} ]]; then
cat > /etc/portage/package.use/path-b-extra <<'PKGUSE_EXTRA'
${PATHB_PACKAGE_USE_APPEND}
PKGUSE_EXTRA
fi

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

boot_iface="\$(ip route show default 2> /dev/null | awk 'NR==1 { print \$5 }')"

if [[ -n "\${boot_iface}" ]]; then
  mapfile -t boot_ipv4_addrs < <(ip -o -4 addr show dev "\${boot_iface}" scope global 2>/dev/null | awk '{ print \$4 }')

  if (( \${#boot_ipv4_addrs[@]} > 1 )); then
    for stale_addr in "\${boot_ipv4_addrs[@]:1}"; do
      ip addr del "\${stale_addr}" dev "\${boot_iface}" >/dev/null 2>&1 || true
    done
  fi

  mapfile -t boot_default_routes < <(ip route show default dev "\${boot_iface}" 2>/dev/null)
  if (( \${#boot_default_routes[@]} > 1 )); then
    for stale_route in "\${boot_default_routes[@]:1}"; do
      ip route del \${stale_route} >/dev/null 2>&1 || true
    done
  fi
fi

pkill dhcpcd >/dev/null 2>&1 || true
LOCALNET
chmod 0755 /etc/local.d/pathb-network-handoff.start
fi

if [[ "${PATHB_REUSE_INITRAMFS_NETWORK}" != '1' ]]; then
  rc-update add ${PATHB_NETWORK_SERVICE} default
fi
rc-update add ${PATHB_SSH_SERVICE} default
for pathb_extra_service in ${PATHB_OPENRC_SERVICES_EXTRA}; do
  rc-update add "\${pathb_extra_service}" default
done

cat > /etc/dracut.conf.d/path-b-live.conf <<'DRACUT'
hostonly="no"
use_fstab="no"
add_dracutmodules+=" dmsquash-live livenet network url-lib "
filesystems+=" squashfs overlay ext4 vfat "
install_items+=" /lib/firmware/rtl_nic/rtl8125b-2.fw /usr/lib/firmware/rtl_nic/rtl8125b-2.fw "
compress="${PATHB_INITRAMFS_COMPRESSOR}"
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
  mkdir -p "${TARGET_ROOT_MNT}/dev"
  run_cmd "${MOUNT_BIN}" -t tmpfs tmpfs -o mode=755,nosuid "${TARGET_ROOT_MNT}/dev"
  mkdir -p "${TARGET_ROOT_MNT}/dev/pts" "${TARGET_ROOT_MNT}/dev/shm"
  run_cmd "${MOUNT_BIN}" -t devpts devpts -o gid=5,mode=620,ptmxmode=666 "${TARGET_ROOT_MNT}/dev/pts"
  run_cmd "${MOUNT_BIN}" -t tmpfs tmpfs "${TARGET_ROOT_MNT}/dev/shm"
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
  if [[ "${PATHB_ENABLE_HOST_CACHE_BINDS}" == '1' ]]; then
    mkdir -p \
      "${PATHB_HOST_DISTFILES_DIR}" \
      "${PATHB_HOST_BINPKG_DIR}" \
      "${TARGET_ROOT_MNT}${PATHB_GUEST_DISTFILES_DIR}" \
      "${TARGET_ROOT_MNT}${PATHB_GUEST_BINPKG_DIR}"
    run_cmd "${MOUNT_BIN}" --bind "${PATHB_HOST_DISTFILES_DIR}" "${TARGET_ROOT_MNT}${PATHB_GUEST_DISTFILES_DIR}"
    run_cmd "${MOUNT_BIN}" --bind "${PATHB_HOST_BINPKG_DIR}" "${TARGET_ROOT_MNT}${PATHB_GUEST_BINPKG_DIR}"
  fi
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
  ln -sfn initramfs.img "${variant_dir}/initramfs-gz.img"
  cp -f "${squashfs_source}" "${variant_dir}/rootfs.squashfs"
  cp -f "${squashfs_source}" "${variant_dir}/rootfs.img"
}

resolve_mksquashfs_compressor() {
  local supported

  supported="$("${MKSQUASHFS_BIN}" -help-section compression 2>&1 || "${MKSQUASHFS_BIN}" -help 2>&1 || true)"
  if printf '%s\n' "${supported}" | grep -Eq "\\b${PATHB_SQUASHFS_COMPRESSOR}\\b"; then
    printf '%s\n' "${PATHB_SQUASHFS_COMPRESSOR}"
    return
  fi

  if printf '%s\n' "${supported}" | grep -Eq "\\bgzip\\b"; then
    log "mksquashfs compressor '${PATHB_SQUASHFS_COMPRESSOR}' is unavailable; falling back to gzip" >&2
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

  STAGE3_HOST_TOOL_VARS="${PATHB_HOST_TOOL_VARS:-MODPROBE_BIN MKNOD_BIN MOUNT_BIN UMOUNT_BIN TAR_BIN CHROOT_BIN}"
  resolve_host_tool_paths
  validate_stage3_profile_preset
  resolve_stage3_target
  validate_host_arch
  ensure_pathb_dirs
  resolve_pathb_profile_inputs
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
