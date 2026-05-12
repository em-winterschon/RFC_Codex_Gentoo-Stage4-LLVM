# EOD Status 2026-05-11

## Completed

- Rebuilt and promoted the GMKtek K10 Path B Stage5 image through the Hasslehoff
  netboot publisher at `172.16.99.88`.
- Fixed the Path B artifact builder compressor fallback bug where the
  `mksquashfs` fallback log line polluted command-substitution stdout and
  caused an invalid compressor argument.
- Added a regression test requiring compressor fallback stdout to be exactly
  `gzip` while the fallback warning goes to stderr.
- Validated the promoted K10 artifacts over HTTP:
  - `vmlinuz`: `2163fd03518c6a8a021c0c3f5fc8a2b2f30f296bb385d8e31d591b5ffa4a1cec`
  - `initramfs.img`: `2729d85dbb3db756391aa0e6b1c0428fd004dc0391b98dded326a00c69c1a272`
  - `rootfs.img`: `c20127615df52e346616a76affc547a0055ad5f137514429a02c984291b24b81`
- Rebooted K10 through AP7901 outlet 6 and validated:
  - hostname: `gmktek-k10-stage5`
  - address: `172.16.99.156`
  - kernel: `6.18.28-gentoo-dist`
  - package tools: `age`, `jq`, `curl`, OpenSSH
  - SSSD IPA backend present
- Re-applied live FreeIPA client state to K10 using the gated playbook and
  validated floating central SSH login as `codex-admin`.
- Updated K10 E2ET evidence to reflect the 2026-05-12 UTC rebuild and reboot.
- Applied NetBox intake live with pre/post snapshots for K10, Chonkers, and
  AP7901 power-chain modeling:
  - pre snapshot: `nb-pre-k10-power-chain-20260512T020911Z`
  - post snapshot: `nb-post-k10-power-chain-20260512T021338Z`
- Modeled AP7901 power cabling in NetBox:
  - `outlet6 -> gmktek_nucbox_k10_stage5_candidate:power0`
  - `outlet4 -> lap_sun99_chonkers:power0`
- Verified NetBox intake idempotence after live apply:
  - `created=0`
  - `updated=0`
  - `existing=303`
- Sent local ntfy progress through the HTTPS LAN ntfy service.
- Committed and pushed the K10/NetBox delta:
  - `f30ec88 Validate K10 rebuild and NetBox power-chain intake`

## Verification

- `bash tests/shell/test_netbox_inventory_intake.sh`
  - result: pass
- `bash tests/shell/test_pathb_profile_inputs.sh`
  - result: pass
- `bash tests/shell/test_host_e2et_conformance_report.sh`
  - result: pass
- `bash tests/shell/test_host_e2et_policy_docs.sh`
  - result: pass
- `python3 -m py_compile scripts/netbox_apply_inventory_intake.py scripts/validate_netbox_inventory_intake.py scripts/host_e2et_conformance.py`
  - result: pass
- `python3 scripts/validate_netbox_inventory_intake.py gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/*.yml`
  - result: pass with the existing FMT2 warning for `172.16.40.10` outside declared prefixes
- NetBox API readback confirmed:
  - K10 primary IP `172.16.99.156/24`
  - Chonkers primary IP `172.16.99.157/24`
  - AP7901 primary IP `172.16.99.241/24`
  - both AP7901 outlet-to-host cable objects connected

## Current Gates

- K10 package/rootfs durability is validated.
- K10 transient FreeIPA/SSSD enrollment is validated.
- K10 E2ET remains blocked for release because unattended reboot-durable host
  enrollment has not yet been proven without embedding `/etc/krb5.keytab` in
  public HTTP netboot artifacts.
- Secure first-boot enrollment scaffold exists, but the remaining work is the
  producer/apply path:
  - create or stage host-bound age identity outside the public rootfs
  - generate a short-lived FreeIPA host OTP
  - render and validate the bundle
  - encrypt to the host age recipient
  - publish the encrypted bundle
  - boot K10 and have `stage5-firstboot-enroll` consume it
  - validate keytab, SSSD, NSS, PAM, SSH, sudo policy, and reboot durability
- As of the EOD pass, K10 had ARP evidence for MAC `84:47:09:5f:21:64` but did
  not answer ICMP or SSH. The next K10 validation window should begin with a
  controlled AP7901 outlet reboot.

## Major Pivots And Errors

- The root cause of the K10 artifact failure was not package build failure; it
  was stdout contamination in the compressor fallback helper. The package build
  had completed successfully before artifact generation failed.
- The first promotion attempt hit publisher disk pressure while duplicating
  installer/rescue artifacts. The retry used hardlinks for rescue staging and
  left a rollback backup under the publisher artifact backup tree.
- NetBox power-chain modeling required real `dcim.cable` objects. The previous
  `mark_connected` approach could express intent but could not model the
  actual PDU outlet to host power-port relationship.

## Outstanding Actions

1. Complete the secure first-boot producer/apply workflow for K10.
2. Decide the persistent identity boundary for K10:
   - preferred release-grade path: disk-installed host with local age identity
   - acceptable lab proof: explicitly documented transient firstboot exercise
   - not acceptable: embedding private age identity or keytab in public HTTP
     rootfs artifacts
3. Add Tang/Clevis as optional NBDE infrastructure:
   - Tang service role and profile
   - Clevis client package/profile policy from Guru
   - `tpm2+tang` binding policy for host-bound unlock
4. Rebuild or re-run K10 only after the enrollment producer/apply path is ready
   enough to improve the E2ET result.
5. Continue NetBox DCIM deep modeling for interfaces, LAGs, optics, and cable
   terminations across CRS309, CRS354, CSS326, Hasslehoff, QNAP, K10, and
   Chonkers.
6. Continue X12AGAIN reimage preparation:
   - workstation profile
   - AMDGPU display/compute policy
   - Optane PMEM driver and tools
   - hypervisor overlay
   - rollback and off-host backup state

## Backout Summary

- K10 netboot promotion has a publisher-side rollback backup:
  `/opt/gentoo-netboot/path-b/artifacts.backups/k10-before-20260512T015753Z`.
- NetBox has ZFS-backed pre/post snapshots on VM `1062`:
  - rollback to `nb-pre-k10-power-chain-20260512T020911Z` if the power-chain
    import proves incorrect
  - keep `nb-post-k10-power-chain-20260512T021338Z` as the known-good
    post-apply state
- The K10/NetBox repo delta is commit `f30ec88`. Revert that commit if the
  repo-side intake or E2ET evidence must be backed out.

## Next Work Block

1. Commit this EOD report and wiki mirror.
2. Add the secure first-boot bundle producer/apply workflow.
3. Add Tang/Clevis service-role and package-profile scaffolding as optional
   NBDE hardening, not as the K10 default.
4. Run a controlled K10 PDU reboot and execute the next K10 firstboot/E2ET
   validation sequence.
5. Record query-cycle timing guidance in `AGENTS.md` and begin using EOD/SITREP
   documents as the durable project-memory sink until the structured analytics
   store exists.

## Overnight Follow-Up

- Added and pushed the secure firstboot producer/apply workflow:
  - `scripts/stage_secure_firstboot_bundle.py`
  - `playbooks/secure-firstboot-bundle-stage.yml`
  - repo-output refusal for encrypted bundles unless explicitly overridden
  - `no_log: true` coverage on OTP/encrypted bundle handling
- Added optional Tang/Clevis NBDE scaffolding:
  - `vm-tang-nbde-server`
  - `secure-firstboot-nbde-client`
  - `tang_nbde_server` role
  - required policy: `tpm2+tang`, not Tang-only
- Normalized Portage license defaults to `ACCEPT_LICENSE="*.*"`.
- Wired Path B builds for persistent `/srv/build-cache` distfile/binpkg binds
  and buildpkg defaults.
- Started a fresh K10 Path B rebuild inside `x12again-stagebuild-k10`:
  - builder SSH: `127.0.0.1:2230`
  - log: `/var/log/k10-pathb-rebuild-current.log`
  - first failed gate: missing root SSH key source
  - fix: `SSH_AUTHORIZED_KEY_FILE=/root/.ssh/authorized_keys`
  - status at `2026-05-12T05:33:54Z`: emerge running, `96/103` package phase
    reached; `openldap` completed and `gentoo-kernel-6.18.29` was emerging
- Added planning docs and wiki pages for:
  - agent memory and analytics
  - Coherence-CE service role
  - RDMA storage fabric
  - AI/ML HPC supercomputer meta-analysis
  - X12AGAIN target installed workstation/hypervisor profile
- Added masked, mutation-gated Coherence-CE service scaffolding:
  - `vm-coherence-ce-node`
  - `coherence_ce_service` role
  - `dev-java/oracle-coherence-ce` local overlay placeholder
  - Jenkins-pinned build requirement before unmasking

Follow-up commits after the initial EOD report:

- `77a3b08 Record 2026-05-11 EOD and roadmap updates`
- `03cd288 Add secure firstboot NBDE staging scaffolds`
- `c390f04 Clarify Path B multi-profile rebuild command`
- `5e4a838 Default Portage license acceptance to all licenses`
- `5a66c99 Enable persistent Path B build caches`
- `f9ec19c Document Path B SSH key bootstrap gate`
- `cf5f0af Add agent memory and RDMA planning docs`
- `be329ac Add Coherence CE service role scaffold`
