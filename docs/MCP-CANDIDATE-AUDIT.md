# MCP Candidate Audit

This audit turns the MCP candidate list into promotion decisions. The goal is
not to collect interesting tools. The goal is to admit only tools with clear
operator value, pinning strategy, least-privilege auth, and safe failure modes.

## Decision Matrix

| Candidate | Source | Observed Capability | Risk | Decision | Next Action |
| --- | --- | --- | --- | --- | --- |
| `huggingface` | https://huggingface.co/docs/hub/en/hf-mcp-server | Model, dataset, Space, and paper discovery through Hugging Face's MCP server. | low | keep candidate | Validate local configuration from `~/.codex/config.toml`; no write token needed for discovery. |
| `trac` | https://github.com/nerpatech/trac-mcp-server | Trac tickets, wiki, milestones, attachments, file push/pull, batch ticket operations. | high | evaluate behind read-only wrapper | Pin commit, test with read-only Trac credentials, and block destructive tools before any production connection. |
| `netbox` | https://github.com/netboxlabs/netbox-mcp-server | Read-only NetBox object lookup, search, object-by-ID, and plugin object discovery. | low-medium | promote to first smoke test | Use a NetBox read-only token and verify IPAM/DCIM query coverage for RFC99/SUN99/FMT2. |
| `grafana` | https://github.com/grafana/mcp-grafana | Dashboard, datasource, alert, incident, and annotation operations with documented `--disable-write` support. | medium-high | smoke test read-only only | Run with `--disable-write` plus Viewer-scoped service account. Never use Editor role by default. |
| `jenkins` | https://github.com/jenkinsci/mcp-server-plugin | Jenkins jobs, builds, logs, SCM metadata, build triggering, replay, and build mutation tools. | high | defer until Jenkins VM is live | Use read-only Jenkins account first; block `triggerBuild`, `rebuildBuild`, `replayBuild`, and `updateBuild` until CI change-control exists. |
| `proxmox` | https://github.com/bsahane/mcp-proxmox | Proxmox inventory and VM lifecycle operations. | high | quarantine | Do not connect to Hasslehoff API credentials until inventory-only wrapper and audit logging exist. |
| `context7` | https://github.com/upstash/context7 | Documentation and code-example lookup for current library/API context. | low | smoke test | Pin package/image version and run without private repository access. |
| `kubernetes-openshift` | https://github.com/containers/kubernetes-mcp-server | Kubernetes/OpenShift cluster query and management. | high | deferred | Revisit after `openshift-service-profile` exists; read-only kubeconfig only. |

## Promotion Order

1. `context7`: lowest blast radius and immediately useful for current docs-heavy
   work.
2. `netbox`: strong fit for IPAM/DCIM and inventory-driven automation;
   schedule a read-only smoke test with the live NetBox API.
3. `grafana`: useful after observability comes online; enforce `--disable-write`.
4. `huggingface`: already configured; keep for research/model/dataset lookup.
5. `trac`: valuable, but only after a read-only wrapper blocks mutation tools.
6. `jenkins`: wait until Jenkins controller service is live.
7. `kubernetes-openshift`: wait until OpenShift profile exists.
8. `proxmox`: last, because VM lifecycle mutation risk is too high.

## Security Findings

- The most dangerous class is not "bad MCP server"; it is a useful MCP server
  with broad credentials and mutation tools exposed to an agent by default.
- Service-specific read-only credentials are mandatory for smoke tests.
- Any tool that can create, update, delete, start, stop, replay, or execute work
  must be gated by change control.
- Candidate servers without clear release tags need commit pinning.
- Public SaaS fallbacks are not acceptable for internal notification, auth,
  infrastructure mutation, or observability control loops.

## Immediate Execution

- Create a disposable MCP smoke-test VM/container profile later, separate from
  the control-plane registry.
- Start with `netbox`, `context7`, and `grafana --disable-write`.
- Keep Trac MCP blocked from write-capable credentials until the wrapper/fork
  decision in `docs/TRAC-MCP-EVALUATION.md` is complete.
