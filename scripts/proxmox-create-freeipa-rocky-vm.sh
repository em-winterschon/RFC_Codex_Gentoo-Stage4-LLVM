#!/bin/bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-hasslehoff}"
VMID="${VMID:-1063}"
VM_NAME="${VM_NAME:-svc-identity-ipa01}"
VM_FQDN="${VM_FQDN:-ipa01.rfc1918.host}"
VM_IP_CIDR="${VM_IP_CIDR:-172.16.99.63/24}"
VM_GATEWAY="${VM_GATEWAY:-172.16.99.1}"
VM_DNS="${VM_DNS:-9.9.9.9}"
VM_SEARCH_DOMAIN="${VM_SEARCH_DOMAIN:-rfc1918.host}"
VM_CORES="${VM_CORES:-4}"
VM_MEMORY_MB="${VM_MEMORY_MB:-12288}"
VM_DISK_SIZE="${VM_DISK_SIZE:-80G}"
PVE_STORAGE="${PVE_STORAGE:-local-zfs}"
PVE_BRIDGE="${PVE_BRIDGE:-vmbr0}"
PVE_MACADDR="${PVE_MACADDR:-52:54:00:99:10:63}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"
ROCKY_CLOUD_IMAGE_URL="${ROCKY_CLOUD_IMAGE_URL:-https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2}"
ROCKY_CLOUD_IMAGE_PATH="${ROCKY_CLOUD_IMAGE_PATH:-/var/lib/vz/template/cache/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2}"

if [[ ! -r "${SSH_PUBKEY_FILE}" ]]; then
  echo "SSH public key not readable: ${SSH_PUBKEY_FILE}" >&2
  exit 2
fi

tmp_key="/tmp/${VM_NAME}.sshkey.pub"
scp -q "${SSH_PUBKEY_FILE}" "${PVE_HOST}:${tmp_key}"

ssh "${PVE_HOST}" bash -s -- \
  "${VMID}" \
  "${VM_NAME}" \
  "${VM_FQDN}" \
  "${VM_IP_CIDR}" \
  "${VM_GATEWAY}" \
  "${VM_DNS}" \
  "${VM_SEARCH_DOMAIN}" \
  "${VM_CORES}" \
  "${VM_MEMORY_MB}" \
  "${VM_DISK_SIZE}" \
  "${PVE_STORAGE}" \
  "${PVE_BRIDGE}" \
  "${PVE_MACADDR}" \
  "${ROCKY_CLOUD_IMAGE_URL}" \
  "${ROCKY_CLOUD_IMAGE_PATH}" \
  "${tmp_key}" << 'REMOTE'
set -euo pipefail

vmid="$1"
vm_name="$2"
vm_fqdn="$3"
vm_ip_cidr="$4"
vm_gateway="$5"
vm_dns="$6"
vm_search_domain="$7"
vm_cores="$8"
vm_memory_mb="$9"
vm_disk_size="${10}"
pve_storage="${11}"
pve_bridge="${12}"
pve_macaddr="${13}"
rocky_cloud_image_url="${14}"
rocky_cloud_image_path="${15}"
ssh_key_path="${16}"

if qm status "${vmid}" >/dev/null 2>&1; then
  echo "VM ${vmid} already exists; leaving it unchanged."
  qm status "${vmid}"
  exit 0
fi

if [[ ! -s "${rocky_cloud_image_path}" ]]; then
  mkdir -p "$(dirname "${rocky_cloud_image_path}")"
  curl -L --fail --retry 5 --retry-delay 5 -o "${rocky_cloud_image_path}.tmp" "${rocky_cloud_image_url}"
  mv "${rocky_cloud_image_path}.tmp" "${rocky_cloud_image_path}"
fi

qm create "${vmid}" \
  --name "${vm_name}" \
  --ostype l26 \
  --memory "${vm_memory_mb}" \
  --cores "${vm_cores}" \
  --cpu host \
  --agent enabled=1 \
  --scsihw virtio-scsi-pci \
  --net0 "virtio=${pve_macaddr},bridge=${pve_bridge}" \
  --serial0 socket \
  --vga serial0

qm importdisk "${vmid}" "${rocky_cloud_image_path}" "${pve_storage}" --format raw
qm set "${vmid}" --scsi0 "${pve_storage}:vm-${vmid}-disk-0,discard=on"
qm resize "${vmid}" scsi0 "${vm_disk_size}"
qm set "${vmid}" --ide2 "${pve_storage}:cloudinit"
qm set "${vmid}" --boot order=scsi0
qm set "${vmid}" --citype nocloud
qm set "${vmid}" --ciuser codex
qm set "${vmid}" --sshkeys "${ssh_key_path}"
qm set "${vmid}" --ipconfig0 "ip=${vm_ip_cidr},gw=${vm_gateway}"
qm set "${vmid}" --nameserver "${vm_dns}"
qm set "${vmid}" --searchdomain "${vm_search_domain}"
qm set "${vmid}" --description "Stage5 central identity controller candidate: ${vm_fqdn}"
qm start "${vmid}"
qm status "${vmid}"
REMOTE
