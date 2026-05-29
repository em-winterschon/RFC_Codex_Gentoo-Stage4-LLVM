# MCP Control Plane

## Purpose

The MCP control-plane profile provides a LAN-only place to run MCP-enabled
operations tooling behind HAProxy. The first service is Nginx-UI, with a
generic HTTP/SSE MCP backend slot reserved for later tools.

## Service Topology

- Profile: `vm-mcp-control-plane`
- Inventory host: `vm_mcp_control_plane`
- Management IP: `172.16.99.68`
- Proxmox placement: Hasslehoff VMID `1068`
- Runtime: Podman via the existing container-services roles
- Front door: HAProxy on ports `80` and `443`
- Primary hostnames:
  - `mcp-control-plane.rfc1918.host`
  - `nginx-ui.rfc1918.host`
  - `mcp-generic.rfc1918.host`
- Internal app addresses:
  - HAProxy: `10.78.1.10`
  - Nginx-UI: `10.78.1.60`
  - generic MCP slot: `10.78.1.61`

## Nginx-UI MCP

Nginx-UI exposes MCP at `/mcp` using SSE and authenticates with the
`node_secret` query parameter. The HAProxy template routes `/mcp` to a dedicated
backend and disables normal request logging for MCP backends so the query
parameter is not routinely written to logs.

Reference:

- https://nginxui.com/guide/mcp

## OpenAI-Compatible Configuration

Nginx-UI supports OpenAI-compatible configuration through environment-backed
settings. The profile only references vault variables; it does not store token
values.

Required vault variables before live deployment:

- `vault_nginx_ui_node_secret`
- `vault_nginx_ui_openai_base_url`
- `vault_nginx_ui_openai_token`
- `vault_nginx_ui_openai_model`
- `vault_nginx_ui_predefined_user_name`
- `vault_nginx_ui_predefined_user_password`
- `vault_nginx_ui_jwt_secret`
- `vault_nginx_ui_crypto_secret`

References:

- https://nginxui.com/guide/config-openai.html
- https://nginxui.com/guide/env

## Security Gates

- Docker socket mounting defaults to disabled.
- The generic MCP backend defaults to disabled until an explicit image and
  command are selected.
- The service should remain LAN-only until private CA trust, RBAC/AAA, and audit
  behavior are validated.
- Live apply should be gated through the same explicit mutation pattern used for
  RouterOS, NetBox, and AAA apply work.

## Live Readiness Gates

The control plane is inventory-ready when all of these are true:

- `vm_mcp_control_plane` exists in the local-network inventory and NetBox intake.
- `mcp-control-plane.rfc1918.host` resolves to `172.16.99.68`.
- `nginx-ui.rfc1918.host` and `mcp-generic.rfc1918.host` are CNAMEs or aliases
  for the MCP control-plane service.
- `vault_nginx_ui_*` variables exist in Ansible Vault.
- `vault_service_tls_certificates.mcp_control_plane.*` contains RFC1918-issued
  leaf material.
- HAProxy serves HTTPS with the `mcp_control_plane` certificate.
- HAProxy request logging remains disabled for `/mcp` routes so `node_secret`
  query parameters are not routinely written to logs.
- Nginx-UI Docker socket access remains disabled.

After those gates pass, promote FastMCP backends one at a time. NetBox is the
first custom MCP target because it is read-heavy, audit-friendly, and already
has repo-side source-of-truth metadata.

## FastMCP Service Promotion

Custom infrastructure MCP services should be implemented as FastMCP wrappers
behind HAProxy, not as unrestricted API mirrors. The initial promotion order is
NetBox, Proxmox, RouterOS, Trac, and then an internal infrastructure wrapper for
repo playbooks and validators. Nginx-UI remains on its native `/mcp` endpoint.

See:

- [FastMCP Infrastructure Control Plane](FASTMCP-INFRA-CONTROL-PLANE.md)
- [FastMCP Infrastructure Control Plane Design](superpowers/specs/2026-05-12-fastmcp-infra-control-plane-design.md)
- [FastMCP Infrastructure Control Plane Implementation Plan](superpowers/plans/2026-05-12-fastmcp-infra-control-plane.md)

## MCP Admission Registry And Promotion Policy

The runtime profile above is the service front door; MCP server admission is a
separate repo-managed safety gate for Forge/Codex and future automation agents.
It prevents ad hoc installation of powerful tools by requiring source review,
version pinning, vault-backed auth, smoke tests, and explicit write gates before
any mutation-capable server receives live credentials.

Promotion flow:

`Discovery -> audit -> pin -> sandbox -> smoke test -> vault-backed auth -> audit logging -> gated writes`

Default mode is read-only. Mutation-capable MCP servers remain blocked until a
change-control entry defines scope, backout, audit logging, and least-privilege
credentials.

### First-Batch Candidate Registry

| ID | Source | Risk | Default | Promotion Status | Notes |
| --- | --- | --- | --- | --- | --- |
| `huggingface` | https://huggingface.co/docs/hub/hf-mcp-server | low | read-only | candidate | Model, dataset, Space, and paper discovery. Operator client settings live at https://huggingface.co/settings/mcp. |
| `trac` | https://mcpmarket.com/server/trac | medium | read-only | candidate | Ticket, milestone, wiki, and change-control integration; write tools require a wrapper gate. |
| `netbox` | https://github.com/netboxlabs/netbox-mcp-server | medium | read-only | candidate | Official NetBox Labs server is read-only and fits IPAM/DCIM lookup first. |
| `grafana` | https://github.com/grafana/mcp-grafana | medium | read-only | candidate | Must run with write-disabled mode and a scoped service-account token. |
| `jenkins` | https://github.com/jenkinsci/mcp-server-plugin | high | read-only | candidate | CI data is useful; build/job mutations require a separate promotion. |
| `proxmox` | https://github.com/bsahane/mcp-proxmox | high | read-only | quarantine | VM lifecycle tools are dangerous; inventory-only smoke test first. |
| `context7` | https://github.com/upstash/context7 | low | read-only | candidate | Documentation freshness tool; pin package/image versions. |
| `kubernetes-openshift` | https://github.com/containers/kubernetes-mcp-server | high | read-only | deferred | Useful once OpenShift exists; keep cluster mutations disabled. |

### Rendered Policy Files

The `mcp_control_plane` Ansible role renders these policy artifacts on the MCP
control-plane host:

- `/etc/mcp-control-plane/candidate-registry.yml`
- `/etc/mcp-control-plane/promotion-policy.yml`
- `/etc/mcp-control-plane/mcp-control-plane.env`

The role does not install or launch third-party MCP servers. It creates the
machine-readable registry and policy that later service wrappers and Trac tasks
can consume.

### Credential Rules

- Store secrets only in Ansible Vault.
- Use read-only tokens unless a change-control entry explicitly requires more.
- Prefer service accounts over personal accounts.
- Keep external SaaS tokens scoped by source system and purpose.
- Do not copy MCP client config files containing tokens into the repo.

### OpenShift And OpenStack TODO

OpenShift and OpenStack are tracked as platform-service profiles, not as MCP
servers. Build VM roles for single-node OpenShift and single-node OpenStack,
review Gentoo/OpenRC feasibility before assuming native service management, and
treat unsupported platform components as appliance VMs managed by our fabric for
network, storage, DNS, TLS, auth, logs, metrics, and backups.

### Operating Rule

No MCP server that can mutate infrastructure should be connected to live
credentials until it has a registry entry, pinned source, smoke-test evidence,
audit path, and explicit promotion state.

## Validation

Run:

```bash
bash tests/shell/test_mcp_control_plane_services.sh
```

The test renders the HAProxy template with Nginx-UI and generic MCP backends and
asserts the `/mcp` route, backend mapping, disabled Docker socket default, and
vault-only secret references.
