#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_dir() {
  [[ -d "$1" ]] || fail "missing directory: $1"
}

require_grep() {
  local pattern=$1
  local file=$2
  grep -q -- "${pattern}" "${file}" || fail "missing pattern '${pattern}' in ${file}"
}

require_dir "${ANSIBLE_ROOT}/roles/trac_server"
require_file "${ANSIBLE_ROOT}/roles/trac_server/defaults/main.yml"
require_file "${ANSIBLE_ROOT}/roles/trac_server/tasks/main.yml"
require_file "${ANSIBLE_ROOT}/roles/trac_server/templates/trac.ini.j2"
require_file "${ANSIBLE_ROOT}/roles/trac_server/templates/trac.openrc.j2"
require_file "${ANSIBLE_ROOT}/roles/trac_server/templates/trac-workflow.ini.j2"
require_file "${ANSIBLE_ROOT}/roles/trac_server/templates/trac-custom-fields.ini.j2"

require_dir "${ANSIBLE_ROOT}/roles/trac_mcp_bridge"
require_file "${ANSIBLE_ROOT}/roles/trac_mcp_bridge/defaults/main.yml"
require_file "${ANSIBLE_ROOT}/roles/trac_mcp_bridge/tasks/main.yml"
require_file "${ANSIBLE_ROOT}/roles/trac_mcp_bridge/templates/trac-mcp.env.j2"
require_file "${ANSIBLE_ROOT}/roles/trac_mcp_bridge/templates/trac-mcp.openrc.j2"

require_file "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"
require_file "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.metadata.yml"
require_file "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-trac-service.packages"

require_grep '^www-apps/trac$' "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-trac-service.packages"
require_grep '^dev-db/postgresql$' "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-trac-service.packages"
require_grep '^net-proxy/haproxy$' "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-trac-service.packages"
require_grep '^dev-vcs/git$' "${ANSIBLE_ROOT}/profile-package-lists/stage5-virtual-host-trac-service.packages"

require_grep 'profile_id: vm-trac-service' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"
require_grep 'trac_server:' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"
require_grep 'trac_mcp_bridge:' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"
require_grep 'name: trac-http' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"
require_grep 'github_pr' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"
require_grep 'codeberg_ref' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"
require_grep 'netbox_object' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"
require_grep 'slo_validation' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.yml"

require_grep 'work_management_authority: trac' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.metadata.yml"
require_grep 'repository_rename_recommendation: rfc1918-platform-fabric' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.metadata.yml"
require_grep 'default_exposure: local-management-only' "${ANSIBLE_ROOT}/profile-definitions/vm-trac-service.metadata.yml"

require_grep 'intake -> ready' "${ANSIBLE_ROOT}/roles/trac_server/templates/trac-workflow.ini.j2"
require_grep 'review -> validation' "${ANSIBLE_ROOT}/roles/trac_server/templates/trac-workflow.ini.j2"
require_grep 'validation -> done' "${ANSIBLE_ROOT}/roles/trac_server/templates/trac-workflow.ini.j2"
require_grep 'github_usage = linked-pr-surface' "${ANSIBLE_ROOT}/roles/trac_server/templates/trac.ini.j2"
require_grep 'codeberg_usage = mirror-ref-surface' "${ANSIBLE_ROOT}/roles/trac_server/templates/trac.ini.j2"
require_grep 'TRAC_MCP_TOKEN="${{{ resolved_trac_mcp_bridge.token_vault_var }}}"' "${ANSIBLE_ROOT}/roles/trac_mcp_bridge/templates/trac-mcp.env.j2"

require_grep 'trac_server' "${ANSIBLE_ROOT}/playbooks/install.yml"
require_grep 'trac_mcp_bridge' "${ANSIBLE_ROOT}/playbooks/install.yml"
require_grep 'resolved_profile_trac_server' "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml"
require_grep 'resolved_profile_trac_mcp_bridge' "${ANSIBLE_ROOT}/roles/preflight/tasks/main.yml"
require_grep 'gentoo_profile_definition.trac_server' "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml"
require_grep 'gentoo_profile_definition.trac_mcp_bridge' "${ANSIBLE_ROOT}/roles/preflight/tasks/load_profile_definition.yml"
require_grep 'trac_server' "${ANSIBLE_ROOT}/vars/install_sequences.yml"
require_grep 'trac_mcp_bridge' "${ANSIBLE_ROOT}/vars/install_sequences.yml"

require_file "${REPO_ROOT}/docs/PROJECT-MANAGEMENT-CONTROL-PLANE.md"
require_file "${REPO_ROOT}/docs/wiki/Project-Management-Control-Plane.md"
require_grep 'rfc1918-platform-fabric' "${REPO_ROOT}/docs/PROJECT-MANAGEMENT-CONTROL-PLANE.md"
require_grep 'GitHub and Codeberg remain Git remotes' "${REPO_ROOT}/docs/PROJECT-MANAGEMENT-CONTROL-PLANE.md"

printf 'PASS: %s\n' "$(basename "${BASH_SOURCE[0]}")"
