# Forge Memory Object Store

MEM-001 and MEM-002 define the durable substrate for Forge continuity across
X12AGAIN, M70, future Forge hosts, and other authorized agents.

The first deployable role is `forge_memory_object_store`. It does not store any
S3 access key or secret key in profile data. It renders the object-store endpoint
contract, local spool path, bucket/prefix policy intent, OpenRC readiness marker,
and audit expectations required by `scripts/forge_memory_spool.py publish-session`.
Credentials must come from Ansible Vault, a runtime secret mount, or a future
Vault SSH/PKI workflow.

## Storage Contract

- Backend: S3-compatible object storage.
- Bucket: `forge-memory`.
- Prefix: `forge-memory/v1`.
- Event logs are append-only JSONL streams.
- Closeout and publish manifests are immutable evidence objects.
- Object names are scoped by `agents/{agent_id}/sessions/{session_id}`.
- server-side encryption is required; the default role contract uses AES256.
- Versioning and object lock are enabled by policy intent.
- Lifecycle retention defaults to 365 days for current objects and 90 days for
  noncurrent objects.
- Audit logs live under `forge-memory/v1/audit`.

## Security Requirements

No access keys or secret keys are stored in defaults, profile definitions, or
generated policy files. Runtime credentials must be injected outside the repo
through vaulted variables or host-local secret material.

The write path remains MCP-gated: `memory.append_event` requires
`MCP_ALLOW_MUTATIONS`, an idempotency key, and an audit artifact. S3 publishing
uses environment-provided credentials and endpoint values only.

## Deployment Shape

`vm-forge-memory-object-store` is the Stage5 profile for a small control-plane VM
or host. The first preferred deployment is an external S3-compatible endpoint,
with MinIO, Garage, Ceph RGW, or another backend selected later after storage,
TLS, and credential authority are finalized.

The role renders:

- `/etc/forge-memory/object-store.env`
- `/etc/forge-memory/object-store-policy.yml`
- `/etc/init.d/forge-memory-object-store`

The OpenRC service is intentionally a readiness marker for local policy and
directory state. It does not attempt to start a backend daemon until the backend
choice is promoted from policy to live deployment.
