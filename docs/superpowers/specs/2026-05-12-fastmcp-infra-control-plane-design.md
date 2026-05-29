# FastMCP Infrastructure Control Plane Design

## Goal

Build local MCP services that let Codex and other approved operators inspect,
plan, and safely apply infrastructure changes through small, auditable tool
surfaces.

## Current State

- `vm-mcp-control-plane` exists as the logical profile for MCP services.
- Nginx-UI has a native `/mcp` path in the existing service scaffold.
- Context7 and OpenAI developer docs are the only active Codex MCP
  registrations restored in the local Codex config.
- Trac, Nginx-UI, NetBox, RouterOS, Proxmox, and internal-infra MCPs are design
  targets, not current Codex MCP registrations.

## Design Decisions

- Use FastMCP for custom Python service wrappers.
- Keep Nginx-UI on its native MCP endpoint instead of wrapping it.
- Prefer curated tool functions over generated OpenAPI mirrors for production.
- Use OpenAPI conversion only for discovery prototypes and mark those services
  non-production until every exposed operation is reviewed.
- Keep every mutation behind `MCP_ALLOW_MUTATIONS`, a vaulted backend token, an
  idempotency key, and an audit artifact.
- Run services over HTTPS through HAProxy once private CA issuance is available.

## Service Promotion Order

1. Validate Nginx-UI native MCP through HAProxy.
2. Implement `netbox-mcp` because IPAM/DCIM correctness drives every later
   service.
3. Implement `proxmox-mcp` for VM inspection, snapshot planning, and controlled
   VM creation.
4. Implement `routeros-mcp` for read state, config backup, DNS/VIP plans, and
   explicitly gated RSC fragments.
5. Implement `trac-mcp` after project-management policy settles.
6. Implement `infra-mcp` as an orchestration facade over repo playbooks,
   validators, and E2ET reports.

## Non-Goals

- Do not expose arbitrary shell execution.
- Do not expose unrestricted backend REST APIs as MCP tools.
- Do not depend on external hosted MCP gateways for LAN-critical automation.
- Do not let generated UI paths perform infrastructure mutation in the first
  release.

## Risks

- MCP tools can become too broad and bypass normal review discipline.
- Backend API tokens can leak through command arguments, query strings, logs, or
  tool output.
- A generated OpenAPI MCP can expose destructive methods unintentionally.
- HAProxy and service logs may capture sensitive query parameters unless
  templates explicitly suppress them.

## Mitigations

- Review tool allowlists per backend before live registration.
- Keep tokens in Vault and materialized files, not Codex config arguments.
- Use deterministic plan-before-apply output for every mutation.
- Add tests that fail if production services expose broad OpenAPI mode.
- Add operation logs to repo documentation or an append-only datastore.
