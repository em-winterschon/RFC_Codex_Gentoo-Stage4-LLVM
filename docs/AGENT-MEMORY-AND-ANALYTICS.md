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

## MCP Integration Direction

The MCP control plane should expose these methods:

- `memory.append_event`
- `memory.get_session_summary`
- `memory.list_recent_sessions`
- `memory.search_artifact_refs`
- `memory.render_eod_context`

Write methods must be gated by repository identity, branch, and an explicit
operator policy. Read methods may use cached summaries first and raw event logs
only when higher fidelity is required.

## Open Decisions

- Select the S3-compatible backend: MinIO, Garage, Ceph RGW, or another
  internal object store.
- Decide whether event manifests are signed with age, minisign, SSH signing, or
  internal CA-backed certificates.
- Define retention for raw events, derived summaries, and debug-level traces.
- Decide whether Coherence-CE is an experimental cache only or part of the
  runtime memory index.
