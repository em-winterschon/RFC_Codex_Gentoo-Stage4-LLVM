# MCP Control Plane Services Design

## Goal

Add a repo-safe service profile for running MCP-enabled operations tooling
behind HAProxy, starting with Nginx-UI and a generic MCP HTTP/SSE backend slot.

## Design

The first implementation is a scaffold, not a live mutation. It adds a
dedicated `vm-mcp-control-plane` profile that reuses the existing
container-services host pattern, registers `nginx-ui` and optional
`mcp-generic` container applications, and publishes them through HAProxy with
TLS. Nginx-UI is treated as privileged operational tooling, so Docker socket
mounting is disabled by default and all secrets are represented only as vault
variable references.

Nginx-UI MCP access uses the documented `/mcp` path with SSE and the
`node_secret` query parameter. The HAProxy profile routes the Nginx-UI web UI
and MCP endpoint by host/path while disabling HTTP request logging for MCP
frontends to avoid leaking query-string secrets.

## Components

- `vm-mcp-control-plane.yml` defines the VM profile, HAProxy TLS hostnames,
  Nginx-UI app settings, OpenAI-compatible API env references, and optional
  generic MCP backend settings.
- `container_app_nginx_ui` registers the Nginx-UI runtime container with
  persistent config/data mounts and vault-backed env names.
- `container_app_mcp_generic` registers one configurable HTTP/SSE MCP backend
  without assuming a final upstream image.
- `container_app_haproxy` routes `mcp-ui` and `/mcp` traffic and can suppress
  logs for MCP routes.
- Docs explain the security boundary, required vault variables, and live
  deployment gates.

## Security Boundary

Secrets stay in Ansible Vault:

- `vault_nginx_ui_node_secret`
- `vault_nginx_ui_openai_token`
- `vault_nginx_ui_predefined_user_password`
- `vault_nginx_ui_jwt_secret`
- `vault_nginx_ui_crypto_secret`

The service profile references these by variable name only. Live deployment
must resolve them at runtime without printing values.

## Initial Gates

- Nginx-UI Docker socket integration remains disabled until a separate
  mutation-gated task approves it.
- The generic MCP backend defaults to disabled unless an image and command are
  explicitly provided.
- HAProxy MCP frontend logging must stay disabled when `node_secret` is carried
  in a query parameter.
- Public WAN exposure is out of scope; this is LAN-only until RBAC/AAA and
  private CA behavior are validated.
