# RFC Codex Gentoo Stage4 LLVM

## Purpose

This repository is a Gentoo-focused operating-system imaging toolkit centered on:

- LLVM/OpenRC-first Gentoo installs
- mirrored ZFS `bpool` and `rpool` layouts
- unattended QEMU validation before bare-metal rollout
- staged Ansible execution with structured control-flow logging
- operator notifications through `ntfy.sh` and Codex-side helpers

It exists to turn the Gentoo install process into a repeatable, inspectable pipeline instead of a one-off interactive procedure.

## Functional Areas

- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible`
  staged Ansible installer for Path A LiveISO-driven imaging plus Path B iPXE asset publishing
- `gentoo-virt-qemu`
  host-side VM builder and launcher helpers for pre-bare-metal validation
- `container-image-definitions`
  Stage4/Stage5 container rootfs package lists, USE policy, and overlay fixes
- `scripts`, `.github/workflows`, `openrc`
  notification, approval-watcher, CI, and host integration tooling
- `docs/workflows`
  machine-readable workflow manifests that mirror the operator flows

## Design Principles

- OpenRC first: avoid systemd as a required runtime assumption
- LLVM first: default to Clang/LLD where practical
- ZFS by default: prefer native ZFS layouts for boot and root
- staged execution: decompose installs into named blocks with resumable checkpoints
- operator visibility: control-flow and ntfy output should make long runs observable
- reproducibility: workflows should be described both for humans and machines
- destructive explicitness: disk reimaging requires deliberate opt-in

## Key Patterns

- Inventory separation by execution mode
  examples, VM alias mode, and validation inventories are kept distinct
- Sequence-driven playbooks
  `install_sequence` maps to named stage blocks such as `storage-foundation`
- Control-flow JSONL
  callback plugin emits machine-readable events for long-running installs
- dual-path validation
  keep Path A LiveISO-driven imaging available while adding Path B iPXE fleet booting

## Wiki Contents

- [Architecture and Design](Architecture-and-Design)
- [Workflows](Workflows)
- [Proxmox NetBox RouterOS Action Plan](Proxmox-NetBox-RouterOS-Action-Plan)
- [ITIL Change Control: Container Services Safe Move](ITIL-Change-Control-Container-Services-Safe-Move)
- [NetBox Essentials](NetBox-Essentials)
- [Infrastructure Inventory Intake](Infrastructure-Inventory-Intake)
- [NetBox IPAM DCIM Completion Plan](NetBox-IPAM-DCIM-Completion-Plan)
- [CRS309 RouterOS Replacement Plan](CRS309-RouterOS-Replacement-Plan)
- [CRS354 Distribution Switch Standardization](CRS354-Distribution-Switch-Standardization)
- [CSS326 SwOS Access Switch](CSS326-SwOS-Access-Switch)
- [RouterOS Spine Distribution](RouterOS-Spine-Distribution)
- [Configurations and Examples](Configurations-and-Examples)
- [CI Builder Farm](CI-Builder-Farm)
- [Binpkg Repository](Binpkg-Repository)
- [Container Building](Container-Building)
- [Container Publishing](Container-Publishing)
- [Identity AAA](Identity-AAA)
- [Hetzner DNS Automation](Hetzner-DNS-Automation)
- [Telemetry Observability](Telemetry-Observability)
- [Observability Access](Observability-Access)
- [Changelog](Changelog)
- [SITREP Status 2026-05-03](SITREP-Status-2026-05-03)
- [EOD Status 2026-05-02](EOD-Status-2026-05-02)
- [EOD Status 2026-04-30](EOD-Status-2026-04-30)
- [EOD Status 2026-04-29](EOD-Status-2026-04-29)
- [EOD Status 2026-04-28](EOD-Status-2026-04-28)
- [Repository Layout](Repository-Layout)
- [Roadmap and TODO](Roadmap-and-TODO)

## Primary Entry Points

### Ansible

- `playbooks/install.yml`
- `scripts/run-install-sequence.sh`
- `scripts/watch-control-flow.py`

### QEMU

- `build-stage3-qcow.sh`
- `qemu-launch-stage3-vm.sh`
- `validate-llvm-qcow-builder.sh`

### Notifications

- `scripts/ntfy_notify.py`
- `scripts/codex-ntfy.sh`
- `scripts/install_codex_approval_watcher_service.sh`

## Current Validation Model

1. Run shell and manifest tests locally and in CI.
2. Follow Path A for LiveISO/QEMU validation:
   - build a Stage3 QCOW from an LLVM/OpenRC Gentoo stage3
   - launch the installer VM with attached target disks
   - execute staged Ansible sequences against the installer VM
   - boot directly from target disks and verify `bpool`/`rpool`, SSH, and boot flow
3. Follow Path B for fleet netboot preparation:
   - render iPXE bootstrap, menu, role, host, and manifest assets
   - publish them through DHCP/TFTP plus iPXE HTTP or UEFI HTTP + iPXE
   - boot into the Gentoo provisioning environment and then invoke the same installer workflow

## Current Recommended Validation Path

For the current LiveISO host, the validated standard workflow is:

- QEMU alias-mode networking
- staged Ansible install execution
- target-disk reboot validation
- Gentoo-native `sys-fs/zfs` + `sys-fs/zfs-kmod`
- `gentoo-kernel` with the validated ZFS/ftrace mitigation fragment

Tap/bridge remains a later enhancement, not the required default path.

## Reference Documents

- repo overview: `README.md`
- workflow index: `docs/WORKFLOWS.md`
- machine manifests under `docs/workflows/`
