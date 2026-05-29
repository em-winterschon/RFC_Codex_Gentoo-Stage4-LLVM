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
- Completed the approved non-destructive SATADOM EFI carrier implementation:
  - SATADOM ESP:
    `/dev/disk/by-id/ata-SATADOM-SH_3ME3_20180915AA9241033080-part1`
  - ESP PARTLABEL: `efiboot0`
  - FAT UUID: `86DA-0813`
  - backup path:
    `/root/m70-canary-satadom-backups/20260525T062728Z`
  - copied `EFI/ZBM/VMLINUZ.EFI` and `EFI/BOOT/BOOTX64.EFI`
  - both copied EFI files hashed to
    `1e08335d697fed772af3ecbccf1724227cdbdfa02aec221ced8a332bd44670bf`
- Booted the canary twice through the durable local path:
  SATADOM -> ZFSBootMenu -> `/boot/vmlinuz-6.18.32-p2-gentoo-dist-hardened`
  -> `rpool/ROOT/gentoo`.
- Fixed the local-boot NIC naming gap by installing
  `/etc/udev/rules.d/10-m70-canary-net-names.rules` on the canary and modeling
  the same MAC-based rules in Ansible `profile_udev_rules_files`.
- Verified the second SATADOM local boot brings up `bond_mgmt` with both
  `netboot0` and `enp3s0`, active slave `netboot0`, and no iPXE-only
  `ifname=netboot0` kernel argument.
- Repaired the live canary distcc client path by applying only `preflight` and
  `distcc_farm` to the installed root at `/`; this rendered compiler wrappers,
  enabled `FEATURES=distcc`, set `MAKEOPTS=-j24`, and kept
  `DISTCC_FALLBACK=0`.
- Verified a fallback-disabled canary `gcc` probe compile completed remotely on
  X12again through the managed distcc wrapper path.
- Recorded LTC Forge's distcc expansion reply. The next approved canary distcc
  policy is `MAKEOPTS="-j16 -l12"` with
  `DISTCC_HOSTS="10.200.99.23/24,lzo 172.16.99.108/48,lzo localhost/2"`.
  The `kvm-sfo200-sec-9923` worker is live and validated, but its Podman/OCI
  distccd service still needs durable persistence before assuming reboot
  survival.
- Applied the approved distcc expansion to the persistent canary OS with only
  selected roles `preflight` and `distcc_farm`, targeting `/`.
- Fixed the FreeIPA live-apply playbook so its read-only root break-glass check
  runs during check mode, then dry-ran canary enrollment through the local
  config-render phase.
- Held FreeIPA/SSSD live enrollment because the delegated
  `svc_identity_ipa01` controller SSH path is not currently accepted for this
  Forge shell; no canary auth mutation was applied from that dry-run.
- Updated M70 canary docs and wiki mirror with the installed-root validation,
  OVS/LACP state, SSSD gating, and firmware/SATADOM boot-path findings.
- Updated PR #144 with installed-root validation evidence.

## Verification

- `ssh m70_canary 'hostname -f; findmnt -no SOURCE,FSTYPE /; rc-status default'`
  - result: pass during installed-root validation
- `ssh m70_canary 'cat /proc/cmdline; cat /proc/net/bonding/bond_mgmt'`
  - result: local SATADOM boot command line has no iPXE role artifacts
  - result: `bond_mgmt` has `netboot0` and `enp3s0`, active slave `netboot0`
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
- `ssh m70_canary` Portage/distcc probe
  - result: `MAKEOPTS=-j24`, `DISTCC_FALLBACK=0`, `FEATURES` includes
    `distcc`, PATH includes `/usr/local/libexec/distcc-farm/bin`
  - result: probe compile completed on X12again with fallback disabled
- LTC Forge distcc expansion reply
  - result: approved next `DISTCC_HOSTS` is
    `10.200.99.23/24,lzo 172.16.99.108/48,lzo localhost/2`
  - result: approved next `MAKEOPTS` is `-j16 -l12`
  - result: sec and X12AGAIN fallback-disabled smoke compiles were reported as
    passing by LTC Forge
- `m70_canary` approved distcc live apply
  - result: selected-role dry-run changed only `/etc/distcc/hosts`,
    `/etc/distcc/builder-farm.json`, and the managed distcc block in
    `/etc/portage/make.conf`
  - result: live apply completed with the same scoped changes
  - result: `portageq envvar MAKEOPTS` returns `-j16 -l12`
  - result: `portageq envvar DISTCC_HOSTS` returns
    `10.200.99.23/24,lzo 172.16.99.108/48,lzo localhost/2`
  - result: fallback-disabled canary compile probes passed for sec, X12AGAIN,
    and the combined host string
- `ipa-client-live-apply.yml --check --diff -l m70_canary`
  - result: local canary config-render phase reached
  - result: held before live apply because delegated controller SSH failed
- `bash tests/shell/run-tests.sh`
  - result: pass
- `gh pr comment 144`
  - result: PR comment added with validation evidence

## Commits And PRs

- Branch: `m70-canary-validation-lane`
- Latest pushed commit before this EOD update:
  `3793b82 docs: plan canary SATADOM and SLURM overnight gates`
- PR: `#144` - `Document M70 canary validation lane`
- PR comment:
  `https://github.com/yukon-systems/RFC_Codex_Gentoo-Stage4-LLVM/pull/144#issuecomment-4530636020`

## Current Runtime State

- The canary now boots normally from the SATADOM EFI carrier through
  ZFSBootMenu into the NVMe ZFS root.
- The temporary M70 canary shim still exists as a rescue bridge for MAC
  `00:07:32:58:73:34`, but it is no longer the normal boot dependency.
- The canary serial console was released after the successful SATADOM and udev
  validation reboots.
- No serial reader remains active from Forge after the handoff.
- The primary Forge M70 remains reachable.
- X12again remains the approved distcc target at `172.16.99.108`.
- The canary persistent OS is now a distcc client for compile work; it is not a
  distccd worker.

## Open Gates

1. Direct NVMe boot is not supported by observed firmware behavior.
2. Do not flash BIOS unless a vendor-matched `FWS-2363` / AppNeta M70 image is
   obtained and staged with a rollback plan.
3. FreeIPA/SSSD client enrollment remains pending; `sssd` should not be enabled
   until the delegated controller SSH path and keytab generation pass.
4. Repeat the SATADOM carrier + udev naming profile path on the next M70 before
   promoting it to the fleet baseline.
5. SLURM controller/worker work should remain coordinated with LTC Forge and
   live-gated until controller VM placement and service ownership are final.

## Overnight Priority

Primary overnight lane:

1. Keep the M70 canary safe and recoverable.
2. Convert the live SATADOM and udev fix into repeatable profile-driven
   application for the next M70.
3. Reduce boot/kernel noise that is now visible after local boot, starting with
   M70-specific module lists and PCI resource warnings.

Secondary overnight lane:

1. Continue SLURM pilot work only through repo validation, NetBox/DNS dry-run
   planning, and service checklist updates.
2. Avoid live scheduler or host mutation that depends on the canary until the
   canary boot path is stable.
3. Keep X12again as a distcc resource but do not make it a hard dependency for
   the first SLURM controller.

## Additional Thor AGX Historical Context

## Historical Context

This closeout records the 2026-05-25 Thor inference lane. It is preserved for
operator traceability, but the temporary Docker transition assumptions in the
original handoff have been superseded by the later validated Podman plus NVIDIA
CDI state now recorded in `docs/THOR-AGX-INFERENCE-READINESS.md`.

## Completed

- PR #155 for inference service playbooks was merged into `main` before this
  EOD lane began.
- Thor AGX was modeled as `agx_rfc99_bunnydev_099034` for Ollama and Open WebUI
  first; vLLM and SGLang remain deferred until arm64/L4T/CUDA 13 images are
  validated.
- Added a Thor inventory regression test and wired it into the shell gate.
- Fixed the inference role check-mode path: service enable/start tasks are
  skipped during `ansible-playbook --check`, because planned unit files are not
  present on the target until a real apply.
- Preserved Docker/NVIDIA wrapper compatibility: explicit legacy Docker wrapper
  rendering uses `--gpus all`, while the active Thor service path remains
  Podman/CDI with `nvidia.com/gpu=all`.
- Ran Thor playbook validation and a bounded artifact deployment during the
  original 2026-05-25 lane; later validation promoted the current Podman/CDI
  state.

## Current Gates

- Docker is not the active Thor deployment path. Keep Docker masked/inactive
  unless a separate operator-approved maintenance window changes host policy.
- `openipmi.service` remains a known failed unit to track separately.
- vLLM and SGLang remain deferred on Thor. No arm64/L4T/CUDA 13 image path is
  accepted yet.

## Validation

- `bash tests/shell/test_thor_inference_inventory.sh`
- `bash tests/shell/test_inference_service_role_core.sh`
- `bash tests/shell/test_inference_service_playbooks.sh`
- `bash tests/shell/test_inference_service_docker_nvidia_wrapper.sh`
- Later full-suite validation is tracked on the branch/PR that reconciles this
  EOD note with the current Podman baseline.

## Recommendations

- Keep Thor inventory Podman-first with NVIDIA CDI.
- Use the Docker wrapper support only as a compatibility renderer for explicitly
  approved legacy exception artifacts.
- Start with Ollama before Open WebUI after any future runtime changes.
- Leave vLLM and SGLang out of Thor host groups until a known-good arm64/L4T
  image and launch command are committed.

## Backout Summary

- The historical 2026-05-25 apply was limited to service artifacts. Backout is
  to remove `/etc/inference-services/{ollama,open-webui}.env`,
  `/usr/local/libexec/inference-services/run-{ollama,open-webui}.sh`, and
  `/etc/systemd/system/inference-{ollama,open-webui}.service`, then run
  `systemctl daemon-reload`.
