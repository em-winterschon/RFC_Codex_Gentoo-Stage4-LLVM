# MCP Control Plane

The MCP control plane tracks which MCP servers are allowed, how they are
audited, and whether they are read-only, deferred, quarantined, or explicitly
promoted for writes.

Promotion flow:

`Discovery -> audit -> pin -> sandbox -> smoke test -> vault-backed auth -> audit logging -> gated writes`

Default mode is read-only. Mutation-capable integrations such as Jenkins,
Proxmox, Kubernetes/OpenShift, NetBox write tools, and Trac writes require
change-control promotion before receiving write-capable credentials.

Current candidate set:

- Hugging Face MCP
- Trac MCP
- NetBox MCP
- Grafana MCP
- Jenkins MCP
- Proxmox MCP
- Context7 MCP
- Kubernetes/OpenShift MCP, deferred until the OpenShift service profile exists

The `mcp_control_plane` role renders `/etc/mcp-control-plane` policy files. It
does not install or start third-party MCP services.
