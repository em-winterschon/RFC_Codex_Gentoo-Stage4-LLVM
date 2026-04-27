# End of Day Status: 2026-04-27

## Summary

Today’s work turned the Path B simple-guest profile test from a lab boot demo
into a real installer validation run.

Validated live:

- a UEFI QEMU client now boots Path B correctly through an embedded
  `ipxe.efi`
- the Path B provisioner is reachable by SSH on the active DHCP lease
- the simple guest profile inventory is valid and loadable
- destructive storage on the target disk completed successfully
- `chroot-bootstrap` progressed into real stage3 bootstrap work and downloaded
  the stage3 tarball

## Problems Solved Today

1. Fixed the UEFI netboot handoff design for Path B.
   - plain UEFI firmware was being pointed at `bootstrap.ipxe`
   - firmware can lease DHCP but cannot execute the iPXE script directly
   - rebuilding `sys-firmware/ipxe` with `USE=uefi64` and embedding the
     bootstrap chain into `ipxe.efi` fixed the UEFI path
2. Identified the first missing provisioner dependency for installer reuse.
   - `liveiso_prepare` depends on `sgdisk`
   - the current Path B provisioner image did not include it
   - live validation continued by copying `/usr/bin/sgdisk` into the guest
3. Proved that Path B storage imaging works on the simple guest target disk.
   - target disk: `ata-QEMU_HARDDISK_stage4-root`
   - storage layout: `single-drive`
   - root pool: single-disk `rpool`
4. Identified the current upstream network gap in the lab.
   - RouterOS DHCP/iPXE worked
   - provisioner had no durable upstream route or DNS
   - temporary progress workaround was:
     - host-side IPv4 forwarding and NAT
     - guest-side default route to `10.9.8.108`
     - explicit `/etc/resolv.conf`

## Commits Landed Today

- none yet on `codex/add-gentoo-system-profiles` before this EOD packaging

## Open PRs

- `#13` ntfy reply listener
- `#14` private ntfy server deployment
- `#15` ZFS hostid / ZFSBootMenu commandline follow-up
- `#16` default LLVM/Clang Portage profile and linting
- `#17` Path B iPXE netboot workflow
- `#18` Gentoo system profiles and identity role

## Closed / Merged PRs Today

- none

## Outstanding Tasks

1. Encode the UEFI embedded-`ipxe.efi` launch flow into repo-managed Path B
   client launch helpers instead of ad hoc host commands.
2. Add the missing installer tool expectations to the Path B provisioner image,
   especially `sgdisk`.
3. Fix the `liveiso_prepare` command-check behavior under Ansible on the Path B
   provisioner so the workaround bypass is no longer needed.
4. Make upstream routing and DNS durable in the Path B lab.
   - preferred long-term fix: RouterOS upstream/WAN path
   - current temporary workaround: host NAT plus guest-side route override
5. Resume `chroot-bootstrap` from a stable provisioner session and carry the run
   through `target-integration` and installed-target reboot.

## Tomorrow / Next Tranche

1. stabilize Path B provisioner upstream networking
2. make the simple-guest provisioner environment fully compatible with the Path
   A installer expectations
3. rerun `chroot-bootstrap`
4. complete `target-integration`
5. boot the installed simple guest from its target disk and verify SSH plus the
   selected profile state

## Data Safety

Repo-side documentation for today’s Path B progress is now recorded in-tree.
The next step after this document is to commit and push the branch so no
progress remains local-only on the host.
