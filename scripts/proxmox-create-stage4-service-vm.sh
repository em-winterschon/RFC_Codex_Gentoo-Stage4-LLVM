#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-hasslehoff}"
VMID="${VMID:-}"
VM_NAME="${VM_NAME:-}"
VM_MEMORY_MIB="${VM_MEMORY_MIB:-${VM_MEMORY_MB:-}}"
VM_CORES="${VM_CORES:-}"
VM_BRIDGE="${VM_BRIDGE:-${PVE_BRIDGE:-vmbr0}}"
VM_MAC="${VM_MAC:-${PVE_MACADDR:-}}"
VM_IP_CIDR="${VM_IP_CIDR:-}"
VM_GATEWAY="${VM_GATEWAY:-}"
VM_DNS="${VM_DNS:-9.9.9.9}"
VM_SEARCH_DOMAIN="${VM_SEARCH_DOMAIN:-rfc1918.host}"
VM_STORAGE="${VM_STORAGE:-${PVE_STORAGE:-local-zfs}}"
SOURCE_QCOW="${SOURCE_QCOW:-}"
NETBOX_ROLE="${NETBOX_ROLE:-}"
VM_DESCRIPTION="${VM_DESCRIPTION:-Stage4/Stage5 service VM; stage5_role=${NETBOX_ROLE}}"
VM_CPU="${VM_CPU:-host}"
VM_OSTYPE="${VM_OSTYPE:-l26}"
VM_SCSIHW="${VM_SCSIHW:-virtio-scsi-single}"
VM_MACHINE="${VM_MACHINE:-q35}"
VM_BIOS="${VM_BIOS:-}"
VM_EFI_STORAGE="${VM_EFI_STORAGE:-${VM_STORAGE}}"
VM_EFI_SIZE="${VM_EFI_SIZE:-1}"
VM_EFI_TYPE="${VM_EFI_TYPE:-4m}"
VM_EFI_PRE_ENROLLED_KEYS="${VM_EFI_PRE_ENROLLED_KEYS:-0}"
VM_ENABLE_EFIDISK="${VM_ENABLE_EFIDISK:-auto}"
VM_DISK_SIZE="${VM_DISK_SIZE:-}"
VM_SERIAL0="${VM_SERIAL0:-socket}"
VM_VGA="${VM_VGA:-serial0}"
VM_EXTRA_NETS="${VM_EXTRA_NETS:-}"
VM_HOSTPCI_DEVICES="${VM_HOSTPCI_DEVICES:-}"
VM_CIUSER="${VM_CIUSER:-root}"
VM_ENABLE_CLOUDINIT="${VM_ENABLE_CLOUDINIT:-1}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"
PROXMOX_APPLY="${PROXMOX_APPLY:-0}"
PROXMOX_REPLACE="${PROXMOX_REPLACE:-0}"
PROXMOX_START_AFTER_CREATE="${PROXMOX_START_AFTER_CREATE:-0}"
DRY_RUN=1

usage() {
  cat <<'EOF'
Usage: proxmox-create-stage4-service-vm.sh [--dry-run|--apply]

Creates a Proxmox VM from an existing Stage4/Stage5 QCOW image. Default mode is
dry-run. Live execution requires both --apply and PROXMOX_APPLY=1.

Required environment:
  VMID
  VM_NAME
  VM_MEMORY_MIB
  VM_CORES
  VM_BRIDGE
  VM_MAC
  VM_IP_CIDR
  VM_GATEWAY
  VM_STORAGE
  SOURCE_QCOW
  NETBOX_ROLE

Optional firmware:
  VM_BIOS=ovmf
  VM_ENABLE_EFIDISK=auto|1|0
  VM_EFI_STORAGE
  VM_EFI_SIZE
  VM_EFI_TYPE
  VM_EFI_PRE_ENROLLED_KEYS

Optional workstation/direct-path devices:
  VM_SERIAL0=socket
  VM_VGA=serial0|none|std|qxl|virtio
  VM_EXTRA_NETS='net1=virtio=MAC,bridge=BRIDGE[,tag=VLAN]'
  VM_HOSTPCI_DEVICES='hostpci0=0000:01:00.0,pcie=1,x-vga=1'

Safety:
  Existing VMID aborts unless PROXMOX_REPLACE=1.
  PROXMOX_REPLACE=1 destroys the existing VMID before import.
  VM is not started unless PROXMOX_START_AFTER_CREATE=1.
EOF
}

log() {
  printf '[proxmox-create-stage4-service-vm] %s\n' "$*"
}

fail() {
  printf '[proxmox-create-stage4-service-vm] ERROR: %s\n' "$*" >&2
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
  local value="${!name:-}"
  [[ -n "${value}" ]] || fail "${name} is required"
}

validate_extra_qm_lines() {
  local var_name="$1"
  local allowed_regex="$2"
  local lines="${!var_name:-}"
  local line option value

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" == *'='* ]] || fail "${var_name} line must use option=value syntax: ${line}"
    option="${line%%=*}"
    value="${line#*=}"
    [[ "${option}" =~ ${allowed_regex} ]] || fail "invalid ${var_name} option: ${option}"
    [[ -n "${value}" ]] || fail "${var_name} option has empty value: ${option}"
  done <<< "${lines}"
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
      --help|-h)
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
  required_var VM_MEMORY_MIB
  required_var VM_CORES
  required_var VM_BRIDGE
  required_var VM_MAC
  required_var VM_IP_CIDR
  required_var VM_GATEWAY
  required_var VM_STORAGE
  required_var SOURCE_QCOW
  required_var NETBOX_ROLE

  [[ "${VMID}" =~ ^[0-9]+$ ]] || fail "VMID must be numeric: ${VMID}"
  [[ "${VM_MEMORY_MIB}" =~ ^[0-9]+$ ]] || fail "VM_MEMORY_MIB must be numeric: ${VM_MEMORY_MIB}"
  [[ "${VM_CORES}" =~ ^[0-9]+$ ]] || fail "VM_CORES must be numeric: ${VM_CORES}"
  validate_extra_qm_lines VM_EXTRA_NETS '^net[1-9][0-9]*$'
  validate_extra_qm_lines VM_HOSTPCI_DEVICES '^hostpci[0-9]+$'

  if [[ "${DRY_RUN}" == '0' && "${PROXMOX_APPLY}" != '1' ]]; then
    fail "PROXMOX_APPLY=1 is required for live --apply mode"
  fi
}

remote_line() {
  local -n args_ref=$1
  local rendered=()
  local arg

  for arg in "${args_ref[@]}"; do
    rendered+=("$(shell_quote "${arg}")")
  done
  printf '%s\n' "${rendered[*]}"
}

emit_extra_qm_set_commands() {
  local lines="$1"
  local line option value extra_cmd

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    option="${line%%=*}"
    value="${line#*=}"
    extra_cmd=(qm set "${VMID}" "--${option}" "${value}")
    remote_line extra_cmd
  done <<< "${lines}"
}

build_remote_script() {
  local create_cmd import_cmd set_scsihw_cmd set_net_cmd set_agent_cmd
  local set_serial_cmd set_vga_cmd set_boot_cmd set_desc_cmd set_ip_cmd set_dns_cmd
  local set_search_cmd set_ciuser_cmd set_ide2_cmd set_citype_cmd set_efidisk_cmd resize_cmd start_cmd
  local destroy_cmd stop_cmd
  local should_create_efidisk=0

  create_cmd=(qm create "${VMID}" --name "${VM_NAME}" --ostype "${VM_OSTYPE}" --memory "${VM_MEMORY_MIB}" --cores "${VM_CORES}" --cpu "${VM_CPU}" --machine "${VM_MACHINE}")
  if [[ -n "${VM_BIOS}" ]]; then
    create_cmd+=(--bios "${VM_BIOS}")
  fi
  import_cmd=(qm importdisk "${VMID}" "${SOURCE_QCOW}" "${VM_STORAGE}" --format qcow2)
  set_scsihw_cmd=(qm set "${VMID}" --scsihw "${VM_SCSIHW}")
  set_net_cmd=(qm set "${VMID}" --net0 "virtio=${VM_MAC},bridge=${VM_BRIDGE}")
  set_agent_cmd=(qm set "${VMID}" --agent enabled=1)
  set_serial_cmd=(qm set "${VMID}" --serial0 "${VM_SERIAL0}")
  set_vga_cmd=(qm set "${VMID}" --vga "${VM_VGA}")
  set_boot_cmd=(qm set "${VMID}" --boot order=scsi0)
  set_desc_cmd=(qm set "${VMID}" --description "${VM_DESCRIPTION}")
  set_ip_cmd=(qm set "${VMID}" --ipconfig0 "ip=${VM_IP_CIDR},gw=${VM_GATEWAY}")
  set_dns_cmd=(qm set "${VMID}" --nameserver "${VM_DNS}")
  set_search_cmd=(qm set "${VMID}" --searchdomain "${VM_SEARCH_DOMAIN}")
  set_ciuser_cmd=(qm set "${VMID}" --ciuser "${VM_CIUSER}")
  set_ide2_cmd=(qm set "${VMID}" --ide2 "${VM_STORAGE}:cloudinit")
  set_citype_cmd=(qm set "${VMID}" --citype nocloud)
  set_efidisk_cmd=(qm set "${VMID}" --efidisk0 "${VM_EFI_STORAGE}:${VM_EFI_SIZE},efitype=${VM_EFI_TYPE},pre-enrolled-keys=${VM_EFI_PRE_ENROLLED_KEYS}")
  resize_cmd=(qm resize "${VMID}" scsi0 "${VM_DISK_SIZE}")
  start_cmd=(qm start "${VMID}")
  stop_cmd=(qm stop "${VMID}")
  destroy_cmd=(qm destroy "${VMID}" --purge 1)

  if [[ "${VM_ENABLE_EFIDISK}" == '1' || ( "${VM_ENABLE_EFIDISK}" == 'auto' && "${VM_BIOS}" == 'ovmf' ) ]]; then
    should_create_efidisk=1
  fi

  cat <<EOF
set -euo pipefail

vmid=$(shell_quote "${VMID}")
source_qcow=$(shell_quote "${SOURCE_QCOW}")
ssh_key_path=""

if qm status "\${vmid}" >/dev/null 2>&1; then
  if [[ $(shell_quote "${PROXMOX_REPLACE}") == '1' ]]; then
    $(remote_line stop_cmd) || true
    $(remote_line destroy_cmd)
  else
    echo "VM \${vmid} already exists; set PROXMOX_REPLACE=1 to replace it." >&2
    exit 2
  fi
fi

if [[ ! -s "\${source_qcow}" ]]; then
  echo "SOURCE_QCOW is not readable on Proxmox host: \${source_qcow}" >&2
  exit 2
fi

$(remote_line create_cmd)
$(remote_line import_cmd)
$(remote_line set_scsihw_cmd)
imported_disk="\$(qm config "\${vmid}" | awk -F': ' '/^unused[0-9]+: / { print \$2; exit }')"
if [[ -z "\${imported_disk}" ]]; then
  echo "Unable to resolve imported disk for VM \${vmid} after importdisk." >&2
  qm config "\${vmid}" >&2
  exit 2
fi
qm set "\${vmid}" --scsi0 "\${imported_disk},discard=on,ssd=1"
$(remote_line set_net_cmd)
$(remote_line set_agent_cmd)
$(remote_line set_serial_cmd)
$(remote_line set_vga_cmd)
$(emit_extra_qm_set_commands "${VM_EXTRA_NETS}")
$(emit_extra_qm_set_commands "${VM_HOSTPCI_DEVICES}")
$(remote_line set_boot_cmd)
$(remote_line set_desc_cmd)
EOF

  if [[ "${should_create_efidisk}" == '1' ]]; then
    remote_line set_efidisk_cmd
  fi

  if [[ -n "${VM_DISK_SIZE}" ]]; then
    remote_line resize_cmd
  fi

  if [[ "${VM_ENABLE_CLOUDINIT}" == '1' ]]; then
    cat <<EOF
$(remote_line set_ide2_cmd)
$(remote_line set_citype_cmd)
$(remote_line set_ciuser_cmd)
$(remote_line set_ip_cmd)
$(remote_line set_dns_cmd)
$(remote_line set_search_cmd)
EOF
    if [[ -r "${SSH_PUBKEY_FILE}" ]]; then
      printf 'ssh_key_path=%s\n' "$(shell_quote "/tmp/${VM_NAME}.sshkey.pub")"
      printf 'if [[ -s "${ssh_key_path}" ]]; then qm set %s --sshkeys "${ssh_key_path}"; fi\n' "$(shell_quote "${VMID}")"
    fi
  fi

  if [[ "${PROXMOX_START_AFTER_CREATE}" == '1' ]]; then
    remote_line start_cmd
  fi

  printf 'qm status %s\n' "$(shell_quote "${VMID}")"
}

copy_ssh_key_if_needed() {
  [[ "${DRY_RUN}" == '0' ]] || return 0
  [[ "${VM_ENABLE_CLOUDINIT}" == '1' ]] || return 0
  [[ -r "${SSH_PUBKEY_FILE}" ]] || return 0
  scp -q "${SSH_PUBKEY_FILE}" "${PVE_HOST}:/tmp/${VM_NAME}.sshkey.pub"
}

main() {
  parse_args "$@"
  validate_inputs

  if [[ "${DRY_RUN}" == '1' ]]; then
    log "DRY RUN; no Proxmox changes will be made."
    printf 'PVE_HOST=%s\n' "${PVE_HOST}"
    build_remote_script
    return 0
  fi

  copy_ssh_key_if_needed
  build_remote_script | ssh "${PVE_HOST}" bash -s
}

main "$@"
