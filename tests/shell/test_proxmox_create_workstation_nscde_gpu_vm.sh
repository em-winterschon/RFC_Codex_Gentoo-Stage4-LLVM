#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSTATION_SCRIPT="${REPO_ROOT}/scripts/proxmox-create-workstation-nscde-gpu-vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected output to contain: ${needle}"
}

output="$(
  SSH_PUBKEY_FILE=/tmp/missing-test-key.pub \
  bash "${WORKSTATION_SCRIPT}" --dry-run
)"

assert_contains "${output}" "qm create 1094"
assert_contains "${output}" "--name vm-workstation-nscde-gpu01"
assert_contains "${output}" "--memory 24576"
assert_contains "${output}" "--cores 8"
assert_contains "${output}" "qm importdisk 1094 /var/lib/vz/template/cache/vm-workstation-nscde.qcow2 local-zfs"
assert_contains "${output}" "qm set 1094 --net0 virtio=52:54:00:99:10:94,bridge=vmbr0"
assert_contains "${output}" "qm set 1094 --net1 virtio=52:54:00:99:11:94,bridge=vmbr-qlogic0,tag=1098"
assert_contains "${output}" "qm set 1094 --net2 virtio=52:54:00:99:12:94,bridge=vmbr-qlogic0,tag=1099"
assert_contains "${output}" "qm set 1094 --vga qxl"
assert_contains "${output}" "qm set 1094 --hostpci0 0000:01:00.0,pcie=1"
assert_contains "${output}" "qm set 1094 --hostpci1 0000:01:00.1,pcie=1"
assert_contains "${output}" "stage5_role=workstation-nscde"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
