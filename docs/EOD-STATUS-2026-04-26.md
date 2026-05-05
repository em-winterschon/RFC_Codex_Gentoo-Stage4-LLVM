# End of Day Status: 2026-04-26

## Summary

Today’s work closed the main Path B boot blocker.

Validated live:

- RouterOS CHR continues to provide DHCP and iPXE handoff on `10.9.8.0/24`
- Path B assets publish from the Gentoo host
- a UEFI test client now completes:
  - iPXE boot
  - kernel/initramfs download
  - `rootfs.img` download
  - dracut `switch_root`
  - OpenRC `default`
  - SSH access to the provisioning environment
- the provisioner network state now converges to:
  - one IPv4 address
  - one default route
  - no surviving DHCP client manager

## Problems Solved Today

1. Fixed a host-side PTY issue on the live-ISO control node.
   - `/dev/ptmx` was missing
   - `devpts` was mounted with unusable `ptmxmode=000`
   - remote SSH PTY allocation works again on the host
2. Fixed Path B SquashFS artifact corruption.
   - `mksquashfs` had been appending by default
   - repeated rebuilds produced recursively duplicated top-level trees
   - builder now uses `-noappend`
3. Fixed Path B live-root mountpoint handling.
   - the prior exclusion pattern removed `/dev`, `/proc`, `/sys`, `/run`, `/tmp`, and `/boot/efi` entirely
   - builder now preserves directories and excludes only contents
4. Fixed Path B post-`switch_root` serial access.
   - active `ttyS0` getty insertion now ignores commented template lines
   - `ttyS0` is added to `securetty`
5. Fixed Path B network handoff after initramfs DHCP.
   - the provisioner previously ended with multiple IPv4 addresses and duplicate default routes
   - builder now supports reusing initramfs networking and pruning duplicate address/route state in userspace

## Commits Landed Today

- `b60feb6` `Fix Path B live-root artifact and network handoff`

## Open PRs

- `#13` ntfy reply listener
- `#14` private ntfy server deployment
- `#15` ZFS hostid / ZFSBootMenu commandline follow-up
- `#16` default LLVM/Clang Portage profile and linting
- `#17` Path B iPXE netboot workflow

## Closed / Merged PRs Today

- none

## Outstanding Tasks

1. Remove temporary debug hooks from the Path B provisioner once the normal boot path is considered stable.
2. Encode the live-proven Path B client launch and host bridge/tap setup into repo-managed launch helpers.
3. Decide whether the provisioner should permanently reuse initramfs networking by default or provide a per-profile switch.
4. Extend documentation and workflow manifests to reflect the now-validated Path B boot state.
5. Start using the Path B provisioner for actual installer-driven imaging runs.

## Tomorrow / Next Tranche

1. Clean up temporary debug instrumentation in the Path B provisioner image.
2. Add repo-managed RouterOS CHR and client launch helpers.
3. Promote the validated Path B flow in repo documentation and wiki source.
4. Begin the first real Ansible-driven imaging run over Path B.

## Data Safety

All repo-side changes from today are committed and pushed to the active Path B branch after validation.
