# MCP Control Plane

## Purpose

The MCP control-plane profile provides a LAN-only place to run MCP-enabled
operations tooling behind HAProxy. The first service is Nginx-UI, with a
generic HTTP/SSE MCP backend slot reserved for later tools.

## Service Topology

- Profile: `vm-mcp-control-plane`
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

## FastMCP Service Promotion

Custom infrastructure MCP services should be implemented as FastMCP wrappers
behind HAProxy, not as unrestricted API mirrors. The initial promotion order is
NetBox, Proxmox, RouterOS, Trac, and then an internal infrastructure wrapper for
repo playbooks and validators. Nginx-UI remains on its native `/mcp` endpoint.

See:

- [FastMCP Infrastructure Control Plane](FastMCP-Infra-Control-Plane)

## Validation

Run:

```bash
bash tests/shell/test_mcp_control_plane_services.sh
```

The test renders the HAProxy template with Nginx-UI and generic MCP backends and
asserts the `/mcp` route, backend mapping, disabled Docker socket default, and
vault-only secret references.
