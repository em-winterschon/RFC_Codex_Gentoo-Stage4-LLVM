#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
INVENTORY="${ANSIBLE_ROOT}/inventories/local-network/hosts.yml"
RUNBOOK="${REPO_ROOT}/docs/THOR-AGX-INFERENCE-READINESS.md"
PLAYBOOK_DOC="${REPO_ROOT}/docs/INFERENCE-SERVICE-PLAYBOOKS.md"
APT_EVIDENCE="${REPO_ROOT}/docs/evidence/thor-apt-actions-cleanup-virts.2026-05-26.log"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_fixed() {
  local pattern=$1
  local file=$2
  grep -Fq -- "${pattern}" "${file}" || fail "missing text ${pattern} in ${file}"
}

require_absent_fixed() {
  local pattern=$1
  local file=$2
  if grep -Fq -- "${pattern}" "${file}"; then
    fail "unexpected text ${pattern} in ${file}"
  fi
}

require_file "${INVENTORY}"
require_fixed 'agx_rfc99_bunnydev_099034:' "${INVENTORY}"
require_fixed 'ansible_host: 172.16.99.34' "${INVENTORY}"
require_fixed 'fqdn: agx-rfc99-bunnydev.rfc1918.host' "${INVENTORY}"
require_fixed 'ollama_servers:' "${INVENTORY}"
require_fixed 'open_webui_servers:' "${INVENTORY}"
require_fixed 'inference_service_container_engine: podman' "${INVENTORY}"
require_fixed 'inference_service_accelerator: nvidia' "${INVENTORY}"
require_fixed 'inference_service_manager: systemd' "${INVENTORY}"
require_fixed 'nvidia.com/gpu=all' "${INVENTORY}"
require_fixed 'thor_apt_action_log: docs/evidence/thor-apt-actions-cleanup-virts.2026-05-26.log' "${INVENTORY}"
require_fixed 'thor_package_holds:' "${INVENTORY}"
require_fixed 'systemd-container' "${INVENTORY}"
require_fixed 'thor_package_purges:' "${INVENTORY}"
require_fixed 'snapd' "${INVENTORY}"
require_fixed 'thor_data_plane_bridges:' "${INVENTORY}"
require_fixed 'br-podman0' "${INVENTORY}"
require_fixed 'br-kata0' "${INVENTORY}"
require_fixed 'bond-podman0' "${INVENTORY}"
require_fixed 'bond-kata0' "${INVENTORY}"
require_fixed 'mgbe0_0' "${INVENTORY}"
require_fixed 'mgbe3_0' "${INVENTORY}"
require_absent_fixed 'inference_service_container_engine: docker' "${INVENTORY}"
require_absent_fixed 'inference_service_allow_docker_exception' "${INVENTORY}"

require_file "${RUNBOOK}"
require_fixed 'Podman is installed and validated on Thor.' "${RUNBOOK}"
require_fixed 'nvidia.com/gpu=all' "${RUNBOOK}"
require_fixed '/etc/cdi/nvidia.yaml' "${RUNBOOK}"
require_fixed 'Docker remains masked and inactive.' "${RUNBOOK}"
require_fixed 'Package Action Ledger' "${RUNBOOK}"
require_fixed 'thor-apt-actions-cleanup-virts.2026-05-26.log' "${RUNBOOK}"
require_fixed 'snapd was purged.' "${RUNBOOK}"
require_fixed 'systemd-container is held.' "${RUNBOOK}"
require_fixed 'OVS userspace LACP fallback' "${RUNBOOK}"
require_fixed 'CONFIG_BONDING is not set' "${RUNBOOK}"
require_fixed 'CONFIG_OPENVSWITCH is not set' "${RUNBOOK}"
require_fixed 'br-podman0' "${RUNBOOK}"
require_fixed 'br-kata0' "${RUNBOOK}"

require_file "${PLAYBOOK_DOC}"
require_fixed 'Thor AGX now uses Podman plus NVIDIA CDI.' "${PLAYBOOK_DOC}"
require_fixed 'inference_service_container_engine: podman' "${PLAYBOOK_DOC}"
require_fixed 'inference_service_accelerator: nvidia' "${PLAYBOOK_DOC}"
require_absent_fixed 'temporary until Podman/CDI is validated' "${PLAYBOOK_DOC}"

require_file "${APT_EVIDENCE}"
require_fixed 'apt-mark hold systemd-container' "${APT_EVIDENCE}"
require_fixed 'apt purge snapd' "${APT_EVIDENCE}"
require_fixed 'apt install podman-toolbox python3-podman podman-remote podman-compose' "${APT_EVIDENCE}"
require_fixed 'apt install virtiofsd' "${APT_EVIDENCE}"
require_fixed 'apt install openvswitch-switch python3-openvswitch' "${APT_EVIDENCE}"

printf 'PASS: %s\n' "$(basename "$0")"
