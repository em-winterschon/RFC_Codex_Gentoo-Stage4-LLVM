# Overnight Execution 2026-05-25

## Operating Rules

- Do not use NetworkManager on the M70 lane.
- Do not run two Ansible applies against `m70_canary` at the same time.
- Do not write to, wipe, repartition, or repurpose the SATADOM without explicit
  operator approval.
- Do not flash BIOS without a vendor-matched `FWS-2363` or AppNeta M70 image
  and a rollback plan.
- Do not mutate live switch, router, ATS, UPS, or PDU state unless the operator
  explicitly requests it.
- Use SSH host aliases such as `m70_canary` and `x12again`; do not use raw
  `ssh root@IP` command forms in new workflow notes.
- NetBox remains source of truth. Any inventory or DNS apply must be preceded
  by a dry-run plan.

## Lane A: M70 Canary Boot Durability

Goal: replace the temporary iPXE bridge dependency with a durable local boot
path that the current M70 firmware can actually enumerate.

Current evidence:

- Direct NVMe boot options do not appear in Aptio Setup.
- CSM-disabled mode still does not expose NVMe in boot priorities or UEFI BBS
  priorities.
- CSM-enabled mode is required for the known legacy PXE rescue path.
- UEFI BBS priorities list the SATADOM and `none`.
- The safe persistent design is SATADOM EFI carrier -> ZFSBootMenu -> NVMe
  `rpool/ROOT/gentoo`.

Allowed overnight work:

1. Prepare a SATADOM EFI carrier plan and rollback checklist in docs.
2. Add repo-side validation tests for the SATADOM carrier plan.
3. Inspect the current target layout from a non-destructive boot only after the
   canary exits BIOS setup and SSH returns.
4. If the canary boots through the temporary iPXE bridge, collect read-only
   evidence:

   ```bash
   ssh m70_canary 'lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,PARTUUID,MOUNTPOINTS'
   ssh m70_canary 'findmnt -R /boot /boot/efi 2>/dev/null || true'
   ssh m70_canary 'zpool status; zfs list -o name,mountpoint,canmount,mounted'
   ```

Blocked without operator approval:

- mounting the SATADOM read-write
- formatting or changing SATADOM partition tables
- copying EFI payloads to the SATADOM
- changing firmware setup options through serial automation
- power-cycling the canary while the operator is using the serial console

## Lane B: M70 Canary Recovery

Goal: keep the canary recoverable if it remains in firmware setup or fails to
return to SSH.

1. Check for active serial users before touching the serial device:

   ```bash
   fuser -v /dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if01-port0
   ```

2. Do not attach to serial if the operator is using it.
3. Keep `/root/m70-canary-netboot-shim/hosts/m70-canary.ipxe` pointed at the
   installed-root bridge role unless a rescue boot is required.
4. If rescue is required, record the exact shim change and restore it before
   final handoff.

## Lane C: SLURM Pilot Repo Work

Goal: advance SLURM without making the M70 canary a dependency while it is still
the boot-path blast target.

Allowed overnight work:

1. Review `docs/SLURM-PILOT-BRINGUP.md` against current NetBox/DNS source of
   truth.
2. Produce dry-run gaps for:
   - controller VM record
   - first worker VM record
   - A/CNAME records for `sched-sun99-slurmctl-099071.rfc1918.host`
   - service targets for `slurmctld`, `slurmdbd`, MUNGE, and MariaDB
3. Run repo tests that validate SLURM roles:

   ```bash
   bash tests/shell/test_slurm_workload_scheduler_role.sh
   bash tests/shell/test_slurm_pilot_readiness.sh
   bash tests/shell/test_slurm_live_apply_playbook.sh
   ```

4. Update docs and tests only. Keep live SLURM service mutation gated until the
   controller VM target and secrets are confirmed.

Blocked without operator approval:

- live SLURM apply
- MUNGE key generation or distribution
- MariaDB/slurmdbd secret creation outside the approved vault flow
- assigning a new IP address not already modeled in NetBox

## Lane D: Distcc And Build Policy

Goal: keep canary and future M70 build policy aligned with X12again resources.

Allowed overnight work:

- repo-side validation of `DISTCC_HOSTS=172.16.99.108/48,lzo`
- tests for `DISTCC_FALLBACK=0`
- docs updates for two concurrent package builds with `MAKEOPTS=-j24`

Do not start large package or kernel builds unless the canary is fully booted
and the distcc guard passes immediately before the job.

## Morning Handoff

Report these exact items:

1. Current branch and commit hash.
2. Whether the M70 canary is in BIOS setup, iPXE bridge boot, rescue live root,
   or installed ZFS root.
3. Whether SATADOM EFI carrier planning has changed any files.
4. Any NetBox/DNS/SLURM dry-run gaps.
5. Tests run and exact result.
6. Actions still blocked on operator approval.
