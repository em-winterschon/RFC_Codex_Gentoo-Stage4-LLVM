# Trac Project Management Control Plane Design

## Goal

Build a self-hosted project-management control plane where Trac is the
authoritative source for tickets, milestones, wiki planning, Kanban workflow,
and change-control metadata, while GitHub and Codeberg remain Git remotes and
PR/mirror surfaces.

## Scope

This phase creates repo-native scaffolding, not a live production cutover. It
defines:

- a `vm-trac-service` Stage5 profile for the persistent Trac service
- a `trac_server` Ansible role for Trac runtime configuration
- a `trac_mcp_bridge` Ansible role for future agent-facing MCP access
- HAProxy service-type metadata for Trac HTTP/TLS publication
- FreeIPA/SSSD/RADIUS integration intent for operator authentication
- docs and tests that keep the planning plane reproducible

GitHub Issues should not become the canonical Kanban system. GitHub pull
requests and Codeberg mirror refs are attached to Trac tickets as external
links or custom fields.

## Architecture

Trac runs as a dedicated VM-backed service with PostgreSQL persistence and
repo-managed configuration. HAProxy publishes the service on the management
network with private-CA TLS termination. Trac authenticates operators through
the identity plane once FreeIPA/SSSD is fully available; local admin accounts
remain break-glass only.

The MCP bridge is modeled as a separate service role because the Trac MCP
server may either be a packaged third-party bridge or a local thin adapter. The
bridge is isolated from Trac's persistent runtime so it can be replaced without
changing ticket/wiki data.

## Data Model

Trac tickets carry infrastructure-specific custom fields:

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

The default workflow states are:

```text
intake -> ready -> in_progress -> blocked -> review -> validation -> done
```

The workflow intentionally keeps `validation` separate from `review`. Review
answers whether the plan/change is coherent. Validation answers whether the
service, host, network path, or SLO actually works.

## Service Dependencies

Trac depends on:

- PostgreSQL for ticket/wiki persistence
- HAProxy for external publication and TLS termination
- private CA trust for browser/API access
- rsyslog for log egress
- node/service exporters for baseline telemetry
- FreeIPA/SSSD for non-root operator identity when ready
- ntfy for workflow notifications

The MCP bridge depends on:

- Trac HTTP/API reachability
- a vault-backed Trac service token
- local network-only exposure by default
- operator-controlled allowlists for batch ticket mutations

MCP audit inputs:

- `https://mcpmarket.com/server/trac`
- `https://mcpmarket.com/server/trac-1`

Both marketplace listings currently reference the `nerpatech/trac-mcp-server`
project family. The marketplace pages are discovery evidence only. Source
pinning, code review, vendoring, or local fork decisions should use the upstream
source repository and local checks.

## Repository Naming

The current repository name is too Gentoo-specific for the platform scope. The
recommended future name is:

```text
rfc1918-platform-fabric
```

Rationale: the project now spans infrastructure fabric, VM and container
service profiles, identity, observability, IPAM/DCIM, build automation, and
network automation. Gentoo Stage4 remains a major implementation substrate, not
the full project identity.

## Acceptance Criteria

This phase is complete when:

- Trac service profile metadata exists and is tested
- Trac role defaults, tasks, and templates exist and are syntax-checkable
- MCP bridge role defaults, tasks, and templates exist and are syntax-checkable
- HAProxy service-type intent exists for Trac
- docs explain Trac as authoritative Kanban and GitHub/Codeberg as linked Git
  surfaces
- tests verify profile, package, custom-field, workflow, and docs invariants
- no plaintext secrets are committed

## Non-Goals

- live production Trac deployment
- importing all existing GitHub PRs/issues
- enabling public WAN access
- committing Trac admin passwords or MCP tokens
- picking a final third-party plugin set before compatibility testing

## Operational Notes

Plugin installation must be conservative. The official Trac plugin ecosystem is
large and unevenly maintained, so this repo should pin a minimal tested set
first: Git integration, API/RPC access, dependency/workflow helpers, and CI
links. Jenkins and Buildbot integration are desirable but should be validated
against the eventual Trac version before entering the default service profile.
