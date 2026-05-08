# Project Management Control Plane

## Purpose

Trac is the planned authoritative work-management plane for RFC1918
infrastructure automation. It owns tickets, milestones, wiki planning, Kanban
workflow, change-control notes, dependency tracking, and operational
acceptance data.

GitHub and Codeberg remain Git remotes. Pull requests, mirror refs, and commit
links are attached to Trac tickets as external references instead of becoming
the canonical planning system.

## Recommended Repository Name

The project scope has moved beyond Gentoo Stage4 image work. The recommended
future repository name is:

```text
rfc1918-platform-fabric
```

This name covers IaaS, PaaS, VM profiles, container services, identity,
observability, IPAM/DCIM, build automation, and network fabric automation.

## Workflow

The default Trac workflow should be:

```text
intake -> ready -> in_progress -> blocked -> review -> validation -> done
```

`review` and `validation` are intentionally separate. Review confirms the
change is coherent and safe. Validation confirms the affected service, host,
network path, SLO, or backout plan has been tested.

## Required Ticket Fields

Infrastructure tickets should carry these custom fields:

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

The first Trac deployment should be a persistent VM service:

- Trac application runtime
- PostgreSQL persistence
- HAProxy service publication and private-CA TLS termination
- FreeIPA/SSSD-backed operator authentication when the identity plane is ready
- rsyslog log forwarding
- node/service telemetry
- ntfy workflow notifications
- local break-glass admin only for recovery

The MCP bridge is modeled separately as `trac_mcp_bridge`. It can wrap a
third-party Trac MCP server or a local thin adapter without changing Trac's
persistent runtime.

## Integration Boundaries

NetBox remains the IPAM/DCIM source of truth. Trac tickets reference NetBox
object identifiers when work affects a device, VM, prefix, rack, service VIP,
or cable path.

FreeIPA remains the identity source of truth. Trac consumes identity through
SSSD/LDAP/HTTP auth integration rather than creating independent operator
identity.

GitHub and Codeberg remain repository surfaces. Trac tickets should link PRs,
branches, commits, and mirror refs.

## Plugin Policy

Trac plugins are useful but must be pinned conservatively. Initial plugin
classes to validate:

- Git repository browsing
- API/RPC access for automation
- dependency or child-ticket tracking
- CI links for Jenkins and Buildbot
- LDAP/FreeIPA authentication support

Do not install a broad plugin set until compatibility is proven against the
selected Trac version.
