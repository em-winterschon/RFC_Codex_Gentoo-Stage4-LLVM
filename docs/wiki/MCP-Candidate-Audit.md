# MCP Candidate Audit

This page summarizes MCP promotion decisions.

| Candidate | Decision | Default |
| --- | --- | --- |
| `context7` | first smoke test | read-only |
| `netbox` | first smoke test | read-only token |
| `grafana` | smoke test with `--disable-write` | Viewer service account |
| `huggingface` | keep configured for discovery | read-only/research |
| `trac` | evaluate behind wrapper | read-only only |
| `jenkins` | defer until Jenkins VM is live | read-only first |
| `kubernetes-openshift` | defer until OpenShift profile exists | read-only kubeconfig |
| `proxmox` | quarantine | inventory-only future wrapper |

Promotion rule:

`Discovery -> audit -> pin -> sandbox -> smoke test -> vault-backed auth -> audit logging -> gated writes`

No mutation-capable MCP server should receive live write credentials until it has
source pinning, least-privilege auth, smoke-test evidence, audit logging, and a
change-control record.
