# EOD Status 2026-05-25

## Completed

- Continued M70 canary persistent Gentoo validation on branch
  `m70-canary-validation-lane`.
- Booted the M70 canary installed Gentoo root through the temporary local iPXE
  bridge served from the primary M70 at `172.16.99.70:8080`.
- Verified the installed root state:
  - hostname/FQDN: `sbsoc-accel-int64-m70n2.rfc1918.host`
  - root filesystem: `rpool/ROOT/gentoo` mounted as ZFS
  - pool state: `rpool ONLINE`, read-write
  - management address: `172.16.99.22/24` on `bond_mgmt`
  - `ovsdb-server`, `ovs-vswitchd`, and `m70-ovs-fabric` started cleanly
  - OVS bridge `br_ovs0` and bond `ovs_workload0` exist
  - `ovs_workload0` reports `lacp_status: negotiated`
  - `eno1`, `eno2`, `eno3`, and `eno4` are enabled OVS bond members
- Fixed target-side Open vSwitch startup blockers:
  - initialized `/var/lib/openvswitch/conf.db`
  - pinned `/etc/conf.d/ovsdb-server` to
    `DATABASE="/var/lib/openvswitch/conf.db"`
  - installed `/usr/local/libexec/m70-ovs-fabric` matching the repo-modeled
    canary OVS fabric intent
- Seeded the canary target root SSH keyring from the primary M70
  `/root/.ssh/authorized_keys` contents and updated `m70_canary.yml` so future
  rebuilds carry the same operator/Forge public keys.
- Removed `sssd` from the canary default runlevel because the FreeIPA client
  enrollment path has not yet rendered `/etc/sssd/sssd.conf`.
- Updated the `aaa-domain-client` profile so it carries packages and USE policy
  but leaves `sssd` enablement to the FreeIPA enrollment apply path.
- Reboot-tested the canary installed-root path after the `sssd` runlevel fix.
  The second installed-root boot returned cleanly with all expected canary
  services started and no `sssd` failure in the default runlevel.
- Investigated M70 firmware behavior with operator serial-console assistance:
  - platform: AppNeta `m70 r01`, AAEON `FWS-2363 V1.0`
  - BIOS: AMI `V0472M22`, dated `2021-04-14`
  - BIOS screen labels the build as `m70 R2.2 (V0472M22)(04/14/2021)`
  - CSM enabled exposes legacy PXE controls and the known network boot path
  - CSM disabled does not expose NVMe boot options
  - UEFI BBS priorities list the SATADOM plus `none`
  - no direct NVMe boot option appeared after CSM was disabled
- Checked public AAEON download paths for a matching BIOS:
  - `FWS-2360` and `FWS-2365` BIOS directories exist
  - direct public `FWS-2363` BIOS directories returned 404
  - no safe public `FWS-2363` BIOS update was identified
  - cross-flashing nearby `FWS-2360` or `FWS-2365` firmware is not accepted
- Confirmed the likely durable boot design:
  - keep Gentoo root on the mirrored NVMe `rpool`
  - use the SATADOM as the persistent EFI boot carrier
  - place the fallback EFI loader at `EFI/BOOT/BOOTX64.EFI`
  - boot ZFSBootMenu from SATADOM, then import and boot the NVMe ZFS root
- Updated M70 canary docs and wiki mirror with the installed-root validation,
  OVS/LACP state, SSSD gating, and firmware/SATADOM boot-path findings.
- Updated PR #144 with installed-root validation evidence.

## Verification

- `ssh m70_canary 'hostname -f; findmnt -no SOURCE,FSTYPE /; rc-status default'`
  - result: pass during installed-root validation
- `ovs-appctl bond/show ovs_workload0`
  - result: `lacp_status: negotiated`
  - result: `eno1` through `eno4` enabled
- `git diff --check`
  - result: pass
- `bash tests/shell/test_m70_canary_docs.sh`
  - result: pass
- `bash tests/shell/test_pathb_profile_inputs.sh`
  - result: pass
- `bash tests/shell/test_live_ipa_client_enrollment.sh`
  - result: pass
- `bash tests/shell/run-tests.sh`
  - result: pass
- `gh pr comment 144`
  - result: PR comment added with validation evidence

## Commits And PRs

- Branch: `m70-canary-validation-lane`
- Latest pushed commit before this EOD:
  `a7d3479 Validate M70 canary installed root`
- PR: `#144` - `Document M70 canary validation lane`
- PR comment:
  `https://github.com/yukon-systems/RFC_Codex_Gentoo-Stage4-LLVM/pull/144#issuecomment-4530636020`

## Current Runtime State

- The temporary M70 canary shim still points MAC `00:07:32:58:73:34` at the
  installed-root iPXE bridge role:
  `/root/m70-canary-netboot-shim/roles/m70-canary-zfsroot.ipxe`.
- The canary serial console was released back to the operator after the
  CSM-disabled/CSM-restored BIOS checks.
- The last passive serial observation showed the canary in Aptio Setup, not yet
  booted back to the iPXE bridge.
- No serial reader remains active from Forge after the handoff.
- The primary Forge M70 remains reachable.
- X12again remains the approved distcc target at `172.16.99.108`.

## Open Gates

1. Persistent canary boot without the temporary iPXE bridge is still open.
2. Direct NVMe boot is not supported by observed firmware behavior.
3. The next durable boot implementation should stage a SATADOM EFI carrier for
   ZFSBootMenu, not depend on firmware NVMe boot enumeration.
4. Do not repurpose or wipe the SATADOM without explicit operator approval.
5. Do not flash BIOS unless a vendor-matched `FWS-2363` / AppNeta M70 image is
   obtained and staged with a rollback plan.
6. FreeIPA/SSSD client enrollment remains pending; `sssd` should not be enabled
   until `/etc/sssd/sssd.conf` exists.
7. SLURM controller/worker work should remain repo-side, VM-side, or read-only
   until the M70 canary is out of firmware setup and its boot path is stable.

## Overnight Priority

Primary overnight lane:

1. Keep the M70 canary safe and recoverable.
2. Convert the canary boot plan from "temporary iPXE bridge" to "SATADOM EFI
   carrier" documentation and implementation scaffolding.
3. Prepare the SATADOM EFI staging steps, validation checks, and rollback plan
   without destructive writes until operator approval is explicit.

Secondary overnight lane:

1. Continue SLURM pilot work only through repo validation, NetBox/DNS dry-run
   planning, and service checklist updates.
2. Avoid live scheduler or host mutation that depends on the canary until the
   canary boot path is stable.
3. Keep X12again as a distcc resource but do not make it a hard dependency for
   the first SLURM controller.
