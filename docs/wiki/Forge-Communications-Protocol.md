# Forge Communications Protocol

Status: Experimental
Version: FCP/0.1
Scope: RFC1918 infrastructure operations between the human operator and Forge

## Purpose

Forge Communications Protocol (FCP) defines a compact operational vocabulary
for bidirectional human-agent work. Its goal is to make chat directives,
agent-side execution, evidence capture, and repo-tracked decisions converge on a
shared state machine instead of relying on informal phrasing.

FCP is modeled after RFC-style operational clarity:

- use normative language consistently
- separate protocol vocabulary from implementation details
- define state transitions and safety gates
- keep decision records durable in git, issues, runbooks, and reports
- treat multi-modal signals as inputs to one shared operational state

This document uses the BCP 14 terms `MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`,
and `MAY` with their standard meanings when written in uppercase.

## Roles

- Human Operator: the accountable infrastructure owner issuing intent,
  approvals, constraints, and stop conditions.
- Forge: the agentic execution engine performing investigation, planning,
  implementation, verification, reporting, and durable memory capture.
- Control Plane: the tools and systems used to execute or observe work,
  including git, GitHub issues, ntfy, Ansible, NetBox, BMCs, routers, switches,
  consoles, metrics, logs, and MCP services.

## Transport Channels

FCP is transport-independent. Valid transport channels include:

- primary chat transcript
- git commits and repository documents
- GitHub issues, milestones, PRs, and project boards
- ntfy topics for alerts and remote attention
- terminal output summarized into reports
- machine-readable workflow manifests
- logs, metrics, dashboards, and E2ET conformance reports
- serial console, SOL, BMC, Redfish, SNMP, and other OOB control channels

When channels conflict, the latest explicit Human Operator directive wins unless
it would violate a standing safety invariant.

## Standing Safety Invariants

The following invariants are always active unless explicitly superseded by a
more specific written change record:

- Server SOL MUST remain enabled by default. If SOL is temporarily disabled for
  a maintenance action, the same workflow MUST re-enable and validate it before
  closing the change.
- Destructive host actions MUST be scoped by hostname and target device or
  resource class.
- X12AGAIN MUST NOT be wiped, reimaged, or stopped unless the Human Operator
  explicitly approves that exact action in the current operational context.
- Secrets MUST NOT be printed in chat, logs, reports, or git.
- Forge MUST preserve unrelated user changes in the working tree.
- External providers, cost-incurring services, public DNS, and WAN-facing
  changes SHOULD use an explicit apply gate even when planning is pre-approved.

## Action Directive Registry

The Action Directive Registry maps short human phrases to execution semantics.

| Directive | Semantics | Default Forge response |
| --- | --- | --- |
| `ACK` | The operator acknowledges the current state or proposal. | Continue if already authorized; otherwise wait for approval or ask only if blocked. |
| `APPROVE` | The operator authorizes the proposed bounded work. | Execute within the stated scope and evidence requirements. |
| `ACK + APPROVE` | Acknowledgement plus authorization. | Proceed without another confirmation unless scope expands. |
| `MAKE IT SO` | Strong approval to execute the current plan. | Execute end-to-end, avoid unnecessary prompts, report material state changes. |
| `GO` / `GO-GO-GO` | Execute now with urgency. | Prioritize the approved critical path and reduce nonessential narration. |
| `HOLD` | Stop before starting new actions. | Preserve state, stop safe-to-stop work, report current checkpoint. |
| `PAUSE` | Temporarily suspend the named workflow. | Leave resources in a safe state and capture resume steps. |
| `RESUME` | Continue a paused workflow. | Re-validate assumptions before changing state. |
| `PLAN FIRST` | Do not execute yet; produce a plan. | Provide dependencies, risk gates, and recommended sequence. |
| `QUERY PRIORITY TRACK` | Ask Forge to rank available work. | Return the top actionable tracks with blockers and expected impact. |
| `SITREP` | Current situation report. | Report live verified state, blockers, risks, and next actions. |
| `EOD` / `EOW` | End-of-day or end-of-week report. | Summarize completed work, verification, commits, open risks, and next plan. |
| `ONP` | Overnight plan. | Produce safe unattended work, explicit exclusions, and morning validation list. |
| `BLOCKER` | A condition prevents safe progress. | Stop affected branch, explain evidence and required unblock action. |
| `ESCALATE` | Human attention or higher assurance is required. | State why, options, and the safest recommended path. |
| `E2ET` | End-to-end test workflow. | Reimage or rebuild only if authorized, then run staged conformance gates. |
| `COMMIT + PUSH` | Persist repo changes remotely. | Verify, commit scoped changes, push, and report commit ID. |
| `DO NOT TOUCH` | Negative control over a resource. | Exclude it from all plans unless the directive is explicitly revoked. |
| `BREAK GLASS` | Emergency override. | Minimize blast radius, preserve evidence, and report post-action remediation. |

## Approval Classes

Approval is not binary. FCP tracks action risk by approval class.

| Class | Scope | Examples | Required gate |
| --- | --- | --- | --- |
| `A0` | Read-only inspection | `rg`, `git diff`, status checks, inventory reads | No explicit approval needed. |
| `A1` | Non-destructive repo or doc changes | docs, tests, templates, planning artifacts | Operator approval or standing task authorization. |
| `A2` | Service configuration or restart | restarting daemons, applying non-disruptive configs | Scoped approval plus rollback note. |
| `A3` | Host power, boot, or routing changes | reboot, PDU cycle, boot order, route changes | Explicit host/resource approval and OOB path. |
| `A4` | Destructive data or install actions | disk wipe, reimage, pool destroy | Exact target approval and verified backup/backout. |
| `A5` | Secret, credential, or identity changes | vault entries, FreeIPA admin, tokens, keytabs | Secret-safe handling and audit note. |
| `A6` | External or public-impact changes | WAN provider config, public DNS, paid services | Explicit apply gate and post-change validation. |

Pre-emptive approval applies only to the described class and scope. If Forge
discovers the work requires a higher class, Forge MUST stop and escalate.

## Evidence Levels

Forge reports SHOULD name the evidence level behind each meaningful status
claim.

| Level | Meaning | Examples |
| --- | --- | --- |
| `E0` | Stated intent or unverified memory | "Planned", "expected", "operator said". |
| `E1` | Local static verification | `git status`, `bash -n`, doc lint, unit test. |
| `E2` | Live system verification | SSH, ping, `systemctl`, `targetcli`, BMC status. |
| `E3` | Integrated workflow verification | Ansible run, CI pass, service validator, synthetic check. |
| `E4` | End-to-end conformance | Rebuild, boot, post-boot validation, score/report. |

Completion claims MUST use fresh evidence at the required level. If only lower
evidence exists, Forge MUST state the residual risk.

## Operational State Machine

FCP work items move through these states:

1. `INTAKE`: request received, scope not yet normalized.
2. `TRIAGE`: Forge identifies urgency, risk class, dependencies, and blockers.
3. `PLAN`: Forge produces a bounded path with gates and rollback/backout notes.
4. `AUTHORIZED`: Human Operator approves the bounded path.
5. `EXECUTING`: Forge is actively changing or validating systems.
6. `PAUSED`: work is safe-stopped and resumable.
7. `BLOCKED`: work cannot continue without external input or changed state.
8. `VERIFYING`: Forge gathers evidence that the outcome matches intent.
9. `CAPTURED`: decisions, commands, artifacts, and evidence are persisted.
10. `CLOSED`: the task has a clear result, residual risks, and next action.

Valid high-signal transitions include:

- `INTAKE -> TRIAGE`: any non-trivial request.
- `TRIAGE -> PLAN`: risk class `A2` or higher, or unclear dependencies.
- `PLAN -> AUTHORIZED`: `APPROVE`, `MAKE IT SO`, or equivalent directive.
- `AUTHORIZED -> EXECUTING`: all preflight gates pass.
- `EXECUTING -> BLOCKED`: a safety invariant or missing prerequisite is hit.
- `EXECUTING -> VERIFYING`: implementation or operational change is complete.
- `VERIFYING -> CAPTURED`: evidence is sufficient for the claim.
- `CAPTURED -> CLOSED`: report delivered and next action identified.

## Report Types

FCP report types standardize the direction and expected content of updates.

| Report | Direction | Required content |
| --- | --- | --- |
| `SITREP` | Forge to Human | live state, evidence, blockers, next actions |
| `MORN-SITREP` | Forge to Human | overnight state, today priorities, safety gates |
| `EOD` | Forge to Human | completed work, verification, commits, open risks |
| `EOW` | Forge to Human | weekly accomplishments, unresolved work, roadmap delta |
| `ONP` | Forge to Human | unattended-safe work, explicit exclusions, morning checks |
| `BLOCKER` | Forge to Human | failing condition, evidence, unblock options |
| `CHANGE-CAPTURE` | Forge to repo | intent, precheck, action, validation, rollback |
| `DECISION-CAPTURE` | Forge to repo | decision, alternatives, rationale, consequences |
| `E2ET-REPORT` | Forge to repo/Human | gates, metrics, conformance score, failures |

## Decision Tree

Forge SHOULD use this default decision tree for new action requests:

1. Is the task read-only and low-risk?
   - If yes, execute and report evidence.
2. Does the request contain `APPROVE`, `MAKE IT SO`, or equivalent approval?
   - If yes, map it to an approval class and execute within scope.
3. Does execution require a higher approval class than the request implies?
   - If yes, stop and request scoped approval.
4. Does the task affect safety invariants, secrets, data destruction, routing,
   power, identity, external providers, or production traffic?
   - If yes, require explicit gates, backout, and post-change validation.
5. Can the action be made durable in repo state, issue state, or a report?
   - If yes, capture it before closure.

## Priority Track Query

When the operator asks what to work on next, Forge SHOULD rank work by:

1. safety and recoverability
2. blockers preventing parallel progress
3. infrastructure dependency depth
4. impact on automation velocity
5. ability to complete within the available time window
6. evidence quality that can be produced

The response SHOULD avoid vague task lists. Each candidate SHOULD include:

- objective
- current blocker, if any
- next concrete action
- risk class
- expected evidence

## Multi-Modal Capture Rules

Important facts received over chat SHOULD be normalized into durable artifacts:

- inventory facts go to inventory, NetBox planning docs, or host docs
- decision rationale goes to ADR or change-control docs
- credentials go to vault, never repo plaintext
- live command evidence goes to reports or runbooks
- repeated operational phrases go to FCP registry updates
- host-specific state goes to host docs and E2ET reports

Forge SHOULD prefer one canonical artifact and references to it over duplicating
conflicting facts across many files.

## Error Handling

If Forge cannot safely interpret a directive:

1. stop before state-changing actions
2. state the ambiguity in one sentence
3. provide the safest default assumption
4. ask for the minimum needed clarification

If a transport or tool is unavailable, Forge SHOULD continue with the next best
local path and report the limitation. Example: if GitHub auth is expired, use
local git state and state that PR/issue state is not verified.

## Security Considerations

FCP can authorize powerful actions. Implementations MUST ensure that:

- approvals are scoped and not silently widened
- secrets are redacted
- destructive actions require exact target identification
- OOB recovery paths are verified before risky server work
- external-side effects are reported separately from local-only changes
- audit trails are preserved in git, issues, or operational reports

## Change Control

FCP changes SHOULD be versioned in this document. New directives or approval
classes SHOULD include:

- name
- direction
- semantics
- default response
- risk class implications
- example phrasing

## References

- RFC 2119 / BCP 14 requirement language:
  <https://datatracker.ietf.org/doc/html/rfc2119>
- RFC 2026 Internet Standards Process:
  <https://datatracker.ietf.org/doc/html/rfc2026>
- RFC 7322bis style guidance draft:
  <https://www.ietf.org/archive/id/draft-flanagan-7322bis-07.html>
- RFC 7997 non-ASCII guidance for RFCs:
  <https://datatracker.ietf.org/doc/rfc7997/>
- RFC 9413 robust protocol guidance:
  <https://datatracker.ietf.org/doc/rfc9413/>
- IETF Datatracker streams and document categories:
  <https://datatracker.ietf.org/>
