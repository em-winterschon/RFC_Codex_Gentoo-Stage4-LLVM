#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PROFILE_DIR="${ANSIBLE_ROOT}/profile-definitions"
PACKAGE_LIST_DIR="${ANSIBLE_ROOT}/profile-package-lists"
ROLE_DIR="${ANSIBLE_ROOT}/roles/mcp_control_plane"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -qE "${pattern}" "${file}"
}

test -f "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md"
test -f "${REPO_ROOT}/docs/wiki/MCP-Control-Plane.md"
test -f "${REPO_ROOT}/docs/superpowers/specs/2026-05-08-mcp-control-plane-design.md"
test -f "${REPO_ROOT}/docs/superpowers/plans/2026-05-08-mcp-control-plane.md"

test -f "${PROFILE_DIR}/vm-mcp-control-plane.yml"
test -f "${PROFILE_DIR}/vm-mcp-control-plane.metadata.yml"
test -f "${PACKAGE_LIST_DIR}/stage5-virtual-host-mcp-control-plane.packages"

assert_file_contains "${PROFILE_DIR}/vm-mcp-control-plane.yml" '^gentoo_profile_definition:'
assert_file_contains "${PROFILE_DIR}/vm-mcp-control-plane.yml" 'mcp_control_plane:'
assert_file_contains "${PROFILE_DIR}/vm-mcp-control-plane.yml" 'default_mode: read-only'
assert_file_contains "${PROFILE_DIR}/vm-mcp-control-plane.yml" 'write_gate: explicit-change-control'
assert_file_contains "${PROFILE_DIR}/vm-mcp-control-plane.metadata.yml" '^gentoo_system_profile_metadata:'
assert_file_contains "${PACKAGE_LIST_DIR}/stage5-virtual-host-mcp-control-plane.packages" '^dev-python/pyyaml$'

test -f "${ROLE_DIR}/defaults/main.yml"
test -f "${ROLE_DIR}/tasks/main.yml"
test -f "${ROLE_DIR}/templates/candidate-registry.yml.j2"
test -f "${ROLE_DIR}/templates/promotion-policy.yml.j2"
test -f "${ROLE_DIR}/templates/mcp-control-plane.env.j2"

assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'mcp_control_plane_default_candidates:'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'huggingface'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'trac'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'netbox'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'grafana'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'jenkins'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'proxmox'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'context7'
assert_file_contains "${ROLE_DIR}/defaults/main.yml" 'allowed_operations'

assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'resolved_profile_mcp_control_plane'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'mcp-control-plane'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'candidate-registry.yml'
assert_file_contains "${ROLE_DIR}/tasks/main.yml" 'promotion-policy.yml'

assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml" 'resolved_profile_mcp_control_plane'
assert_file_contains "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml" 'mcp_control_plane'
assert_file_contains "${ANSIBLE_ROOT}/playbooks/install.yml" 'mcp_control_plane'
assert_file_contains "${ANSIBLE_ROOT}/vars/install_sequences.yml" 'mcp_control_plane'

assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" 'Discovery -> audit -> pin -> sandbox -> smoke test -> vault-backed auth -> audit logging -> gated writes'
assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" 'Default mode is read-only'
assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" 'https://huggingface.co/settings/mcp'
assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" 'https://github.com/grafana/mcp-grafana'
assert_file_contains "${REPO_ROOT}/docs/MCP-CONTROL-PLANE.md" 'https://github.com/jenkinsci/mcp-server-plugin'
assert_file_contains "${REPO_ROOT}/docs/wiki/MCP-Control-Plane.md" 'MCP Control Plane'

printf 'PASS: %s\n' "$(basename "$0")"
