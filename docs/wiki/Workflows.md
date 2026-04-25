# Workflows

## Operator Workflow Families

This repository currently has four main workflow families:

- host validation and CI
- VM build and launch
- staged installer execution
- notification and approval visibility

## 1. Validate the Repository

Run before host or VM operations:

```bash
pre-commit run --all-files
bash tests/shell/run-tests.sh
```

Relevant CI workflows:

- `.github/workflows/validate.yml`
- `.github/workflows/notify.yml`

## 2. Build the Stage3 QCOW

Preferred path:

```bash
SSH_AUTHORIZED_KEY_FILE=$HOME/.ssh/id_ed25519.pub \
bash gentoo-virt-qemu/build-stage3-qcow.sh
```

This produces:

- `/opt/gentoo-virt-qemu/stage3/images/gentoo-stage4-testvm.qcow2`

## 3. Launch the Installer VM

Default user-mode networking:

```bash
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

Alias mode:

```bash
QEMU_NETWORK_MODE=alias \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

## 4. Watch Long-Running Install Control Flow

Start the sequence:

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence storage-foundation \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.storage.jsonl
```

Watch it:

```bash
python3 scripts/watch-control-flow.py \
  --path /tmp/ansible-control-flow/target-system-remote.storage.jsonl \
  --follow
```

## 5. Full VM Validation Flow

High-level order:

1. build the QCOW
2. launch installer VM
3. run `storage-foundation`
4. run `chroot-bootstrap`
5. run `target-integration`
6. shut down installer-QCOW boot
7. relaunch with `QEMU_BOOT_SOURCE=target-disks`
8. verify installed target boot, SSH, and ZFS state

Machine-readable version:

- `docs/workflows/stage4-vm-install-and-boot.json`

## 6. Destination Host Staged Install Flow

Recommended order:

1. `storage-foundation`
2. `chroot-bootstrap`
3. `target-integration`
4. optional `repair-boot`
5. optional `repair-services`

Machine-readable version:

- `docs/workflows/stage4-destination-install-sequences.json`

## 7. Persistent Codex Approval Visibility

Install:

```bash
bash scripts/install_codex_approval_watcher_service.sh
```

Verify:

```bash
rc-service codex-approval-watcher status
```

This watches Codex TUI logs and emits ntfy alerts for sandbox approval dialogs.

Machine-readable version:

- `docs/workflows/codex-approval-watcher-service.json`

## 8. Release and Merge Discipline

Operational rule:

- no merges if validation fails

Recommended GitHub protection:

- require PRs
- require status checks:
  - `Validate / pre-commit`
  - `Validate / shell-tests`
- require up-to-date branches before merge
- restrict direct pushes to `main`

## Expected Return Codes

Normal success:

- `0`

Failure conditions should be surfaced at one of these layers:

- shell validator
- Ansible stage failure
- QEMU launch preflight
- SSH readiness checks
- workflow JSONL final stats

## Artifacts Worth Watching

- `/tmp/ansible-control-flow/*.jsonl`
- `/opt/gentoo-virt-qemu/stage3/state/*.serial.log`
- `/tmp/qemu-launch-stage3-vm.sh.*.log`
- `/tmp/validate-llvm-qcow-builder.sh.*.log`
