# Overnight Execution 2026-05-13

## Purpose

Move the highest-gain work forward while avoiding unattended destructive host
mutation. The working assumption is that the operator is unavailable, so the
overnight lane must preserve X12AGAIN, avoid M70 disk wipes, and keep live
infrastructure changes either read-only or explicitly gated.

## Operating Mode

Allowed overnight work:

1. Repo documentation, tests, runbooks, roadmap updates, and wiki mirrors.
2. No-mutation Ansible syntax checks and dry-run planners.
3. Read-only infrastructure reachability checks when they do not reboot,
   reconfigure, or walk large backup trees.
4. GitHub issue and PR comments that record commits, gates, and verification.
5. Forge memory spool or session closeout artifacts that do not contain
   secrets.

Deferred until operator is awake:

1. M70 disk install or any wipe of `/dev/sda`, `/dev/nvme0n1`, or
   `/dev/nvme1n1`.
2. X12AGAIN shutdown, reimage, disk mutation, or service stop.
3. RouterOS, switch, or AP7901 authentication mutation.
4. NetBox live writes unless snapshot-backed and already approved for the exact
   payload.
5. BigNetwork route promotion or FMT2 inventory promotion.

## Priority Sequence

| Priority | Work item | Safe overnight output | Live follow-up |
| --- | --- | --- | --- |
| 1 | M70 persistent automation-admin | Install runbook, disk-health preflight, E2ET manifest updates, tests | Human-approved disk install on SATADOM+iPXE plus mirrored NVMe ZFS |
| 2 | Forge continuity restore | Restore manifest and validation checklist for `/root`, `/opt`, `/var/lib/*` paths | Restore off-host backup content onto installed M70 and validate Codex runtime |
| 3 | X12AGAIN preflight | Service reachability matrix and SoL validation wrapper docs | Run live preflight and keep destructive gates false until approved |
| 4 | SLURM observability | Prometheus/VictoriaMetrics/Grafana/rsyslog/Elasticsearch integration targets | Apply exporter/log configs to controller and first worker |
| 5 | NetBox DCIM dry-run | Interface/LAG/optic/cable/power-chain model plan | Snapshot NetBox, then apply reviewed payload |
| 6 | FMT2/BigNetwork prep | Evidence bundle schema and disposable smoke-test wrapper | Bring up L2 path and run discovery against FMT2 |

## M70 Work Details

The M70 is the critical path for X12AGAIN reimage. Overnight work should make
the final install boring, not perform it unattended.

Deliverables:

- `docs/runbooks/m70-automation-admin-install.md`
- no-mutation disk inventory command list
- expected SATADOM/iPXE and mirrored-NVMe ZFS layout
- post-install service validation checklist
- acceptance checks for:
  - hostname/FQDN
  - static `netboot0`
  - SSSD and host keytab
  - `codex-admin` central SSH
  - Ansible, Ansible Vault, Git, GitHub CLI, and ipmitool
  - X12AGAIN SoL wrapper
  - local ntfy HTTPS

## X12AGAIN Work Details

X12AGAIN should remain untouched overnight. Repo work should make the eventual
change window safer:

- add concrete service reachability checks to the preflight
- define the backup manifest fields required for approval
- document the emergency console evidence requirement
- keep `x12again_reimage_apply_required=false`
- keep `x12again_reimage_human_change_window_approved=false`

## SLURM Work Details

The pilot is live. The next safe work is observability and feature metadata:

- scrape target definitions for controller and worker
- log routing definitions for `slurmctld`, `slurmdbd`, and `slurmd`
- dashboard placeholder or import plan
- node feature taxonomy sourced from NetBox and Ansible inventory
- no admission of X12AGAIN until E2ET passes

## Closeout Requirements

Before ending the overnight block:

1. Run focused tests for changed artifacts.
2. Run `git diff --check`.
3. Run `bash tests/shell/run-tests.sh` if runtime cost is acceptable.
4. Commit and push repo-safe changes.
5. Comment PR `#122` or the relevant issue with commit hashes and verification.
6. Update the next MORN/SITREP with gates, blockers, and any deferred live
   changes.
