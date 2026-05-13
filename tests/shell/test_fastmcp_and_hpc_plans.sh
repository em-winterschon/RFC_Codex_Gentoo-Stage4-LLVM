#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

fastmcp_doc="${REPO_ROOT}/docs/FASTMCP-INFRA-CONTROL-PLANE.md"
fastmcp_spec="${REPO_ROOT}/docs/superpowers/specs/2026-05-12-fastmcp-infra-control-plane-design.md"
fastmcp_plan="${REPO_ROOT}/docs/superpowers/plans/2026-05-12-fastmcp-infra-control-plane.md"
hpc_doc="${REPO_ROOT}/docs/HPC-WORKLOAD-SCHEDULER-PLAN.md"
roadmap="${REPO_ROOT}/docs/ROADMAP-AND-TODO.md"

for path in \
  "${fastmcp_doc}" \
  "${fastmcp_spec}" \
  "${fastmcp_plan}" \
  "${hpc_doc}" \
  "${REPO_ROOT}/docs/wiki/FastMCP-Infra-Control-Plane.md" \
  "${REPO_ROOT}/docs/wiki/HPC-Workload-Scheduler-Plan.md"; do
  test -f "${path}"
done

grep -q "MCP_ALLOW_MUTATIONS" "${fastmcp_doc}"
grep -q "mcp-netbox.rfc1918.host" "${fastmcp_doc}"
grep -q "No MCP service may expose arbitrary shell" "${fastmcp_doc}"
grep -q "FastMCP" "${fastmcp_spec}"
grep -q "scripts/mcp_servers/netbox_mcp.py" "${fastmcp_plan}"
grep -q "SLURM is the best first scheduler" "${hpc_doc}"
grep -q "HTCondor remains valuable" "${hpc_doc}"
grep -q "CVMFS" "${hpc_doc}"
grep -q "MCP-004" "${roadmap}"
grep -q "HPC-002" "${roadmap}"
grep -q "FastMCP Infra Control Plane" "${REPO_ROOT}/docs/wiki/_Sidebar.md"
grep -q "HPC Workload Scheduler Plan" "${REPO_ROOT}/docs/wiki/_Sidebar.md"

printf 'PASS: %s\n' "$(basename "$0")"
