# EOD Status 2026-05-11

## Completed

- Rebuilt and promoted the GMKtek K10 Path B Stage5 image through the Hasslehoff
  netboot publisher at `172.16.99.88`.
- Fixed the Path B artifact builder compressor fallback bug where the
  `mksquashfs` fallback log line polluted command-substitution stdout.
- Rebooted K10 through AP7901 outlet 6 and validated kernel
  `6.18.28-gentoo-dist`, SSSD IPA backend availability, and live FreeIPA
  client apply plus floating `codex-admin` SSH login.
- Applied NetBox intake live with pre/post snapshots:
  - `nb-pre-k10-power-chain-20260512T020911Z`
  - `nb-post-k10-power-chain-20260512T021338Z`
- Modeled AP7901 power cabling:
  - `outlet6 -> gmktek_nucbox_k10_stage5_candidate:power0`
  - `outlet4 -> lap_sun99_chonkers:power0`
- Verified NetBox intake idempotence after live apply: `created=0`,
  `updated=0`, `existing=303`.
- Committed and pushed `f30ec88 Validate K10 rebuild and NetBox power-chain intake`.

## Current Gates

- K10 package/rootfs durability and transient FreeIPA/SSSD enrollment are
  validated.
- K10 release E2ET remains blocked until unattended reboot-durable host
  enrollment is proven without embedding `/etc/krb5.keytab` in public HTTP
  netboot artifacts.
- The next K10 validation window should begin with a controlled AP7901 outlet
  reboot because ICMP/SSH were not responding during the EOD follow-up check.

## Next Work Block

1. Add the secure first-boot bundle producer/apply workflow.
2. Add Tang/Clevis service-role and package-profile scaffolding as optional
   NBDE hardening.
3. Run the next K10 firstboot/E2ET validation sequence.
4. Continue NetBox deep DCIM modeling and X12AGAIN reimage preparation.

## Overnight Follow-Up

- Added the secure firstboot producer/apply workflow, including
  `stage_secure_firstboot_bundle.py`, `secure-firstboot-bundle-stage.yml`,
  encrypted bundle repo-output refusal, and `no_log` coverage.
- Added Tang/Clevis NBDE scaffolding with required `tpm2+tang` policy.
- Normalized Portage defaults to `ACCEPT_LICENSE="*.*"`.
- Wired Path B persistent distfile/binpkg cache binds and buildpkg defaults.
- Started a fresh K10 rebuild inside `x12again-stagebuild-k10`; current log is
  `/var/log/k10-pathb-rebuild-current.log` on the builder VM.
- Added agent-memory, Coherence-CE, RDMA storage fabric, HPC meta-analysis, and
  X12AGAIN reimage planning docs.
- Added masked, mutation-gated Coherence-CE service scaffolding with a local
  overlay placeholder and Jenkins-pinned build requirement.
