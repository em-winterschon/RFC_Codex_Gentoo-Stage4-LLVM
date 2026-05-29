# Trac MCP Evaluation

Decision: Trac MCP is valuable but must start read-only.

Pinned source inspected:

- `nerpatech/trac-mcp-server`
- commit `6dc712eed9045411034488cdd3a6e7de2d131ad0`
- package version `2.1.3`

Safe read tools:

- `ticket_search`
- `ticket_get`
- `ticket_changelog`
- `wiki_get`
- `wiki_search`
- `wiki_recent_changes`
- `milestone_list`
- `milestone_get`

Blocked by default:

- `ticket_delete`
- `ticket_batch_delete`
- `wiki_delete`
- `milestone_delete`
- all write tools until explicit change-control promotion

Do not deploy with write-capable Trac credentials. Use a read-only wrapper or
fork-gated tool surface first.
