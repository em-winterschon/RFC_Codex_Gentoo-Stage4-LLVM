#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -qE "${pattern}" "${file}"
}

test -f "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md"
test -f "${REPO_ROOT}/docs/TRAC-MCP-EVALUATION.md"
test -f "${REPO_ROOT}/docs/wiki/MCP-Candidate-Audit.md"
test -f "${REPO_ROOT}/docs/wiki/Trac-MCP-Evaluation.md"
test -f "${REPO_ROOT}/docs/MORNING-SITREP-NEXT-STEPS-2026-05-08.md"
test -f "${REPO_ROOT}/docs/wiki/Morning-SITREP-Next-Steps-2026-05-08.md"

for candidate in \
  huggingface \
  trac \
  netbox \
  grafana \
  jenkins \
  proxmox \
  context7 \
  kubernetes-openshift; do
  assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" "\`${candidate}\`"
done

assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" 'https://huggingface.co/docs/hub/en/hf-mcp-server'
assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" 'https://github.com/netboxlabs/netbox-mcp-server'
assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" 'https://github.com/grafana/mcp-grafana'
assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" 'https://github.com/jenkinsci/mcp-server-plugin'
assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" 'https://github.com/nerpatech/trac-mcp-server'
assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" 'read-only smoke test'
assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" 'quarantine'
assert_file_contains "${REPO_ROOT}/docs/MCP-CANDIDATE-AUDIT.md" 'deferred'

assert_file_contains "${REPO_ROOT}/docs/TRAC-MCP-EVALUATION.md" 'Pinned source commit'
assert_file_contains "${REPO_ROOT}/docs/TRAC-MCP-EVALUATION.md" '6dc712eed9045411034488cdd3a6e7de2d131ad0'
assert_file_contains "${REPO_ROOT}/docs/TRAC-MCP-EVALUATION.md" 'TICKET_ADMIN'
assert_file_contains "${REPO_ROOT}/docs/TRAC-MCP-EVALUATION.md" 'ticket_batch_delete'
assert_file_contains "${REPO_ROOT}/docs/TRAC-MCP-EVALUATION.md" 'wiki_delete'
assert_file_contains "${REPO_ROOT}/docs/TRAC-MCP-EVALUATION.md" 'read-only wrapper'
assert_file_contains "${REPO_ROOT}/docs/TRAC-MCP-EVALUATION.md" 'do not deploy with write-capable Trac credentials'

assert_file_contains "${REPO_ROOT}/docs/MORNING-SITREP-NEXT-STEPS-2026-05-08.md" 'MORN-001'
assert_file_contains "${REPO_ROOT}/docs/MORNING-SITREP-NEXT-STEPS-2026-05-08.md" 'MORN-008'
assert_file_contains "${REPO_ROOT}/docs/MORNING-SITREP-NEXT-STEPS-2026-05-08.md" 'Codeberg'
assert_file_contains "${REPO_ROOT}/docs/MORNING-SITREP-NEXT-STEPS-2026-05-08.md" 'base system services'
assert_file_contains "${REPO_ROOT}/docs/MORNING-SITREP-NEXT-STEPS-2026-05-08.md" 'centralized AAA'

assert_file_contains "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md" 'MCP-001'
assert_file_contains "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md" 'PM-001'
assert_file_contains "${REPO_ROOT}/docs/ROADMAP-AND-TODO.md" 'MORN-001'
assert_file_contains "${REPO_ROOT}/docs/wiki/_Sidebar.md" 'MCP Candidate Audit'
assert_file_contains "${REPO_ROOT}/docs/wiki/_Sidebar.md" 'Trac MCP Evaluation'

printf 'PASS: %s\n' "$(basename "$0")"
