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

test_dry_run_emits_safe_proxmox_commands
test_ovmf_mode_adds_efi_disk
test_default_mode_is_dry_run
test_live_mode_requires_apply_gate

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
