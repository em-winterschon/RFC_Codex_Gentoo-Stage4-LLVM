# Project Management Control Plane

Trac is the planned authoritative work-management plane for RFC1918
infrastructure automation. It owns tickets, milestones, wiki planning, Kanban
workflow, change-control notes, dependency tracking, and operational
acceptance data.

GitHub and Codeberg remain Git remotes. Pull requests, mirror refs, and commit
links are attached to Trac tickets as external references instead of becoming
the canonical planning system.

## Repository Naming

Recommended future repository name:

```text
rfc1918-platform-fabric
```

This keeps Gentoo Stage4 as an implementation substrate without making it the
entire project identity.

## Workflow

```text
intake -> ready -> in_progress -> blocked -> review -> validation -> done
```

`review` confirms coherence and safety. `validation` confirms the service,
host, network path, SLO, or backout plan works.

## Required Ticket Fields

- `site`
- `system_type`
- `service_role`
- `component`
- `priority`
- `blocked_by`
- `github_pr`
- `codeberg_ref`
- `netbox_object`
- `change_window`
- `backout_plan`
- `slo_validation`

## Service Shape

The first Trac deployment should be a persistent VM service with PostgreSQL,
HAProxy/private-CA TLS, rsyslog, telemetry, ntfy notifications, and
FreeIPA/SSSD-backed operator authentication when the identity plane is ready.

The MCP bridge is modeled separately as `trac_mcp_bridge` so a third-party Trac
MCP server or local thin adapter can be swapped without changing Trac runtime
state.

## Boundaries

NetBox remains IPAM/DCIM authority. FreeIPA remains identity authority. GitHub
and Codeberg remain Git and PR/mirror surfaces.

Trac tickets link NetBox objects, GitHub PRs, Codeberg refs, change windows,
and SLO validation evidence.
