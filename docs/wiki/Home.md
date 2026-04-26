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
  staged Ansible installer for LiveISO-driven imaging
- `gentoo-virt-qemu`
  host-side VM builder and launcher helpers for pre-bare-metal validation
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
  build and install in a disposable QCOW first, then validate target-disk boot

## Wiki Contents

- [Architecture and Design](Architecture-and-Design)
- [Workflows](Workflows)
- [Configurations and Examples](Configurations-and-Examples)
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
2. Build a Stage3 QCOW from an LLVM/OpenRC Gentoo stage3.
3. Launch the installer VM with attached target disks.
4. Execute staged Ansible sequences against the installer VM.
5. Boot directly from target disks and verify `bpool`/`rpool`, SSH, and boot flow.

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
