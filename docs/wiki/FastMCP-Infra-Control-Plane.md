# FastMCP Infrastructure Control Plane

## Purpose

This document promotes the MCP control-plane scaffold into concrete, local,
LAN-only MCP services for infrastructure operations. The target is not a raw
shell-execution surface. Each service exposes a small, allowlisted set of
inspection, planning, and explicitly gated mutation tools.

FastMCP is the preferred implementation path for custom wrappers because it can
run normal Python tool functions as MCP servers over stdio or HTTP, and the HTTP
transport can sit cleanly behind the existing HAProxy service VIP. FastMCP's
OpenAPI conversion is useful for prototyping, but production infrastructure
tools should remain curated and allowlisted rather than mirroring every backend
API endpoint.

References:

- https://gofastmcp.com/getting-started/quickstart
- https://gofastmcp.com/integrations/openapi
- https://gofastmcp.com/apps/generative
- https://nginxui.com/guide/mcp

## Service Model

All services run on the `vm-mcp-control-plane` profile unless a specific backend
requires stronger isolation. HAProxy terminates TLS with the private CA and
routes each MCP service by hostname and `/mcp` path.

| Service | Initial Hostname | Backend | First Status |
| --- | --- | --- | --- |
| Nginx-UI MCP | `nginx-ui.rfc1918.host` | Native Nginx-UI `/mcp` endpoint | Validate and keep native |
| NetBox MCP | `mcp-netbox.rfc1918.host` | FastMCP Python wrapper | Implement first |
| Proxmox MCP | `mcp-proxmox.rfc1918.host` | FastMCP Python wrapper | Implement second |
| RouterOS MCP | `mcp-routeros.rfc1918.host` | FastMCP wrapper over existing RouterOS scripts | Implement third |
| Trac MCP | `mcp-trac.rfc1918.host` | FastMCP wrapper over Trac XML-RPC/REST | Implement after PM bootstrap |
| Internal Infra MCP | `mcp-infra.rfc1918.host` | FastMCP wrapper over repo playbooks and validators | Implement after backend wrappers |

## Safety Contract

- Read tools are safe by default and may query inventory, state, and health.
- Plan tools return proposed changes, diffs, and validation steps without
  mutating external systems.
- Apply tools require `MCP_ALLOW_MUTATIONS=true`, a backend-specific vaulted
  token, an idempotency key, and an audit comment.
- Apply tools must prefer existing repo scripts and Ansible playbooks over ad
  hoc command execution.
- No MCP service may expose arbitrary shell, arbitrary Python eval, unrestricted
  HTTP proxying, or broad OpenAPI-to-tool conversion in production.
- Every mutation must write an audit artifact to the repo or an append-only
  operations log before or immediately after backend apply.

## Backend Tool Boundaries

### NetBox MCP

Read tools:

- `netbox_get_device`
- `netbox_get_ip_address`
- `netbox_search_inventory`
- `netbox_validate_dns_ipam`

Plan tools:

- `netbox_plan_host_record`
- `netbox_plan_interface_record`
- `netbox_plan_service_ip`

Apply tools:

- `netbox_apply_host_record`
- `netbox_apply_dns_ipam_reconciliation`

### Proxmox MCP

Read tools:

- `pve_list_nodes`
- `pve_list_vms`
- `pve_get_vm_config`
- `pve_get_storage_status`

Plan tools:

- `pve_plan_stage4_vm`
- `pve_plan_snapshot`
- `pve_plan_migration`

Apply tools:

- `pve_apply_snapshot`
- `pve_apply_stage4_vm`
- `pve_apply_vm_power_action`

### RouterOS MCP

Read tools:

- `routeros_get_identity`
- `routeros_get_interfaces`
- `routeros_get_routes`
- `routeros_get_vlans`

Plan tools:

- `routeros_plan_config_backup`
- `routeros_plan_dns_record`
- `routeros_plan_vip_route`

Apply tools:

- `routeros_apply_config_backup`
- `routeros_apply_dns_record`
- `routeros_apply_rsc_fragment`

### Trac MCP

Read tools:

- `trac_get_ticket`
- `trac_search_tickets`
- `trac_get_milestone`

Plan tools:

- `trac_plan_ticket`
- `trac_plan_dependency_link`
- `trac_plan_milestone`

Apply tools:

- `trac_apply_ticket`
- `trac_apply_comment`
- `trac_apply_milestone`

### Internal Infra MCP

Read tools:

- `infra_get_roadmap_item`
- `infra_get_service_status`
- `infra_get_validation_manifest`

Plan tools:

- `infra_plan_ansible_run`
- `infra_plan_dns_change`
- `infra_plan_e2et_run`

Apply tools:

- `infra_apply_ansible_playbook`
- `infra_apply_validation_run`

## Deployment Requirements

- Private CA certificate and service certificate material available through
  Ansible Vault.
- DNS records for each MCP hostname in `rfc1918.host`.
- HAProxy routes for HTTP MCP endpoints with sensitive query logging disabled.
- Service tokens stored in Ansible Vault and materialized as root-readable files
  or environment files with `0600` permissions.
- Codex MCP registrations should use HTTPS URLs and never embed tokens in
  command arguments or logged URLs.

## Generative UI Position

FastMCP Generative UI is useful for operator dashboards and ad hoc read-only
visualizations after the backend wrappers are stable. It should not be used for
first-pass mutation workflows because the generated UI executes dynamic code and
adds an unnecessary moving part to already sensitive infrastructure changes.

## Validation Gates

Before an MCP backend is marked live:

- Unit tests must validate tool schemas and mutation gating.
- Shell tests must confirm service role metadata, HAProxy routes, and vault-only
  secret references.
- A read-only smoke test must run against the live backend.
- A dry-run planning test must produce a deterministic diff.
- A single low-risk apply must be executed with an idempotency key and an audit
  artifact.
