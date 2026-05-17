# EOD Status 2026-05-12

## Completed

- Recovered project state after the Codex session/memory loss window by
  auditing local git history, pushed branches, wiki state, and the GitHub
  project-management artifacts.
- Restored and hardened Codex MCP configuration:
  - `openaiDeveloperDocs` MCP is registered.
  - `context7` MCP is registered through a local wrapper.
  - Context7 API token was imported into Ansible Vault and materialized to a
    root-readable runtime secret file instead of being embedded in Codex config.
- Committed and pushed:
  - `2db50d1 Vault Context7 MCP token`
  - `dc9cc06 Plan FastMCP and scheduler control planes`
  - `a88d013 Scaffold NetBox MCP and tomorrow roadmap`
- Published GitHub wiki updates:
  - `36ee06a Sync FastMCP and scheduler planning`
  - `d90696f Sync MCP scaffold and tomorrow roadmap`
- Added FastMCP infrastructure-control-plane planning:
  - NetBox, Proxmox, RouterOS, Trac, and internal-infra MCP wrapper sequence
  - LAN-only HAProxy routing model
  - vault-only credentials
  - `MCP_ALLOW_MUTATIONS` mutation gate
  - idempotency-key and audit-artifact requirements
- Added the first FastMCP implementation scaffold:
  - `scripts/mcp_servers/rfc1918_mcp_common/settings.py`
  - `scripts/mcp_servers/rfc1918_mcp_common/gates.py`
  - `scripts/mcp_servers/rfc1918_mcp_common/audit.py`
  - `scripts/mcp_servers/netbox_mcp.py`
  - `tests/shell/test_fastmcp_infra_servers.sh`
- Added the SLURM-first scheduler plan:
  - SLURM first for deterministic build, validation, GPU-test, and RDMA-test
    partitions
  - HTCondor later for opportunistic/heterogeneous/federated compute
  - CVMFS, Galaxy, UNICORE, and ARC kept as later layers after local scheduler
    stability
- Added tomorrow planning tasks and Kanban issues:
  - `RDMA-003` / #111: OFED path for BlueField-2 and ConnectX-5
  - `STOR-002` / #112: coherent-storage ADR import
  - `HPC-005` / #113: heterogeneous-compute ADR import
  - `FMT2-005` / #114: BigNetwork L2 path for FMT2/SFO-200 discovery
  - `MEM-003` / #115: Forge cross-machine continuity bootstrap
- Extended the agent memory plan with the Forge continuity model:
  - repo state as source of truth for decisions
  - append-only memory events in object storage
  - signed session closeout manifests
  - local write-ahead spool for offline operation
  - MCP facade for memory append/read/render operations

## Verification

- `codex mcp list`
  - result: Context7 and OpenAI Developer Docs registrations restored
- `scripts/materialize-context7-mcp-secret.sh`
  - result: materialized `/root/.codex/secrets/context7_api_key` as `0600`
- `bash tests/shell/test_ansible_vault_tools.sh`
  - result: pass
- `bash tests/shell/test_context7_vault.sh`
  - result: pass
- `scripts/validate-ansible-vaults.sh .../inventories/local-network/group_vars/all/vault.yml`
  - result: pass
- `bash tests/shell/test_fastmcp_and_hpc_plans.sh`
  - result: pass
- `bash tests/shell/test_fastmcp_infra_servers.sh`
  - result: pass
- `bash tests/shell/test_mcp_control_plane_services.sh`
  - result: pass
- `bash -n tests/shell/test_fastmcp_infra_servers.sh tests/shell/test_fastmcp_and_hpc_plans.sh tests/shell/run-tests.sh`
  - result: pass
- `python3 -m py_compile scripts/mcp_servers/netbox_mcp.py scripts/mcp_servers/rfc1918_mcp_common/*.py`
  - result: pass
- `git diff --check`
  - result: pass before commits
- `GH_TOKEN=... gh auth status`
  - result: token-file authentication works with required repo/project scopes

## Current Gates

- `AGENTS.md` remains dirty and uncommitted from pre-existing unrelated local
  changes. It was intentionally not staged or reverted.
- The NetBox MCP code is a skeleton with safety boundaries, not a live backend
  client. The next implementation step is wiring `pynetbox` reads first, then
  dry-run planning, then gated writes.
- The FastMCP services are planned and partially scaffolded, but not deployed
  behind HAProxy yet.
- Default `gh auth status` is not logged in unless `GH_TOKEN` is loaded from
  `/root/.ssh/codex.d/tokens/FORGE_TOKEN`. Use that token-file path for
  automation.
- The GitHub issues were created and project-add commands returned no warnings,
  but project field/status normalization should be verified in the next
  project-management pass.

## Major Errors Or Direction Changes

- The installed `gh issue create` does not support `--json`; issue creation was
  retried using the older CLI output format. The first attempt failed before
  creating any issue.
- The FastMCP scaffold test produced Python `__pycache__` files during local
  validation. Those generated files were removed and remain ignored by
  `.gitignore`.
- The recovery process confirmed that several previous "MCP services" were
  repo-side scaffolds, not active Codex MCP registrations. The current approach
  is to implement real local FastMCP services explicitly instead of assuming
  they already exist.

## Forge Continuity Design

The durable memory model should be implemented as a small infrastructure service
rather than relying on one local Codex process.

Recommended shape:

- Store raw session events as append-only JSONL in S3-compatible object storage.
- Keep a local spool at `/var/lib/forge-memory/spool/<session-id>.jsonl` when
  object storage is unavailable.
- Write a signed manifest at session closeout with branch, commit, host, issue,
  PR, wiki, and artifact references.
- Generate derived summaries for MORN/SITREP/EOD from raw event ranges.
- Expose the memory path through the internal MCP control plane:
  `memory.append_event`, `memory.get_session_summary`,
  `memory.list_recent_sessions`, `memory.search_artifact_refs`, and
  `memory.render_eod_context`.
- Bootstrap every new Forge runtime by reading repo state, latest memory
  manifest, latest EOD/SITREP, unresolved blockers, and GitHub project state
  before taking infrastructure actions.

Backend recommendation:

- First choice: MinIO or Garage for the initial LAN object-store target.
- Later choice: Ceph RGW if Ceph becomes part of the storage fabric.
- Coherence-CE should stay an experimental cache/index layer until the durable
  object-backed event stream is proven.

## Tomorrow Queue

1. Verify GitHub project board placement and status fields for #111 through
   #115.
2. Start `MEM-003`: implement the first Forge memory spool and manifest format.
3. Start `RDMA-003`: define OFED/DOCA detection and deployment policy for
   BlueField-2 and ConnectX-5.
4. Start `FMT2-005`: bring up BigNetwork L2 path to FMT2/SFO-200 and run
   first reachability discovery.
5. Review ADR source sets:
   - `/tmp/docs/ADRs/RFC_Proj-Coherent-Storage-ADRs.2026-Q2.v1`
   - `/tmp/docs/ADRs/RFC_Proj-Heterogeneous-Compute-ADRs.2026-Q2`
6. Continue FastMCP implementation:
   - wire NetBox read-only client
   - add dry-run plan output
   - keep writes gated behind `MCP_ALLOW_MUTATIONS`
7. Continue K10/X12AGAIN and AAA durability work only after the immediate
   continuity and FMT2 access items are safely tracked.

## Backout Summary

- Repo commits from today are small documentation/scaffold deltas and can be
  reverted independently:
  - `2db50d1`
  - `dc9cc06`
  - `a88d013`
- Wiki commits can be reverted from the wiki repo if needed:
  - `36ee06a`
  - `d90696f`
- No live infrastructure mutation was performed by the FastMCP scaffold. The
  scaffold writes audit artifacts only when explicitly called with
  `MCP_ALLOW_MUTATIONS=true`.
