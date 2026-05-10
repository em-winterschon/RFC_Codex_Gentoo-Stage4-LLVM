#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/proxmox-materialize-gentoo-openrc-static-net.sh"

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

test_dry_run_emits_offline_openrc_network_materialization() {
  local output

  output="$(
    PVE_HOST=hasslehoff \
      VMID=1064 \
      VM_NAME=obs-sun99-prometheus-099064 \
      VM_IP_CIDR=172.16.99.64/24 \
      VM_GATEWAY=172.16.99.1 \
      VM_BOOT_DISK=local-zfs:vm-1064-disk-0 \
      PROXMOX_START_AFTER_CONFIG=1 \
      bash "${SCRIPT}" --dry-run
  )"

  assert_contains "${output}" "PVE_HOST=hasslehoff"
  assert_contains "${output}" "vmid=1064"
  assert_contains "${output}" "vm_name=obs-sun99-prometheus-099064"
  assert_contains "${output}" "vm_ip_cidr=172.16.99.64/24"
  assert_contains "${output}" "vm_boot_disk=local-zfs:vm-1064-disk-0"
  assert_contains "${output}" 'qm snapshot "${vmid}" "${snap}"'
  assert_contains "${output}" 'qm stop "${vmid}" --timeout 60'
  assert_contains "${output}" 'sgdisk -e "${disk}"'
  assert_contains "${output}" 'parted -s "${disk}" resizepart 2 100%'
  assert_contains "${output}" 'e2fsck -fy "${part}"'
  assert_contains "${output}" 'resize2fs "${part}"'
  assert_contains "${output}" 'config_${vm_net_service}="${vm_ip_cidr}"'
  assert_contains "${output}" 'routes_${vm_net_service}="default via ${vm_gateway}"'
  assert_contains "${output}" 'rm -f "${mnt}/etc/runlevels/default/dhcpcd"'
  assert_contains "${output}" 'ln -sfn "/etc/init.d/net.${vm_net_service}"'
  assert_contains "${output}" 'qm start "${vmid}"'
  assert_not_contains "${output}" "rm -rf"
}

test_live_mode_requires_apply_gate() {
  local output status

  set +e
  output="$(
    PROXMOX_APPLY=0 \
      VMID=1064 \
      VM_NAME=obs-sun99-prometheus-099064 \
      VM_IP_CIDR=172.16.99.64/24 \
      VM_GATEWAY=172.16.99.1 \
      bash "${SCRIPT}" --apply 2>&1
  )"
  status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "expected apply without PROXMOX_APPLY=1 to fail"
  assert_contains "${output}" "PROXMOX_APPLY=1 is required"
}

test_required_inputs_are_validated() {
  local output status

  set +e
  output="$(
    VMID=not-a-number \
      VM_NAME=obs-sun99-prometheus-099064 \
      VM_IP_CIDR=172.16.99.64/24 \
      VM_GATEWAY=172.16.99.1 \
      bash "${SCRIPT}" --dry-run 2>&1
  )"
  status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "expected invalid VMID to fail"
  assert_contains "${output}" "VMID must be numeric"
}

test_dry_run_emits_offline_openrc_network_materialization
test_live_mode_requires_apply_gate
test_required_inputs_are_validated

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
