#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CREATE_SCRIPT="${REPO_ROOT}/scripts/proxmox-create-stage4-service-vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected output to contain: ${needle}"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" != *"${needle}"* ]] || fail "expected output not to contain: ${needle}"
}

test_dry_run_emits_safe_proxmox_commands() {
  local output

  output="$(
    PVE_HOST=hasslehoff \
      VMID=1089 \
      VM_NAME=svc-container-services-01 \
      VM_MEMORY_MIB=32768 \
      VM_CORES=16 \
      VM_BRIDGE=vmbr0 \
      VM_MAC=52:54:00:12:34:78 \
      VM_IP_CIDR=10.9.8.89/24 \
      VM_GATEWAY=10.9.8.1 \
      VM_STORAGE=local-zfs \
      SOURCE_QCOW=/var/lib/vz/template/cache/svc-netbox-stage4-base.qcow2 \
      NETBOX_ROLE=container-services \
      SSH_PUBKEY_FILE=/tmp/missing-test-key.pub \
      bash "${CREATE_SCRIPT}" --dry-run
  )"

  assert_contains "${output}" "DRY RUN"
  assert_contains "${output}" "PVE_HOST=hasslehoff"
  assert_contains "${output}" "qm create 1089"
  assert_contains "${output}" "--name svc-container-services-01"
  assert_contains "${output}" "--memory 32768"
  assert_contains "${output}" "--cores 16"
  assert_contains "${output}" "qm importdisk 1089 /var/lib/vz/template/cache/svc-netbox-stage4-base.qcow2 local-zfs"
  assert_contains "${output}" "qm set 1089 --scsihw virtio-scsi-single"
  assert_contains "${output}" "qm set 1089 --net0 virtio=52:54:00:12:34:78,bridge=vmbr0"
  assert_contains "${output}" "qm set 1089 --agent enabled=1"
  assert_contains "${output}" "qm set 1089 --serial0 socket"
  assert_contains "${output}" "qm set 1089 --boot order=scsi0"
  assert_contains "${output}" "qm set 1089 --ipconfig0 ip=10.9.8.89/24,gw=10.9.8.1"
  assert_contains "${output}" "stage5_role=container-services"
  assert_not_contains "${output}" "rm -rf"
}

test_ovmf_mode_adds_efi_disk() {
  local output

  output="$(
    PVE_HOST=hasslehoff \
      VMID=1092 \
      VM_NAME=svc-test-ovmf \
      VM_MEMORY_MIB=4096 \
      VM_CORES=4 \
      VM_BRIDGE=vmbr0 \
      VM_MAC=52:54:00:12:34:92 \
      VM_IP_CIDR=172.16.99.92/24 \
      VM_GATEWAY=172.16.99.1 \
      VM_STORAGE=local-zfs \
      SOURCE_QCOW=/var/lib/vz/template/cache/test.qcow2 \
      NETBOX_ROLE=test \
      VM_BIOS=ovmf \
      SSH_PUBKEY_FILE=/tmp/missing-test-key.pub \
      bash "${CREATE_SCRIPT}" --dry-run
  )"

  assert_contains "${output}" "qm create 1092"
  assert_contains "${output}" "--bios ovmf"
  assert_contains "${output}" "qm set 1092 --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=0"
}

test_default_mode_is_dry_run() {
  local output

  output="$(
    VMID=1090 \
      VM_NAME=svc-test-default-dry-run \
      VM_MEMORY_MIB=2048 \
      VM_CORES=2 \
      VM_BRIDGE=vmbr0 \
      VM_MAC=52:54:00:12:34:90 \
      VM_IP_CIDR=172.16.99.90/24 \
      VM_GATEWAY=172.16.99.1 \
      VM_STORAGE=local-zfs \
      SOURCE_QCOW=/var/lib/vz/template/cache/test.qcow2 \
      NETBOX_ROLE=test \
      bash "${CREATE_SCRIPT}"
  )"

  assert_contains "${output}" "DRY RUN"
  assert_contains "${output}" "qm create 1090"
}

test_live_mode_requires_apply_gate() {
  local output status

  set +e
  output="$(
    PROXMOX_APPLY=0 \
      PROXMOX_LIVE=1 \
      VMID=1091 \
      VM_NAME=svc-test-live-blocked \
      VM_MEMORY_MIB=2048 \
      VM_CORES=2 \
      VM_BRIDGE=vmbr0 \
      VM_MAC=52:54:00:12:34:91 \
      VM_IP_CIDR=172.16.99.91/24 \
      VM_GATEWAY=172.16.99.1 \
      VM_STORAGE=local-zfs \
      SOURCE_QCOW=/var/lib/vz/template/cache/test.qcow2 \
      NETBOX_ROLE=test \
      bash "${CREATE_SCRIPT}" --apply 2>&1
  )"
  status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "expected apply without PROXMOX_APPLY=1 to fail"
  assert_contains "${output}" "PROXMOX_APPLY=1 is required"
}

test_imported_disk_is_resolved_from_unused_slot() {
  local output

  output="$(
    VMID=1096 \
      VM_NAME=svc-test-imported-disk \
      VM_MEMORY_MIB=2048 \
      VM_CORES=2 \
      VM_BRIDGE=vmbr0 \
      VM_MAC=52:54:00:99:10:96 \
      VM_IP_CIDR=172.16.99.96/24 \
      VM_GATEWAY=172.16.99.1 \
      VM_STORAGE=local-zfs \
      SOURCE_QCOW=/var/lib/vz/template/cache/test.qcow2 \
      NETBOX_ROLE=test \
      bash "${CREATE_SCRIPT}" --dry-run
  )"

  assert_contains "${output}" "imported_disk=\"\$(qm config \"\${vmid}\" | awk -F': ' '/^unused[0-9]+: / { print \$2; exit }')\""
  assert_contains "${output}" "qm set \"\${vmid}\" --scsi0 \"\${imported_disk},discard=on,ssd=1\""
  assert_not_contains "${output}" "qm set 1096 --scsi0 local-zfs:vm-1096-disk-0,discard=on,ssd=1"
}

test_workstation_options_emit_gpu_hostpci_and_extra_nics() {
  local output

  output="$(
    VMID=1094 \
      VM_NAME=vm-workstation-nscde-gpu01 \
      VM_MEMORY_MIB=49152 \
      VM_CORES=8 \
      VM_BRIDGE=vmbr0 \
      VM_MAC=52:54:00:99:10:94 \
      VM_IP_CIDR=172.16.99.94/24 \
      VM_GATEWAY=172.16.99.1 \
      VM_STORAGE=local-zfs \
      SOURCE_QCOW=/var/lib/vz/template/cache/gentoo-stage4-workstation.qcow2 \
      NETBOX_ROLE=workstation-nscde \
      VM_BIOS=ovmf \
      VM_VGA=none \
      VM_EXTRA_NETS=$'net1=virtio=52:54:00:99:11:94,bridge=vmbr-qlogic0,tag=1098\nnet2=virtio=52:54:00:99:12:94,bridge=vmbr-qlogic0,tag=1099' \
      VM_HOSTPCI_DEVICES=$'hostpci0=0000:01:00.0,pcie=1,x-vga=1\nhostpci1=0000:01:00.1,pcie=1' \
      SSH_PUBKEY_FILE=/tmp/missing-test-key.pub \
      bash "${CREATE_SCRIPT}" --dry-run
  )"

  assert_contains "${output}" "qm set 1094 --vga none"
  assert_contains "${output}" "qm set 1094 --net1 virtio=52:54:00:99:11:94,bridge=vmbr-qlogic0,tag=1098"
  assert_contains "${output}" "qm set 1094 --net2 virtio=52:54:00:99:12:94,bridge=vmbr-qlogic0,tag=1099"
  assert_contains "${output}" "qm set 1094 --hostpci0 0000:01:00.0,pcie=1,x-vga=1"
  assert_contains "${output}" "qm set 1094 --hostpci1 0000:01:00.1,pcie=1"
}

test_invalid_extra_vm_option_is_rejected() {
  local output status

  set +e
  output="$(
    VMID=1095 \
      VM_NAME=vm-invalid-extra-option \
      VM_MEMORY_MIB=2048 \
      VM_CORES=2 \
      VM_BRIDGE=vmbr0 \
      VM_MAC=52:54:00:99:10:95 \
      VM_IP_CIDR=172.16.99.95/24 \
      VM_GATEWAY=172.16.99.1 \
      VM_STORAGE=local-zfs \
      SOURCE_QCOW=/var/lib/vz/template/cache/test.qcow2 \
      NETBOX_ROLE=test \
      VM_EXTRA_NETS=$'args=-machine hacked' \
      bash "${CREATE_SCRIPT}" --dry-run 2>&1
  )"
  status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "expected invalid extra VM option to fail"
  assert_contains "${output}" "invalid VM_EXTRA_NETS option: args"
}

test_dry_run_emits_safe_proxmox_commands
test_ovmf_mode_adds_efi_disk
test_default_mode_is_dry_run
test_live_mode_requires_apply_gate
test_imported_disk_is_resolved_from_unused_slot
test_workstation_options_emit_gpu_hostpci_and_extra_nics
test_invalid_extra_vm_option_is_rejected

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
