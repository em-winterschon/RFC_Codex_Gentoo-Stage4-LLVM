# FastMCP Infrastructure Control Plane Implementation Plan

> **For Forge/Codex:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan.

## Objective

Implement local FastMCP wrappers for infrastructure systems while preserving
auditability, safety gates, and LAN-only operation.

## Tasks

- [ ] Add tests for the common MCP safety contract.
  - Create `tests/shell/test_fastmcp_infra_control_plane.sh`.
  - Assert the docs, service metadata, and HAProxy routes mention
    `MCP_ALLOW_MUTATIONS`, vault-only tokens, and no arbitrary shell exposure.

- [ ] Add a common Python helper package for MCP wrappers.
  - Create `scripts/mcp_servers/rfc1918_mcp_common/`.
  - Implement `settings.py` for environment parsing.
  - Implement `audit.py` for operation artifact writing.
  - Implement `gates.py` for mutation gating and idempotency validation.

- [ ] Implement `netbox-mcp`.
  - Create `scripts/mcp_servers/netbox_mcp.py`.
  - Add read tools for devices, interfaces, IP addresses, prefixes, and sites.
  - Add plan tools for host, interface, service IP, and DNS/IPAM reconciliation.
  - Add apply tools only through mutation gates.

- [ ] Implement `proxmox-mcp`.
  - Create `scripts/mcp_servers/proxmox_mcp.py`.
  - Add read tools for nodes, guests, storage, networks, and VM config.
  - Add plan tools for Stage4 VM creation, snapshot, power, and migration.
  - Add apply tools only for snapshot, power action, and controlled VM creation.

- [ ] Implement `routeros-mcp`.
  - Create `scripts/mcp_servers/routeros_mcp.py`.
  - Wrap existing RouterOS command and backup scripts instead of duplicating SSH
    logic.
  - Add read tools for interface, route, VLAN, DHCP, DNS, and version state.
  - Add plan/apply tools for backups and reviewed RSC fragments.

- [ ] Implement `trac-mcp`.
  - Create `scripts/mcp_servers/trac_mcp.py`.
  - Add read tools for tickets, milestones, components, and queries.
  - Add apply tools for tickets and comments with audit artifacts.

- [ ] Implement `infra-mcp`.
  - Create `scripts/mcp_servers/infra_mcp.py`.
  - Expose roadmap, validation, and E2ET report reads.
  - Expose Ansible and validation execution only through allowlisted playbooks.

- [ ] Add service roles and HAProxy routes.
  - Extend `vm-mcp-control-plane` service definitions for each backend.
  - Add DNS/IPAM entries for `mcp-netbox`, `mcp-proxmox`, `mcp-routeros`,
    `mcp-trac`, and `mcp-infra`.
  - Disable sensitive request logging for MCP backends.

- [ ] Add Codex MCP registration materialization.
  - Create a script that emits `codex mcp add --url` commands from vaulted
    service endpoints.
  - Keep API tokens out of Codex command arguments.

- [ ] Validate live services.
  - Run unit tests and shell tests.
  - Run read-only smoke tests per backend.
  - Run one low-risk mutation per backend only after a deterministic dry-run
    plan and operator approval.
