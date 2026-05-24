# M70 Canary Gap Analysis 2026-05-24

This review covers the active M70 canary work after the 2026-05-24 hostname,
QAT, dracut, initramfs, and ZFSBootMenu remediation pass.

## Branch And PR Coverage

Repository: `yukon-systems/RFC_Codex_Gentoo-Stage4-LLVM`

Open PR coverage after audit:

| Branch | PR | State | Notes |
| --- | --- | --- | --- |
| `m70-canary-validation-lane` | #144 | open draft | Active canary validation lane. |
| `m70-platform-optimization-inventory` | #135 | merged | M70 platform optimization inventory already reviewed and merged. |
| `recon-sun99-hasslehoff-m70-rs232` | #132 | merged | SUN99/Hasslehoff/M70 serial reconciliation already reviewed and merged. |
| `codex/mcp-control-plane` | #160 | open draft | Backfilled during this audit because the branch had no PR. |
| `codex/trac-control-plane` | #161 | open draft | Backfilled during this audit because the branch had no PR. |

The active canary branch was clean before this documentation update. No
additional uncommitted canary code changes were found at the start of this gap
analysis.

## Open Issue Review

The repo had 86 open issues at review time:

| Status class | Count |
| --- | ---: |
| `status:active` | 41 |
| `status:backlog` | 44 |
| `status:ready` | 1 |

Issue coverage relevant to M70 canary:

| Issue | Coverage | Gap |
| --- | --- | --- |
| #31 `PNR-013` | NetBox-driven provisioning and IPAM maps. | Covers source-of-truth direction, but not canary-local boot evidence. |
| #52 `CI-002` | First Atom C3758 distcc worker validation. | Relevant to M70/C3758 build-worker behavior; canary evidence should feed this when distcc is tested after local boot. |
| #54 `CI-004` | Distcc policy around network isolation and QoS. | Relevant to X12again/M70 distcc concurrency policy, but not a canary install blocker. |
| #81 `WS-007` | Netboot protocol-flow and boot-image manifest automation. | Related to canary netboot rescue path, DNS validation, and iPXE artifacts. |
| #83 `MT-002` | Repo-side automation for wiki publication. | Explains why wiki source coverage must be explicitly mirrored under `docs/wiki/`. |
| #84 `MT-003` | Post-install assertion stages. | Should eventually own automated checks for hostname, cmdline, initramfs payload, QAT modules, and ZFSBootMenu props. |
| #118 `HPC-003` | Scheduler node health and feature inventory. | M70 QAT and C3758 features should become scheduler feature metadata after local boot validation. |

No dedicated open issue exists solely for "M70 canary persistent Gentoo local
boot acceptance." PR #144 currently carries that lane. If the branch stays open
for multiple operating sessions, create a small tracking issue with these
acceptance gates:

- local ZFSBootMenu boot succeeds without iPXE
- hostname/FQDN survive local boot
- `/etc/hosts`, `/etc/cmdline`, and `/etc/kernel/cmdline` match policy
- ZFS imports with expected `spl_hostid`
- QAT modules load and heartbeat remains healthy
- IOMMU groups appear with `intel_iommu=on iommu=pt`
- management networking comes up outside OVS

## Documentation Coverage

Covered in `docs/`:

- `docs/M70-CANARY-VALIDATION-LANE.md` records physical intake, NetBox
  expectations, persistent identity, storage, current remediation state,
  initramfs payload evidence, QAT state, and remaining boot gates.
- `docs/M70-PLATFORM-OPTIMIZATION-PLAN.md` records M70 pool-level
  optimization direction and the current canary evidence.
- `docs/M70-SERIAL-CONSOLE-MAP.md` records the M70 serial console map,
  including the canary FT2232H path.
- `docs/NETBOX-DNS-AUDIT-2026-05-22.md` records canary DNS/IP evidence.
- `docs/CSS326-SWOS-ACCESS-SWITCH.md` records the canary switch-port cabling.
- `docs/EOD-STATUS-2026-05-24.md` records the earlier 2026-05-24 package,
  initramfs, and operating-plan state.

Gaps closed by this audit:

- Added current hostname/QAT/dracut/ZFSBootMenu remediation evidence to the
  M70 canary runbook.
- Added current canary evidence and next action ordering to the M70 platform
  optimization plan.
- Added wiki-source mirrors for M70 canary, M70 platform optimization, M70
  serial console, and this gap analysis.
- Added wiki navigation entries in `Home.md`, `_Sidebar.md`, and `README.md`.
- Added shell regression coverage for M70 docs/wiki presence.

Remaining documentation gaps:

- The live GitHub wiki still needs a separate `scripts/publish-wiki.sh --push`
  after PR review and merge; repo policy treats `docs/wiki/` as canonical.
- A post-local-boot EOD entry should be added after the canary is actually
  rebooted into the persistent Gentoo install.
- NetBox service records should remain absent until the canary actually runs
  those services.

## Operational Gap Summary

Closed:

- Hostname hardcoding and stale K10 identity in live/target host files.
- Missing target `/etc/kernel/cmdline`.
- Missing target QAT kernel fragment policy before future kernel rebuilds.
- Missing ZFSBootMenu dataset command line and zpool cache.
- Missing target dracut ZFS hostid/root config files.
- Universal initramfs rebuilt with AMD and Intel early microcode, ZFS, QAT, and
  legacy DHCP networking.

Still open:

- Planned canary-only reboot to validate local ZFSBootMenu boot.
- Post-boot verification of IOMMU groups.
- Post-boot verification of persistent QAT modules, firmware load, and
  heartbeat.
- Post-boot verification of netifrc management networking without
  NetworkManager.
- X553 OVS/LACP and runtime network validation, which LTC Forge is handling in
  the parallel network/SLURM lane.
