# MCP Control Plane

The MCP control plane is the repo-managed admission process for Model Context
Protocol servers used by Forge/Codex and future automation agents. It prevents
ad hoc installation of powerful tools by requiring source review, version
pinning, vault-backed auth, smoke tests, and explicit write gates.

## Promotion Pipeline

`Discovery -> audit -> pin -> sandbox -> smoke test -> vault-backed auth -> audit logging -> gated writes`

Default mode is read-only. Mutation-capable MCP servers remain blocked until a
change-control entry defines scope, backout, audit logging, and least-privilege
credentials.

## First-Batch Candidate Registry

| ID | Source | Risk | Default | Promotion Status | Notes |
| --- | --- | --- | --- | --- | --- |
| `huggingface` | https://huggingface.co/docs/hub/hf-mcp-server | low | read-only | candidate | Already configured locally for model, dataset, Space, and paper discovery. |
| `trac` | https://mcpmarket.com/server/trac | medium | read-only | candidate | Ticket, milestone, wiki, and change-control integration; branch dependency can land independently. |
| `netbox` | https://github.com/netboxlabs/netbox-mcp-server | medium | read-only | candidate | Official NetBox Labs server is read-only and fits IPAM/DCIM lookup first. |
| `grafana` | https://github.com/grafana/mcp-grafana | medium | read-only | candidate | Must run with write-disabled mode and scoped service-account token. |
| `jenkins` | https://github.com/jenkinsci/mcp-server-plugin | high | read-only | candidate | CI data is useful; build/job mutations require a separate promotion. |
| `proxmox` | https://github.com/bsahane/mcp-proxmox | high | read-only | quarantine | VM lifecycle tools are dangerous; inventory-only smoke test first. |
| `context7` | https://github.com/upstash/context7 | low | read-only | candidate | Documentation freshness tool; pin package/image versions. |
| `kubernetes-openshift` | https://github.com/containers/kubernetes-mcp-server | high | read-only | deferred | Useful once OpenShift exists; keep cluster mutations disabled. |

## Rendered Policy

The `mcp_control_plane` Ansible role renders:

- `/etc/mcp-control-plane/candidate-registry.yml`
- `/etc/mcp-control-plane/promotion-policy.yml`
- `/etc/mcp-control-plane/mcp-control-plane.env`

The role does not install or launch third-party MCP servers. It creates the
machine-readable registry and policy that later service wrappers and Trac tasks
can consume.

## Credential Rules

- Store secrets only in Ansible Vault.
- Use read-only tokens unless a change-control entry explicitly requires more.
- Prefer service accounts over personal accounts.
- Keep external SaaS tokens scoped by source system and purpose.
- Do not copy MCP client config files containing tokens into the repo.

## OpenShift And OpenStack TODO

OpenShift and OpenStack are tracked as platform-service profiles, not as MCP
servers. The immediate policy is:

- Build a VM role for single-node OpenShift using an `openshift-service-profile`.
- Build a VM role for single-node OpenStack using an `openstack-service-profile`.
- Review how much can be Gentoo/OpenRC-native before assuming support.
- Treat OpenShift as VM-hosted RHCOS/FCOS/RHEL-oriented infrastructure unless a
  supported Gentoo path is proven.
- Treat OpenStack as a feasibility split: native Gentoo/OpenRC service daemons
  only if package/service coverage is maintainable; otherwise run it as an
  appliance VM with our fabric managing network, storage, DNS, TLS, auth, and
  observability.

Reference points for the follow-up design pass:

- Red Hat single-node OpenShift installation docs:
  https://docs.redhat.com/en/documentation/openshift_container_platform/
- OpenStack installation guide:
  https://docs.openstack.org/install-guide/
- Gentoo OpenStack package/service feasibility starting point:
  https://wiki.gentoo.org/wiki/OpenStack

Operator/client configuration reference:

- Hugging Face MCP settings page: https://huggingface.co/settings/mcp

## Operating Rule

No MCP server that can mutate infrastructure should be connected to live
credentials until it has a registry entry, pinned source, smoke-test evidence,
audit path, and explicit promotion state.
