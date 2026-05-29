# Overnight Execution 2026-05-15

## Purpose

Advance high-value planning and low-risk automation while the operator is away.
The overnight lane must preserve X12AGAIN, avoid destructive host mutation, and
leave all secret-bearing work either vaulted or explicitly deferred.

## Allowed Work

1. Repo-safe docs, tests, runbooks, profile definitions, and dry-run planners.
2. M70 read-only or additive validation that does not reboot or repartition.
3. NASA NFS mount policy design and non-destructive free-space/read/write
   probes under already-created UID/GID `8888` directories.
4. GitHub issue/PR updates that record evidence and next gates.
5. Ansible Vault planning and variable-name scaffolding without printing or
   committing private keys, passwords, tokens, or keytabs.

## Deferred Work

1. X12AGAIN shutdown, reimage, disk mutation, or service stop.
2. RouterOS, switch, PDU, or FreeIPA live mutation unless a specific payload is
   already approved and a rollback path is documented.
3. Permanent NASA backup retention deletion.
4. Raw `/root/.ssh` or operator-private secret import into git.
5. GPU/inference workload scheduling on production hosts before role boundaries
   and network VIPs are modeled.

## Priority Sequence

| Priority | Work item | Safe overnight output | Live follow-up |
| --- | --- | --- | --- |
| 1 | M70 NASA backup relay | Mount plan, fstab/autofs recommendation, stale-mount checks, dry-run backup command | Apply timer or backup job after operator review |
| 2 | Forge continuity | Checklist for M70 to replace X12AGAIN as admin runtime | Run acceptance gates and keep X12AGAIN online |
| 3 | Vault sync | Variable-name map for M70 SSH profiles, NASA key, host passwords, and BigNetwork token | Import secrets with `ansible-vault` from operator paths |
| 4 | AAA daily operations | FreeIPA Web UI plus `ipa`/`ldapvi` workflow plan | Sync repo identity source to FreeIPA and validate SSSD SSH |
| 5 | SLURM and build farm | Scheduler inventory plan for M70/X11 and future M70 cluster | Bring up controller/worker only after admin host gates |
| 6 | Inference roles | Profile and container-role spec for accelerators, Ollama, vLLM/SGLang, and Open WebUI | Implement once GPU/NPU host inventory and VIPs are modeled |

## AAA UI/TUI Direction

Use FreeIPA Web UI as the primary human web console. It already understands the
objects we need: users, groups, hostgroups, HBAC, sudo rules, SSH public keys,
service principals, and Kerberos policy.

Use `ipa` CLI for repeatable operator actions and `ldapvi` for guarded terminal
inspection/editing when raw LDAP visibility is useful. Avoid making a custom UI
the source of truth. If HTTP SSO is needed for applications, add Keycloak as an
OIDC/SAML federation layer backed by FreeIPA LDAP/Kerberos; do not make
Keycloak authoritative for POSIX UID/GID or SSH public keys.

Automation target:

- repo-safe identity source defines users, groups, hostgroups, UID/GID, SSH
  public-key intent, HBAC, and sudo policy
- Ansible Vault provides passwords, OTPs, RADIUS secrets, private keys, and
  bootstrap credentials
- apply playbooks reconcile FreeIPA and FreeRADIUS
- SSSD serves NSS/PAM and SSH authorized keys on Linux clients

## Inference Role Direction

Define three separate role layers:

- `inference-accelerator`: host/VM profile for GPU/NPU driver readiness,
  PCIe/IOMMU metadata, VFIO or container device exposure, hugepages where
  needed, NUMA pinning, low-latency sysctl, and io_uring-capable storage/network
  workers.
- `inference-engine`: container/service role for Ollama first, with vLLM and
  SGLang as later engines for heterogeneous accelerator scheduling.
- `inference-webui-api`: Open WebUI plus API gateway role that exposes
  OpenAI-compatible endpoints through HAProxy VIPs.

Network policy:

- each primary inference container gets a dedicated service IP/interface
- HAProxy owns stable VIPs and health checks
- model/data mounts come from NFS first, then RDMA/NVMe-oF once the storage
  fabric is validated
- GPU/NPU scheduling is inventory-driven from NetBox plus Ansible host vars

## Closeout Requirements

1. Run focused shell tests for changed repo artifacts.
2. Run `git diff --check`.
3. Commit and push repo-safe changes.
4. Do not claim Shift+Enter is fixed until it is retested in a fresh Codex TUI
   under a tmux pane with extended keys active.
5. Start the next MORN/SITREP with backup relay status, Forge continuity gates,
   and any remaining blockers for X12AGAIN reimage prep.
