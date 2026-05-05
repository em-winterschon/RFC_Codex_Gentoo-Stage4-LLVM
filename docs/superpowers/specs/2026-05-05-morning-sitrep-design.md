# Morning SITREP Design

## Purpose

Morning SITREP is the start-of-day operator brief for RFC99 infrastructure
work. It preserves the directness of a situation report while making the
content morning-specific: overnight state, active workstreams, immediate risks,
and the first execution sequence for the day.

## Format

```text
MORNING SITREP - YYYY-MM-DD HH:MM TZ

State:
<Current health, branch state, builds, service state, and infrastructure posture.>

Incidents:
<Overnight failures, restarts, resolved blockers, and anything that changed without direct operator attention.>

Threads:
<Active workstreams and concise status for each.>

Risks:
<Likely time sinks, fragile assumptions, external dependencies, and known technical debt that can affect today.>

Execution:
<Recommended first moves in priority order.>

Partner Needs:
<Physical actions, credentials, access, cabling, approvals, or decisions needed from the human operator.>

Watch:
<Commands, logs, tmux sessions, dashboards, or health checks worth monitoring.>
```

## Field Semantics

- `State` is factual and current. It should include the current date/time,
  active branch, build status, and any important infrastructure health signals.
- `Incidents` is for events since the prior closeout or prior Morning SITREP.
  Include both failures and meaningful recoveries.
- `Threads` is the workstream map. Each item should be short enough to scan but
  concrete enough to resume work.
- `Risks` should be blunt. If something is likely to burn time, call it out
  before execution begins.
- `Execution` is the recommended action order for the morning. It should favor
  verification gates before irreversible changes.
- `Partner Needs` is empty only when no operator action is needed. Do not hide
  physical dependencies in other sections.
- `Watch` should contain exact commands, paths, sessions, or endpoints when
  available.

## Style Rules

- Lead with current reality, not narrative.
- Prefer exact timestamps, branch names, paths, package counts, and service
  names.
- Keep each section compact. Morning SITREP is a launch brief, not an EOD
  report.
- Separate facts from recommendations. `State` and `Incidents` are facts;
  `Execution` is recommended action.
- Use `None` when a section has no entries, instead of omitting the section.

## Example

```text
MORNING SITREP - 2026-05-05 06:35 PDT

State:
Workstation Stage5 branch is clean and pushed. On-host workstation QCOW package build completed.

Incidents:
Overnight Portage blockers were resolved by encoding explicit workstation policy for PyQt5, pyqt5-sip, freetype[harfbuzz], xmlto[text], and pillow bootstrap cycle breaking.

Threads:
1. Workstation VM: ready for image validation and SPICE boot test.
2. Branch workflow: ready for PR/action-plan if validation passes.
3. Hasslehoff validation: next after on-host QEMU boot proves sane.

Risks:
PyQt5 is masked for removal upstream, so NsCDE needs either local overlay support or a future PyQt6/non-PyQt path.

Execution:
1. Inspect final QCOW artifacts.
2. Boot workstation VM with SPICE.
3. Validate SSH, dbus, spice-vdagent, Xorg/startx, and NsCDE role path.
4. Commit validation docs or fixes.
5. Open or update PR.

Partner Needs:
None immediately.

Watch:
tail -f /opt/gentoo-virt-qemu/workstation-nscde/logs/build-20260505T034516Z.log
```

## Review Notes

The format is intentionally stable enough for daily repetition but lightweight
enough to write quickly. It complements EOD reports: Morning SITREP starts the
day with action priority, while EOD captures durable recordkeeping and
handoff detail.
