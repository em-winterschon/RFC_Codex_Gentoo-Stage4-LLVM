# Overnight Execution 2026-05-24

## Operating Rules

- Do not reboot or power-cycle any host without explicit operator approval.
- Do not use NetworkManager on the M70 lane.
- Do not switch PDU, ATS, or UPS outlets during unattended work.
- Do not mutate live switch or router configuration without a dry-run artifact
  and an explicit approval gate.
- NetBox remains the source of truth. Any inventory-derived changes must be
  represented as a dry-run plan before apply.
- Heavy package, kernel, and image jobs may run only when their dependency
  guards pass and logs are captured.

## Supervisor Lane: M70 Canary

Goal: finish the current canary package and initramfs validation chain without
leaving the node in an ambiguous state.

Current status:

- The selected package convergence run completed successfully.
- The final universal initramfs was regenerated and verified.
- Intel and AMD early microcode, ZFS boot content, and dracut
  `network-legacy` with `dhclient` are present in the canary initramfs.
- The canary Portage policy now allows two concurrent package builds, each
  using `MAKEOPTS=-j24`, against X12again's `172.16.99.108/48,lzo` distcc
  target.
- No reboot or power-cycle has been performed.

1. Wait for the active Ansible run to finish.
2. Record the Ansible recap and the last relevant package log lines.
3. If the run fails, stop live mutation and document the failing atom.
4. If the run succeeds, run:

   ```bash
   ssh root@172.16.99.22 '/root/gentoo-liveiso-work/chroot-runner.sh '\''set -o pipefail
   kver=6.18.32-p2-gentoo-dist-hardened
   dracut --force --no-hostonly --early-microcode "/boot/initramfs-${kver}.img" "${kver}"
   '\'''
   ```

5. Verify the artifact:

   ```bash
   ssh root@172.16.99.22 '/root/gentoo-liveiso-work/chroot-runner.sh '\''set -o pipefail
   img=/boot/initramfs-6.18.32-p2-gentoo-dist-hardened.img
   lsinitrd "$img" | grep -E "kernel/x86/microcode|AuthenticAMD|GenuineIntel"
   lsinitrd "$img" | grep -E "usr/bin/zfs$|usr/bin/mount.zfs|extra/zfs.ko|parse-zfs|mount-zfs" | head -40
   lsinitrd "$img" | grep -E "dhclient|network-legacy" | head -40
   '\'''
   ```

6. Do not reboot. Record the verified boot artifact state only.

## Worker Lane A: FMT2 Transport Evidence

Issues: #114, #68, #130.

Mode: read-only unless the operator returns.

1. Gather current repo-side FMT2 docs and previous notes:

   ```bash
   rg -n "FMT2|SFO-200|BigNetwork|R630|Arista|7060|RDMA" docs gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories
   ```

2. Build a gap table with these columns:
   `issue`, `host/device`, `expected source`, `observed evidence`,
   `missing validation`, `safe next command`.
3. Do not apply RouterOS, Arista, or switch changes.
4. Commit only documentation or validation-script changes that do not touch
   live inventory state.

## Worker Lane B: NetBox/IPAM/DNS Source-of-Truth

Issues: #31, #43, #69, #130.

Mode: dry-run first.

1. Run NetBox-to-DNS planning only:

   ```bash
   ./scripts/plan-hetzner-dns-from-netbox.py --help
   ./scripts/plan-hetzner-dns-from-inventory.py --help
   ```

2. Use existing credentials only through the repo-approved environment wrapper.
3. Produce a plan artifact before applying:
   `docs/reports/netbox-dns-gap-2026-05-24.md`.
4. Apply changes only for facts already confirmed in NetBox or operator-provided
   source data.
5. Do not invent IP addresses, CNAMEs, serial paths, or service names.

## Worker Lane C: Post-Install Assertions

Issues: #84, #85, #54.

Mode: repo-only; safe to run while live package jobs are idle or waiting.

1. Add failing tests for the assertions before implementation.
2. Cover at least:
   - dracut universal microcode policy
   - no NetworkManager in M70 roles
   - distcc guard before system package builds
   - DNS resolver validation before netboot publication
3. Run focused tests after each change:

   ```bash
   bash tests/shell/test_ci_builder_farm_roles.sh
   ```

4. Use separate commits for assertion additions and implementation fixes.

## Worker Lane D: Power and Observability Inventory

Issues: #57, #61, #43.

Mode: read-only.

1. Query SNMP capabilities for known APC PDU, ATS, and UPS management devices.
2. Record outlet names, model, firmware, and sensor/control OIDs.
3. Do not issue SNMP set operations.
4. Cross-check each device against NetBox before suggesting an update.

## Worker Lane E: RDMA and Fabric Policy

Issues: #130, #111, #112, #118.

Mode: design and validation only until FMT2 transport evidence is current.

1. Extract current RDMA-related docs and package role policy.
2. Identify required host groups:
   - Dell R630
   - Dell R730xd
   - M70 canary class
   - BlueField-2 and ConnectX hosts
3. Produce a no-apply validation checklist for:
   - MTU
   - VLAN
   - LACP boundary
   - RoCEv2/PFC/ECN assumptions
   - kernel/module/package requirements

## Concurrency Rules

- One live mutation lane at a time per target host.
- Multiple read-only lanes may run concurrently.
- M70 canary package builds may use two concurrent Portage jobs with
  `MAKEOPTS=-j24`, keeping the aggregate distcc compile envelope at 48 jobs
  against X12again.
- Repo workers must have disjoint write sets:
  - M70 canary role changes: installer roles and host vars only
  - FMT2 docs: `docs/FMT2-*`, `docs/RDMA-*`, report files
  - NetBox/DNS scripts: `scripts/plan-*`, tests for those scripts
  - Observability docs: `docs/reports/*`, SNMP validation notes
- Do not run two Ansible applies against `m70_canary` at the same time.
- Do not run a package merge and a boot role materialization concurrently in the
  same target chroot.

## Morning Handoff

Provide these exact items:

1. Current branch and commit hash.
2. Active PR number, if updated.
3. M70 canary package role result.
4. Initramfs verification result for Intel microcode, AMD microcode, ZFS, and
   dracut network legacy support.
5. Any NetBox/DNS gap plan generated overnight.
6. Any read-only FMT2 transport evidence gathered.
7. Clear list of operator-gated actions that still require hands-on approval.
