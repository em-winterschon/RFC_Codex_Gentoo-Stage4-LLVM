# End of Day Status: 2026-04-25

Generated: 2026-04-25 America/Los_Angeles  
Repo: `em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM`  
Active branch at EOD: `codex/fix-zfs-hostid-and-zbm-kcl`

## Executive Summary

Today closed the loop on the kernel and ZFS validation path for the alias-mode installer VM.

The important outcome is this:

- the staged installer completed successfully on the alias-mode VM
- the installed target booted successfully from mirrored `bpool` and mirrored `rpool`
- the previous `ftrace` warning path seen with `gentoo-kernel-bin` no longer reproduced after switching to `gentoo-kernel` with a kernel config fragment disabling the direct-call / args dynamic ftrace path
- the malformed `sole=tty0` boot argument was corrected and verified on a fresh target-disk reboot

This means the preferred kernel/ZFS sequence is now operationally validated.

## Problems Solved Today

### 1. Corrected the package-version strategy for the live validation tree

The initial exact pins were too optimistic for the target Portage tree.

Resolved by changing the qemu-alias validation inventory to the versions that actually exist:

- `=sys-kernel/gentoo-kernel-6.18.18`
- `=sys-fs/zfs-2.3.6`
- `=sys-fs/zfs-kmod-2.3.6`

### 2. Validated the preferred ZFS mitigation sequence

The validated combination is now:

- Gentoo-native `sys-fs/zfs`
- Gentoo-native `sys-fs/zfs-kmod`
- `kernel_strategy: gentoo-kernel`
- kernel fragment disabling:
  - `CONFIG_DYNAMIC_FTRACE_WITH_DIRECT_CALLS`
  - `CONFIG_DYNAMIC_FTRACE_WITH_ARGS`

### 3. Completed a full staged imaging run in alias mode

Completed successfully:

- `storage-foundation`
- `chroot-bootstrap`
- `target-integration`

Observed final installer results included:

- `gentoo-kernel-6.18.18` built successfully
- `sys-fs/zfs-kmod-2.3.6` built successfully
- `sys-fs/zfs-2.3.6` built successfully
- boot integration completed
- network integration completed

### 4. Re-validated target-disk boot from installed media

Confirmed after reboot from target disks:

- `/` mounted from `rpool/ROOT/gentoo`
- `/boot` mounted from `bpool/BOOT/gentoo`
- `/efi` mounted from `/dev/sda1`
- pools healthy
- SSH reachable on `10.9.8.108:2222`

### 5. Closed the ZFS/ftrace question for the current validated path

On the final target-disk boot:

- acceptable out-of-tree taint remains:
  - `spl: loading out-of-tree module taints kernel`
- the earlier `ftrace bug` / `ftrace failed to modify` warning path did **not** reproduce

### 6. Corrected the malformed kernel command line

The target had a persisted ZFSBootMenu property containing:

- `sole=tty0`

That was corrected to:

- `console=tty0`

Verified on fresh boot:

```text
root=ZFS=rpool/ROOT/gentoo ro console=tty0 console=ttyS0,115200 spl.spl_hostid=0x02bda349
```

### 7. Added a regression check for the bad boot-argument token

Added coverage so the repo now checks that a standalone `sole=tty0` token does not reappear in the boot commandline templates.

## Outstanding Tasks

### 1. Commit and push the current PR #15 branch updates

The branch contains more than the original hostid/ZFSBootMenu fix now. It also contains:

- the validated `gentoo-kernel` + ZFS package strategy
- qemu-alias inventory updates
- the installer override-path regression test
- the `sole=tty0` regression guard

### 2. Update PR #15 description

PR #15 currently describes only the earlier hostid/ZFSBootMenu work. It should be updated to reflect:

- the validated kernel/ZFS mitigation
- the final target-disk boot result
- the corrected command line

### 3. Decide whether to merge PR #15 as-is or split it

Current branch scope is now broader than its original summary. Decision needed:

- merge as one coherent “finish the ZFS boot and kernel mitigation path” PR
- or split the newer kernel/ZFS mitigation work into a separate PR

### 4. Keep private ntfy server deployment paused

PR #14 remains paused pending external network/server availability.

### 5. Evaluate tap/bridge later

Alias mode is now the validated standard workflow for the current LiveISO host. Tap/bridge remains a later enhancement, not a blocker.

## Open PRs at EOD

- PR #13: `Add persistent ntfy reply listener for Codex`
- PR #14: `Add Ansible deployment path for private ntfy server`
- PR #15: `Fix ZFS hostid and ZFSBootMenu boot commandline handling`

## PRs Closed Today

### Merged

- PR #12: `Fix alias-mode target integration for staged boot validation`
  - merged at `2026-04-25 23:20:50Z`
  - merge commit: `0d5a17930ed6aa3e812f8576dc5f728ed3b37de6`

No other PR closures were recorded today in the observed repo activity.

## Tomorrow's Goals

1. Commit and push the current `codex/fix-zfs-hostid-and-zbm-kcl` branch state.
2. Update PR #15 so its summary matches the actual validated scope.
3. Decide whether PR #15 should remain single-scope or be split.
4. Run a final shell validation pass after the EOD commit if anything else changes.
5. Move next either into PR #15 review/merge or into the next tranche of network / ntfy infrastructure work.

## Validation Snapshot

Validated live today:

- target-disk boot from mirrored `bpool` + mirrored `rpool`
- alias-mode installer imaging path
- `gentoo-kernel-6.18.18` install
- `zfs-2.3.6` / `zfs-kmod-2.3.6` install
- healthy ZFS import and root mount under dracut
- corrected runtime kernel command line

Key runtime facts at final check:

```text
/      -> rpool/ROOT/gentoo
/boot  -> bpool/BOOT/gentoo
/efi   -> /dev/sda1
```

```text
ZFS: Loaded module v2.3.6-r0-gentoo
```

No `ftrace bug` reproduced on the final validated path.
