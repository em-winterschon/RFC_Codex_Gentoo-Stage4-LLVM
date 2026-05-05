#!/usr/bin/env bash
set -euo pipefail

REMOTE="${HASSLEHOFF_SSH_TARGET:-root@hasslehoff}"
BACKUP_ROOT="${HASSLEHOFF_BACKUP_ROOT:-/root/operator-private/hasslehoff/backups}"
STAMP="${HASSLEHOFF_BACKUP_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
DEST="${BACKUP_ROOT}/${STAMP}"
DRY_RUN="${HASSLEHOFF_BACKUP_DRY_RUN:-0}"

usage() {
  cat <<'USAGE'
Usage: backup-hasslehoff-config.sh

Environment:
  HASSLEHOFF_SSH_TARGET=root@hasslehoff
  HASSLEHOFF_BACKUP_ROOT=/root/operator-private/hasslehoff/backups
  HASSLEHOFF_BACKUP_STAMP=YYYYMMDDTHHMMSSZ
  HASSLEHOFF_BACKUP_DRY_RUN=1

Backs up Proxmox/Hasslehoff configuration to on-host operator-private storage.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '[hasslehoff-backup] %s\n' "$*" >&2
}

ssh_base=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
scp_base=(scp -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
remote_tmp="/tmp/hasslehoff-config-backup-${STAMP}"
remote_bundle="/tmp/hasslehoff-config-backup-${STAMP}.tar.gz"

if [[ "${DRY_RUN}" == "1" ]]; then
  printf 'remote=%s\n' "${REMOTE}"
  printf 'dest=%s\n' "${DEST}"
  printf 'remote_tmp=%s\n' "${remote_tmp}"
  printf 'remote_bundle=%s\n' "${remote_bundle}"
  printf 'captures=/etc/pve /etc/network/interfaces /etc/sysctl.d pvesh get /nodes/hasslehoff/qemu\n'
  exit 0
fi

install -d -m 0700 "${DEST}"

log "collecting remote config from ${REMOTE}"
"${ssh_base[@]}" "${REMOTE}" "BACKUP_TMP='${remote_tmp}' BACKUP_BUNDLE='${remote_bundle}' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

rm -rf "${BACKUP_TMP}" "${BACKUP_BUNDLE}"
install -d -m 0700 "${BACKUP_TMP}"/{files,pvesh,commands}

capture_file() {
  local path="$1"
  local out="${BACKUP_TMP}/files${path}"
  if [[ -e "${path}" ]]; then
    install -d -m 0700 "$(dirname "${out}")"
    cp -a "${path}" "${out}"
  fi
}

for path in \
  /etc/pve \
  /etc/network/interfaces \
  /etc/hosts \
  /etc/hostname \
  /etc/resolv.conf \
  /etc/sysctl.conf \
  /etc/sysctl.d \
  /etc/modules \
  /etc/modules-load.d \
  /etc/modprobe.d \
  /etc/default/grub \
  /etc/apt/sources.list \
  /etc/apt/sources.list.d \
  /etc/vzdump.conf
do
  capture_file "${path}"
done

run_capture() {
  local name="$1"
  shift
  {
    "$@"
  } > "${BACKUP_TMP}/commands/${name}.txt" 2>&1 || true
}

run_pvesh() {
  local name="$1"
  shift
  {
    pvesh get "$@" --output-format json
  } > "${BACKUP_TMP}/pvesh/${name}.json" 2>&1 || true
}

run_capture pveversion pveversion -v
run_capture qm-list qm list
run_capture pct-list pct list
run_capture ip-addr ip -br addr
run_capture ip-route ip route
run_capture bridge-link bridge link
run_capture bridge-vlan bridge vlan
run_capture ss-listen ss -lntup
run_capture proc-cmdline cat /proc/cmdline
run_capture lsblk lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
run_capture zpool-status zpool status
run_capture zfs-list zfs list

run_pvesh qemu /nodes/hasslehoff/qemu
run_pvesh lxc /nodes/hasslehoff/lxc
run_pvesh storage /nodes/hasslehoff/storage
run_pvesh network /nodes/hasslehoff/network
run_pvesh disks /nodes/hasslehoff/disks/list
run_pvesh cluster-resources /cluster/resources

tar -C "$(dirname "${BACKUP_TMP}")" -czf "${BACKUP_BUNDLE}" "$(basename "${BACKUP_TMP}")"
(
  cd "$(dirname "${BACKUP_BUNDLE}")"
  sha256sum "$(basename "${BACKUP_BUNDLE}")" > "${BACKUP_BUNDLE}.sha256"
)
REMOTE_SCRIPT

log "copying backup bundle to ${DEST}"
"${scp_base[@]}" "${REMOTE}:${remote_bundle}" "${DEST}/"
"${scp_base[@]}" "${REMOTE}:${remote_bundle}.sha256" "${DEST}/"

log "removing remote temporary files"
"${ssh_base[@]}" "${REMOTE}" "rm -rf '${remote_tmp}' '${remote_bundle}' '${remote_bundle}.sha256'"

(
  cd "${DEST}"
  sha256sum -c "$(basename "${remote_bundle}").sha256"
)

log "backup complete: ${DEST}"
