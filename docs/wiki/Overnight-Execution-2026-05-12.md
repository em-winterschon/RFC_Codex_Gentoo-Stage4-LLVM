# Overnight Execution 2026-05-12

## Purpose

Preserve progress during the X12AGAIN off-host backup window and move open
ticket work forward without creating live-infrastructure risk or competing for
disk/network I/O.

## Backup-Safe Operating Mode

Do not start heavy Portage, VM image, or live-infrastructure mutation work while the off-host backup is active.

Allowed overnight work:

1. Repo documentation, tests, roadmap updates, and wiki mirrors.
2. GitHub issue comments, labels, milestones, and dependency mapping.
3. Read-only local inspection that does not walk large backup source trees.
4. Small shell test runs and syntax checks.
5. Append-only Forge memory events that reference commits, issues, and docs.

Deferred until backup completion:

1. RouterOS route, VIP, firewall, or DHCP changes.
2. NetBox writes beyond GitHub/repo planning artifacts.
3. BigNetwork service startup or route promotion.
4. Portage build jobs, rootfs rebuilds, VM image builds, and large rsync-style
   scans.
5. K10 or X12AGAIN reboot/reimage actions.

## Active Ticket Queue

| Issue | Roadmap ID | Overnight action | Live follow-up |
| --- | --- | --- | --- |
| Issue #114 | `FMT2-005` | Add BigNetwork readiness runbook and evidence bundle requirements. | Start the disposable transport VM only after backup completion; capture issue evidence before NetBox/Check_MK promotion. |
| Issue #115 | `MEM-003` | Keep Forge continuity anchored to commits, local spool events, and issue comments. | Select object-store backend, add upload/signed manifest path, then wrap with MCP facade. |
| Issue #116 | `HPC-002` | Keep SLURM pilot scaffold documented and gated on AAA/DNS/E2ET/build VM dependencies. | Provision non-production controller VM after secrets, NetBox features, and observability targets are ready. |
| Issue #111 | `RDMA-003` | Keep DOCA/OFED detection gate and RoCE validation commands documented. | Run live read-only detection on BlueField-2/ConnectX-5 hosts after target host access is stable. |

## Morning handoff sequence

1. Confirm the off-host backup completed and record the destination snapshot
   path and byte count.
2. Re-run the repo shell suite before any live infrastructure mutation.
3. Check `git status --short --branch`; preserve any unrelated dirty files
   separately and commit only Forge-owned changes.
4. For Issue #114, boot or resume the disposable BigNetwork smoke-test VM,
   capture the evidence bundle, then stop before any NetBox or Check_MK writes.
5. For K10/X12AGAIN, resume E2ET only after the netboot publisher and backup
   artifacts are confirmed independent of X12AGAIN.
6. For Agent Memory, write a session-start event before live work and a
   closeout manifest after each major mutation window.

## Blocking Conditions

Do not proceed to live mutation if any of these are true:

1. Backup process is still writing `/root`, `/opt`, `/var/lib`, or `/srv`.
2. `git status` has unresolved Forge-owned changes from overnight work.
3. BigNetwork token vault validation fails.
4. NetBox API or DNS automation state is inconsistent with the planned target
   hostnames.
5. The rollback path for the target VM, route, or service is not documented in
   the relevant issue or runbook.

## Closeout Requirements

Before ending the overnight work block:

1. Run focused tests for every changed artifact.
2. Run the full shell suite if I/O pressure is acceptable.
3. Commit and push repo-safe changes.
4. Comment the affected GitHub issues with commit hashes and verification.
5. Append a Forge memory event referencing the commit and issue numbers.
