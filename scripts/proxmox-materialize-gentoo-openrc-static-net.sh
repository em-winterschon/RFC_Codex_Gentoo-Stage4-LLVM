#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-hasslehoff}"
VMID="${VMID:-}"
VM_NAME="${VM_NAME:-}"
VM_IP_CIDR="${VM_IP_CIDR:-}"
VM_GATEWAY="${VM_GATEWAY:-}"
VM_DNS="${VM_DNS:-9.9.9.9 8.8.8.8}"
VM_SEARCH_DOMAIN="${VM_SEARCH_DOMAIN:-rfc1918.host}"
VM_BOOT_DISK="${VM_BOOT_DISK:-}"
VM_NET_SERVICE="${VM_NET_SERVICE:-eth0}"
VM_DISABLE_DHCPCD="${VM_DISABLE_DHCPCD:-1}"
VM_ENABLE_SSHD="${VM_ENABLE_SSHD:-1}"
VM_ENABLE_QEMU_GUEST_AGENT="${VM_ENABLE_QEMU_GUEST_AGENT:-1}"
VM_ENABLE_SERIAL_GETTY="${VM_ENABLE_SERIAL_GETTY:-1}"
VM_RESIZE_ROOTFS="${VM_RESIZE_ROOTFS:-1}"
PROXMOX_SNAPSHOT_BEFORE_CONFIG="${PROXMOX_SNAPSHOT_BEFORE_CONFIG:-1}"
PROXMOX_START_AFTER_CONFIG="${PROXMOX_START_AFTER_CONFIG:-0}"
PROXMOX_APPLY="${PROXMOX_APPLY:-0}"
DRY_RUN=1

usage() {
  cat << 'EOF'
Usage: proxmox-materialize-gentoo-openrc-static-net.sh [--dry-run|--apply]

Writes static OpenRC network configuration directly into a stopped Gentoo VM
root filesystem on a Proxmox ZFS-backed VM disk. This is for Stage4 images that
do not run cloud-init inside the guest, even when Proxmox NoCloud metadata is
attached.

Required environment:
  VMID
  VM_NAME
  VM_IP_CIDR
  VM_GATEWAY

Optional environment:
  PVE_HOST=hasslehoff
  VM_DNS='9.9.9.9 8.8.8.8'
  VM_SEARCH_DOMAIN=rfc1918.host
  VM_BOOT_DISK=local-zfs:vm-1064-disk-0
  VM_NET_SERVICE=eth0
  VM_DISABLE_DHCPCD=1
  VM_ENABLE_SSHD=1
  VM_ENABLE_QEMU_GUEST_AGENT=1
  VM_ENABLE_SERIAL_GETTY=1
  VM_RESIZE_ROOTFS=1
  PROXMOX_SNAPSHOT_BEFORE_CONFIG=1
  PROXMOX_START_AFTER_CONFIG=0

Safety:
  Live execution requires --apply and PROXMOX_APPLY=1.
EOF
}

fail() {
  printf '[proxmox-materialize-gentoo-openrc-static-net] ERROR: %s\n' "$*" >&2
  exit 2
}

shell_quote() {
  if [[ "$1" =~ ^[A-Za-z0-9_./:@=+,%:-]+$ ]]; then
    printf '%s' "$1"
  else
    printf '%q' "$1"
  fi
}

required_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "${name} is required"
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --apply)
      DRY_RUN=0
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
    esac
    shift
  done
}

validate_inputs() {
  required_var VMID
  required_var VM_NAME
  required_var VM_IP_CIDR
  required_var VM_GATEWAY

  [[ "${VMID}" =~ ^[0-9]+$ ]] || fail "VMID must be numeric: ${VMID}"
  [[ "${VM_DISABLE_DHCPCD}" =~ ^[01]$ ]] || fail "VM_DISABLE_DHCPCD must be 0 or 1"
  [[ "${VM_ENABLE_SSHD}" =~ ^[01]$ ]] || fail "VM_ENABLE_SSHD must be 0 or 1"
  [[ "${VM_ENABLE_QEMU_GUEST_AGENT}" =~ ^[01]$ ]] || fail "VM_ENABLE_QEMU_GUEST_AGENT must be 0 or 1"
  [[ "${VM_ENABLE_SERIAL_GETTY}" =~ ^[01]$ ]] || fail "VM_ENABLE_SERIAL_GETTY must be 0 or 1"
  [[ "${VM_RESIZE_ROOTFS}" =~ ^[01]$ ]] || fail "VM_RESIZE_ROOTFS must be 0 or 1"
  [[ "${PROXMOX_SNAPSHOT_BEFORE_CONFIG}" =~ ^[01]$ ]] || fail "PROXMOX_SNAPSHOT_BEFORE_CONFIG must be 0 or 1"
  [[ "${PROXMOX_START_AFTER_CONFIG}" =~ ^[01]$ ]] || fail "PROXMOX_START_AFTER_CONFIG must be 0 or 1"

  if [[ "${DRY_RUN}" == '0' && "${PROXMOX_APPLY}" != '1' ]]; then
    fail "PROXMOX_APPLY=1 is required for live --apply mode"
  fi
}

render_remote_script() {
  cat << EOF
set -euo pipefail

vmid=$(shell_quote "${VMID}")
vm_name=$(shell_quote "${VM_NAME}")
vm_ip_cidr=$(shell_quote "${VM_IP_CIDR}")
vm_gateway=$(shell_quote "${VM_GATEWAY}")
vm_dns=$(shell_quote "${VM_DNS}")
vm_search_domain=$(shell_quote "${VM_SEARCH_DOMAIN}")
vm_boot_disk=$(shell_quote "${VM_BOOT_DISK}")
vm_net_service=$(shell_quote "${VM_NET_SERVICE}")
disable_dhcpcd=$(shell_quote "${VM_DISABLE_DHCPCD}")
enable_sshd=$(shell_quote "${VM_ENABLE_SSHD}")
enable_qemu_guest_agent=$(shell_quote "${VM_ENABLE_QEMU_GUEST_AGENT}")
enable_serial_getty=$(shell_quote "${VM_ENABLE_SERIAL_GETTY}")
resize_rootfs=$(shell_quote "${VM_RESIZE_ROOTFS}")
snapshot_before_config=$(shell_quote "${PROXMOX_SNAPSHOT_BEFORE_CONFIG}")
start_after_config=$(shell_quote "${PROXMOX_START_AFTER_CONFIG}")

if ! qm status "\${vmid}" >/dev/null 2>&1; then
  echo "VM \${vmid} does not exist on this Proxmox host." >&2
  exit 3
fi

if [[ "\${snapshot_before_config}" == '1' ]]; then
  snap="pre-openrc-net-\$(date -u +%m%dT%H%MZ)"
  qm snapshot "\${vmid}" "\${snap}" --description "Before offline Gentoo OpenRC static network materialization" || true
fi

if qm status "\${vmid}" | grep -q running; then
  qm stop "\${vmid}" --timeout 60 || true
  qm wait "\${vmid}" --timeout 60 || true
fi

if [[ -z "\${vm_boot_disk}" ]]; then
  vm_boot_disk="\$(qm config "\${vmid}" | awk -F': ' '/^scsi0: / {print \$2}' | cut -d, -f1)"
fi

case "\${vm_boot_disk}" in
  local-zfs:*) zvol="/dev/zvol/rpool/data/\${vm_boot_disk#local-zfs:}" ;;
  *) echo "unsupported boot volume for offline configuration: \${vm_boot_disk}" >&2; exit 3 ;;
esac

if [[ ! -b "\${zvol}" ]]; then
  echo "missing VM boot zvol: \${zvol}" >&2
  exit 3
fi

disk="\$(realpath "\${zvol}")"

sgdisk -e "\${disk}" >/dev/null
partprobe "\${disk}" || true
partx -u "\${disk}" >/dev/null 2>&1 || true

root_part=""
root_part_type=""
while read -r candidate; do
  if [[ "\${candidate}" == "\${disk}" ]]; then
    continue
  fi
  candidate_type="\$(blkid -o value -s TYPE "\${candidate}" 2>/dev/null || true)"
  case "\${candidate_type}" in
    ext2 | ext3 | ext4)
      root_part="\${candidate}"
      root_part_type="\${candidate_type}"
      break
      ;;
  esac
done < <(lsblk -pnro NAME "\${disk}")

if [[ -z "\${root_part}" ]]; then
  while read -r candidate; do
    if [[ "\${candidate}" == "\${disk}" ]]; then
      continue
    fi
    candidate_type="\$(blkid -o value -s TYPE "\${candidate}" 2>/dev/null || true)"
    if [[ "\${candidate_type}" == 'zfs_member' ]]; then
      root_part="\${candidate}"
      root_part_type="\${candidate_type}"
      break
    fi
  done < <(lsblk -pnro NAME "\${disk}")
fi

if [[ -z "\${root_part}" ]]; then
  echo "unable to locate an ext or ZFS Gentoo root partition on \${disk}" >&2
  exit 3
fi

mnt="/mnt/offline-vm-\${vmid}"
mkdir -p "\${mnt}"
if mountpoint -q "\${mnt}"; then
  umount "\${mnt}"
fi

zfs_import_name=""
zfs_imported=0
zfs_root_dataset=""
cleanup() {
  if [[ "\${zfs_imported}" == '1' ]]; then
    zfs list -H -r -o name,mounted "\${zfs_import_name}" 2>/dev/null \
      | awk '\$2 == "yes" {print \$1}' \
      | sort -r \
      | while read -r dataset; do
          zfs unmount "\${dataset}" >/dev/null 2>&1 || true
        done
    zpool export "\${zfs_import_name}" >/dev/null 2>&1 || true
  elif mountpoint -q "\${mnt}"; then
    umount "\${mnt}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

case "\${root_part_type}" in
  ext2 | ext3 | ext4)
    if [[ "\${resize_rootfs}" == '1' ]]; then
      root_part_num="\$(partx -g -o NR "\${root_part}" | awk 'NF {print \$1; exit}')"
      if [[ -n "\${root_part_num}" ]]; then
        parted -s "\${disk}" resizepart "\${root_part_num}" 100% || true
        partprobe "\${disk}" || true
        partx -u "\${disk}" >/dev/null 2>&1 || true
      fi
      set +e
      e2fsck -fy "\${root_part}"
      fsck_rc=\$?
      set -e
      if [[ "\${fsck_rc}" -gt 1 ]]; then
        exit "\${fsck_rc}"
      fi
      resize2fs "\${root_part}"
    fi
    mount "\${root_part}" "\${mnt}"
    ;;
  zfs_member)
    zfs_pool_id="\$(blkid -o value -s UUID "\${root_part}" 2>/dev/null || true)"
    if [[ -z "\${zfs_pool_id}" ]]; then
      echo "unable to resolve ZFS pool id from \${root_part}" >&2
      exit 3
    fi
    zfs_import_name="offlinevm\${vmid}"
    if zpool list -H -o name | grep -qx "\${zfs_import_name}"; then
      zpool export "\${zfs_import_name}" >/dev/null 2>&1 || true
    fi
    zpool import -f -N -R "\${mnt}" "\${zfs_pool_id}" "\${zfs_import_name}"
    zfs_imported=1
    zfs_root_dataset="\$(zfs list -H -r -o name,mountpoint "\${zfs_import_name}" | awk -v mnt="\${mnt}" '\$2 == mnt {print \$1; exit}')"
    if [[ -z "\${zfs_root_dataset}" ]]; then
      zfs_root_dataset="\$(zfs list -H -r -o name "\${zfs_import_name}" | awk '/\\/ROOT\\// {print; exit}')"
    fi
    if [[ -z "\${zfs_root_dataset}" ]]; then
      echo "unable to locate ZFS root dataset in \${zfs_import_name}" >&2
      exit 3
    fi
    zfs mount "\${zfs_root_dataset}"
    ;;
  *)
    echo "unsupported Gentoo root partition type \${root_part_type} on \${root_part}" >&2
    exit 3
    ;;
esac

mkdir -p "\${mnt}/etc/conf.d" "\${mnt}/etc/runlevels/default"
cat > "\${mnt}/etc/conf.d/net" <<NETEOF
# Managed by RFC_Codex_Gentoo-Stage4-LLVM for Proxmox Stage4 service VMs.
config_\${vm_net_service}="\${vm_ip_cidr}"
routes_\${vm_net_service}="default via \${vm_gateway}"
dns_servers_\${vm_net_service}="\${vm_dns}"
dns_domain_\${vm_net_service}="\${vm_search_domain}"
NETEOF

printf 'hostname="%s"\n' "\${vm_name}" > "\${mnt}/etc/conf.d/hostname"
printf '%s\n' "\${vm_name}" > "\${mnt}/etc/hostname"
cat > "\${mnt}/etc/hosts" <<HOSTSEOF
127.0.0.1 localhost
127.0.1.1 \${vm_name}.\${vm_search_domain} \${vm_name}
::1 localhost
HOSTSEOF

ln -sfn net.lo "\${mnt}/etc/init.d/net.\${vm_net_service}"
ln -sfn "/etc/init.d/net.\${vm_net_service}" "\${mnt}/etc/runlevels/default/net.\${vm_net_service}"

if [[ "\${disable_dhcpcd}" == '1' ]]; then
  rm -f "\${mnt}/etc/runlevels/default/dhcpcd"
fi

if [[ "\${enable_sshd}" == '1' && -x "\${mnt}/etc/init.d/sshd" ]]; then
  ln -sfn /etc/init.d/sshd "\${mnt}/etc/runlevels/default/sshd"
fi

if [[ "\${enable_qemu_guest_agent}" == '1' && -x "\${mnt}/etc/init.d/qemu-guest-agent" ]]; then
  ln -sfn /etc/init.d/qemu-guest-agent "\${mnt}/etc/runlevels/default/qemu-guest-agent"
fi

if [[ "\${enable_serial_getty}" == '1' && -f "\${mnt}/etc/inittab" ]]; then
  sed -i 's/^#s0:/s0:/' "\${mnt}/etc/inittab"
fi

sync
cleanup
trap - EXIT

if [[ "\${start_after_config}" == '1' ]]; then
  qm start "\${vmid}"
fi
EOF
}

main() {
  parse_args "$@"
  validate_inputs

  if [[ "${DRY_RUN}" == '1' ]]; then
    printf 'PVE_HOST=%s\n' "${PVE_HOST}"
    render_remote_script
    return 0
  fi

  render_remote_script | ssh "${PVE_HOST}" bash -s
}

main "$@"
