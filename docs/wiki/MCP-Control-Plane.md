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

- [FastMCP Infrastructure Control Plane](FastMCP-Infra-Control-Plane)

## MCP Admission Registry And Promotion Policy

The runtime profile above is the service front door; MCP server admission is a
separate safety gate for which integrations are allowed, how they are audited,
and whether they are read-only, deferred, quarantined, or explicitly promoted
for writes.

Promotion flow:

`Discovery -> audit -> pin -> sandbox -> smoke test -> vault-backed auth -> audit logging -> gated writes`

Default mode is read-only. Mutation-capable integrations such as Jenkins,
Proxmox, Kubernetes/OpenShift, NetBox write tools, and Trac writes require
change-control promotion before receiving write-capable credentials.

Current candidate set:

- Hugging Face MCP: https://huggingface.co/settings/mcp
- Trac MCP
- NetBox MCP
- Grafana MCP: https://github.com/grafana/mcp-grafana
- Jenkins MCP: https://github.com/jenkinsci/mcp-server-plugin
- Proxmox MCP
- Context7 MCP
- Kubernetes/OpenShift MCP, deferred until the OpenShift service profile exists

The `mcp_control_plane` role renders `/etc/mcp-control-plane` policy files. It
does not install or start third-party MCP services.

## Validation

Run:

```bash
bash tests/shell/test_mcp_control_plane_services.sh
```

The test renders the HAProxy template with Nginx-UI and generic MCP backends and
asserts the `/mcp` route, backend mapping, disabled Docker socket default, and
vault-only secret references.
