# Trac MCP Evaluation

## Summary

Trac remains the best fit for the local project-management control plane, but
the public Trac MCP server is not safe to connect to production credentials as
shipped. It exposes useful read tools and also exposes destructive ticket, wiki,
milestone, and batch operations.

Decision: run only a read-only smoke test until we either wrap the server,
fork-gate the dangerous tools, or create a separate read-only Trac credential
that cannot mutate state.

## Source Audit

- Project: `nerpatech/trac-mcp-server`
- URL: https://github.com/nerpatech/trac-mcp-server
- Pinned source commit inspected: `6dc712eed9045411034488cdd3a6e7de2d131ad0`
- Package version in `pyproject.toml`: `2.1.3`
- License: MIT
- Runtime: Python `>=3.10`
- MCP SDK dependency: `mcp[cli]>=1.26.0,<2.0.0`
- Transport to Trac: XML-RPC plus local file helpers.

## Tool Surface

Read-oriented tools include:

- `ticket_search`
- `ticket_get`
- `ticket_changelog`
- `ticket_fields`
- `ticket_actions`
- `wiki_get`
- `wiki_search`
- `wiki_recent_changes`
- `wiki_file_pull`
- `milestone_list`
- `milestone_get`

Write and destructive tools include:

- `ticket_create`
- `ticket_update`
- `ticket_delete`, which requires `TICKET_ADMIN` and Trac ticket deleter support
- `ticket_batch_create`
- `ticket_batch_update`
- `ticket_batch_delete`
- `wiki_create`
- `wiki_update`
- `wiki_delete`
- `wiki_file_push`
- `milestone_create`
- `milestone_update`
- `milestone_delete`

## Risk Assessment

The server is useful but too broad. `ticket_batch_delete`, `wiki_delete`, and
milestone deletion are incompatible with default agent access. Batch mutation
tools are particularly risky because a prompt/tool-routing error can damage many
records at once.

The safe initial path is:

1. Deploy Trac itself as the project-management source of truth.
2. Create a Trac read-only service account.
3. Run a Trac MCP smoke test with only read-capable Trac credentials.
4. Add a read-only wrapper or fork that filters exposed MCP tools to the read
   allowlist above.
5. Promote individual write tools later through change control.

## Recommendation

do not deploy with write-capable Trac credentials. Start with a read-only
wrapper. If we need write automation, expose only `ticket_create` and
`ticket_update` first, require a change-control ID in the tool arguments, and
keep delete/batch-delete permanently disabled unless there is a direct operator
break-glass action.

## Smoke-Test Acceptance Criteria

- Trac service is reachable through HAProxy.
- Read-only Trac service account can list milestones and read tickets.
- MCP server starts from a pinned commit or packaged artifact.
- Exposed tool list is captured before use.
- `ticket_batch_delete`, `ticket_delete`, `wiki_delete`, and
  `milestone_delete` are unavailable to the agent path.
- Test output is stored in docs or Trac ticket evidence before promotion.
