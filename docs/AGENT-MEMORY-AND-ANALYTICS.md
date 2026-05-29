# Agent Memory And Analytics Plan

## Purpose

Define the first repo-safe path for Codex/Forge session analytics and shared
memory without creating a fragile hidden state dependency.

## Query Cycle Analytics

`AGENTS.md` now requires recording query/response timing when practical. The
initial data model should be append-only JSONL:

```json
{
  "schema": "rfc-codex.agent-cycle.v1",
  "session_id": "operator-assigned",
  "repo": "RFC_Codex_Gentoo-Stage4-LLVM",
  "branch": "codex/container-services-delta",
  "started_at": "2026-05-12T00:00:00Z",
  "ended_at": "2026-05-12T00:00:42Z",
  "elapsed_ms": 42000,
  "intent": "k10-e2et-rebuild",
  "actions": ["tests", "commit", "build-start"],
  "artifacts": ["commit:5a66c99"],
  "outcome": "running",
  "notes": "Do not fabricate timing values."
}
```

Rules:

- record only measured timings
- avoid raw secrets, tokens, command outputs containing credentials, and full
  private logs
- link to durable artifacts by commit, issue, PR, file path, or build ID
- preserve a human-readable EOD/SITREP summary until the structured store is
  operational

## Shared Memory Backend

Target backend: S3-compatible object storage.

Initial object layout:

```text
s3://rfc-codex-memory/
  agents/<agent-id>/sessions/<session-id>/events.jsonl
  agents/<agent-id>/sessions/<session-id>/summary.md
  repos/<repo-id>/branches/<branch>/events.jsonl
  manifests/<yyyy>/<mm>/<dd>/<session-id>.json
```

The event stream should be append-only from the agent point of view. Compaction
jobs can write derived summaries and indexes but must not rewrite raw events.

## Consistency Model

Use a simple model first:

- one writer per session event stream
- signed manifest per session closeout
- immutable event object after closeout
- derived summaries are replaceable and marked with source event ranges
- per-agent namespace isolation prevents accidental cross-agent overwrite

This is intentionally weaker than a distributed database but stronger than
untracked local notes. It is sufficient for replay, audit, EOD synthesis, and
future pattern analysis.

## Forge Continuity Model

Forge continuity should not depend on one local Codex process, one host, or one
terminal session. The durable model should have three layers:

- Repo state: committed docs, roadmap entries, plans, tests, and issue links are
  the source of truth for decisions and work products.
- Append-only memory events: each Forge session writes JSONL events and a closeout
  manifest to object storage with commit, branch, host, and artifact references.
- Derived summaries: a compaction job renders current-day SITREP, EOD context,
  unresolved blockers, and next-action queues from the append-only event stream.

Bootstrap sequence for a new Forge runtime:

1. Read the current repository branch and latest pushed commit.
2. Fetch the latest memory manifest for the repo and branch.
3. Load the latest EOD/SITREP summary plus unresolved blocker index.
4. Reconcile with GitHub issues, milestones, and the project board.
5. Emit a new session-start event before taking infrastructure actions.

Required properties:

- one writer per session stream
- no raw secrets or private key material in events
- content-addressed artifact references where practical
- signed session closeout manifests
- local write-ahead spool when object storage is offline
- replayable summaries so memory can be rebuilt after corruption or bad
  compaction

Recommended first implementation:

- Object store: MinIO or Garage on the LAN; Ceph RGW later if Ceph becomes part
  of the storage fabric.
- Local spool: `/var/lib/forge-memory/spool/<session-id>.jsonl`.
- Sync path: append locally, upload object, write manifest, then mark local spool
  synced.
- MCP facade: `scripts/mcp_servers/forge_memory_mcp.py` exposes
  `memory.append_event`, `memory.get_session_summary`,
  `memory.list_recent_sessions`, `memory.search_artifact_refs`, and
  `memory.render_eod_context`.
- GitHub bridge: link memory manifests to issue comments or EOD reports rather
  than storing long raw event logs in GitHub.

## Local Spool CLI

`scripts/forge_memory_spool.py` provides the first repo-managed write-ahead
spool for continuity events while the object-store backend and MCP facade are
still being built.

Implemented operations:

- `append-event`: writes one JSONL event under
  `agents/<agent-id>/sessions/<session-id>/events.jsonl`
- `closeout`: writes a closeout manifest under
  `manifests/<yyyy>/<mm>/<dd>/<session-id>.json`; manifests are unsigned by
  default and may be signed with a local HMAC-SHA256 key file
- `list-sessions`: summarizes local continuity sessions for bootstrap,
  including event count, event hash, last event type, last intent, and whether
  a closeout manifest exists
- `bootstrap-session`: appends a session-start event after summarizing current
  repo branch/commit/dirty state, latest EOD/SITREP/closeout documents, recent
  local memory sessions, optional issue state, optional blocker state, and
  operator-provided memory notes
- `publish-session`: publishes a closed session into a filesystem-backed or
  S3-compatible object-store layout, copying the event log, closeout manifest,
  and publish manifest with checksum metadata

The CLI records session, agent, repo, branch, commit, host, timestamp, intent,
actions, artifact references, and notes. It rejects secret-looking JSON keys
before writing an event or manifest so token material cannot be accidentally
stored through structured JSON paths.

Example:

```bash
scripts/forge_memory_spool.py append-event \
  --spool-root /var/lib/forge-memory/spool \
  --session-id "$(date -u +%Y%m%dT%H%M%SZ)-forge" \
  --agent-id forge \
  --repo RFC_Codex_Gentoo-Stage4-LLVM \
  --branch "$(git branch --show-current)" \
  --commit "$(git rev-parse --short HEAD)" \
  --event-type session-start \
  --intent "resume critical-path infrastructure work" \
  --action "reconcile repo state" \
  --artifact "issue:115"
```

Bootstrap inspection example:

```bash
scripts/forge_memory_spool.py list-sessions \
  --spool-root /var/lib/forge-memory/spool \
  --agent-id forge \
  --limit 10
```

Session bootstrap example:

```bash
scripts/forge_memory_spool.py bootstrap-session \
  --spool-root /var/lib/forge-memory/spool \
  --session-id "$(date -u +%Y%m%dT%H%M%SZ)-forge" \
  --agent-id forge \
  --repo-path /root/RFC_Codex_Gentoo-Stage4-LLVM \
  --intent "resume cross-machine continuity" \
  --issue-state-file project-management/open-issues.json \
  --blocker-state-file project-management/blockers.json \
  --memory-note "M70 is the preferred Forge runtime"
```

Use this before live infrastructure work when object storage is unavailable or
not yet selected. It gives a new Forge runtime enough local continuity context
to find recent session streams and closeout manifests, reconcile those artifact
references against GitHub issues and committed docs, and append a durable
session-start event before taking action.

Object-store publish example:

```bash
scripts/forge_memory_spool.py publish-session \
  --spool-root /var/lib/forge-memory/spool \
  --object-store-root /srv/forge-memory-object-store \
  --session-id 20260521T220000Z-forge \
  --agent-id forge \
  --prefix forge-memory/v1
```

The initial publisher deliberately targets a local or mounted filesystem path
using the same object-key layout intended for a future S3-compatible backend.
This makes the upload contract testable before selecting MinIO, Garage, Ceph
RGW, or another service. It rejects existing destination objects unless
`--overwrite` is explicitly supplied.

S3-compatible publish example:

```bash
scripts/forge_memory_spool.py publish-session \
  --spool-root /var/lib/forge-memory/spool \
  --backend s3 \
  --s3-bucket forge-memory \
  --s3-prefix forge-memory/v1 \
  --session-id 20260521T220000Z-forge \
  --agent-id forge
```

The S3-compatible backend invokes `aws s3 cp` by default, or another compatible
CLI supplied with `--s3-cli`. Credentials, endpoints, and profile selection
must come from the runtime environment or CLI configuration, not from Forge
memory arguments or manifests.

Signed closeout example:

```bash
scripts/forge_memory_spool.py closeout \
  --spool-root /var/lib/forge-memory/spool \
  --session-id 20260521T220000Z-forge \
  --agent-id forge \
  --summary "End-of-session continuity checkpoint" \
  --signing-key-file /run/forge-memory/signing.hmac.key \
  --signing-key-id forge-local-hmac
```

The local signing backend records only the key id, canonical payload hash, and
HMAC-SHA256 signature value. Key material must be provisioned through vault or a
runtime secret path and is never written to the manifest.

Current limitations:

- Vault/SSH/internal-CA signing backends remain future hardening options

## MCP Integration Direction

The Forge memory MCP facade exposes these methods:

- `memory.append_event`
- `memory.get_session_summary`
- `memory.list_recent_sessions`
- `memory.search_artifact_refs`
- `memory.render_eod_context`

`memory.append_event` is a write method and is gated by `MCP_ALLOW_MUTATIONS`,
an idempotency key, and an audit artifact. Read methods operate from the local
spool path selected by `FORGE_MEMORY_SPOOL_ROOT`, defaulting to
`/var/lib/forge-memory/spool`.

## M70 Codex Skill Budget Workaround

On 2026-05-21, M70 showed this Codex startup warning with all Forge skills and
plugins enabled:

```text
Warning: Exceeded skills context budget of 2%.
```

The local root cause is Codex's skill metadata renderer budget, not the model
itself. The upstream renderer currently allocates 2% of the configured model
context window to skill descriptions. With `gpt-5.5` at the cached 272k-token
context window, the metadata budget is about 5,440 tokens, which is too small
for the installed 56-skill Forge profile.

Do not fix this by disabling skills. M70 keeps the plugins enabled and uses a
local model-catalog override to give the skill metadata renderer a larger
budget while keeping normal compaction below the real model context window:

```toml
model = "gpt-5.5"
model_catalog_json = "/root/.codex/models_catalog_local_skillbudget.json"
model_context_window = 400000
model_auto_compact_token_limit = 240000
```

The override file is generated from `/root/.codex/models_cache.json` and changes
only the local `gpt-5.5.max_context_window` entry to `1000000`. This does not
increase the true model context. It only prevents unnecessary truncation of
local skill descriptions, while `model_auto_compact_token_limit = 240000` keeps
conversation compaction comfortably below the actual 272k-token model window.

Fresh-process verification on M70:

```bash
codex debug prompt-input 'fresh-skill-budget-check'
```

Expected result:

```text
skill_mentions=56
warning_count=0
skills_text_len=25885
```

## Open Decisions

- Select the S3-compatible backend: MinIO, Garage, Ceph RGW, or another
  internal object store.
- Decide whether event manifests are signed with age, minisign, SSH signing, or
  internal CA-backed certificates.
- Define retention for raw events, derived summaries, and debug-level traces.
- Decide whether Coherence-CE is an experimental cache only or part of the
  runtime memory index.
