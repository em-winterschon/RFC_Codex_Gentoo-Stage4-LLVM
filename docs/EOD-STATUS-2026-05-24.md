# EOD Status 2026-05-24

## Completed

- Continued M70 canary persistent Gentoo work on branch
  `m70-canary-validation-lane`.
- Implemented the approved universal dracut policy:
  - target Portage renders
    `/etc/dracut.conf.d/95-universal-netboot-microcode.conf`
  - `hostonly="no"` is enforced for generic artifacts
  - `early_microcode="yes"` is enforced
  - the boot role now materializes initramfs with
    `dracut --force --no-hostonly --early-microcode`
- Regenerated the M70 canary initramfs once after the policy landed.
- Verified the rebuilt canary initramfs contains both CPU vendor payloads:
  - `kernel/x86/microcode/AuthenticAMD.bin`
  - `kernel/x86/microcode/GenuineIntel.bin`
- Verified the rebuilt canary initramfs still carries ZFS boot material:
  - `usr/bin/zfs`
  - `usr/bin/mount.zfs`
  - `usr/lib/modules/6.18.32-p2-gentoo-dist-hardened/extra/zfs.ko`
  - dracut ZFS cmdline and mount hooks
- Identified the universal dracut network helper gap:
  - `network-legacy` needs `dhclient`
  - `ip` and `arping` were already present
  - NetworkManager remains banned and masked
- Added `net-misc/dhcp` to the base no-X package list so future universal
  initramfs builds can include dracut legacy network support without
  NetworkManager or systemd-networkd.
- Added package.use policy for `net-misc/dhcp client -server` in the active
  LLVM/no-systemd profile path and the base minimal profile.
- Re-ran selected Ansible roles with the correct dependency order:
  `preflight`, `portage`, `distcc_farm`, `system_packages`.
- Confirmed the distcc guard passed before package work:
  - distcc wrapper path is present in target Portage `PATH`
  - `DISTCC_HOSTS` is populated
  - `DISTCC_FALLBACK=0`
  - configured `MAKEOPTS` policy is active
- Confirmed the current system package merge includes `net-misc/dhcp`.
- Completed the selected `system_packages` role after the DHCP policy landed.
- Regenerated the M70 canary initramfs again after package convergence.
- Verified the final rebuilt canary initramfs contains:
  - Intel early microcode
  - AMD early microcode
  - ZFS userspace, module, and dracut hooks
  - dracut `network-legacy` content with `dhclient`
- Increased the canary distcc package concurrency policy for X12again:
  - `EMERGE_DEFAULT_OPTS` now includes `--jobs=2 --load-average=16`
  - `MAKEOPTS=-j24`
  - `DISTCC_HOSTS=172.16.99.108/48,lzo`
  - `DISTCC_FALLBACK=0`
  - effective remote compile envelope is 48 jobs across two concurrent
    Portage package builds

## Verification

- `bash tests/shell/test_ci_builder_farm_roles.sh`
  - result: pass
- `ansible-playbook ... --limit m70_canary -e '{"selected_roles":["preflight","portage"]}'`
  - result: pass
  - changed target dracut policy files only
- `lsinitrd /boot/initramfs-6.18.32-p2-gentoo-dist-hardened.img`
  - result: Intel and AMD microcode payloads present
  - result: ZFS userspace, module, and hooks present
  - result: dracut `network-legacy` and `dhclient` content present
- `system_packages` selected role run
  - result: pass
- `dracut --force --no-hostonly --early-microcode`
  - result: pass after package convergence
- `portageq envvar` on the canary chroot
  - result: `MAKEOPTS=-j24`
  - result: `EMERGE_DEFAULT_OPTS=--jobs=2 --load-average=16 ...`
  - result: `DISTCC_HOSTS=172.16.99.108/48,lzo`
  - result: `DISTCC_FALLBACK=0`
- `ansible-playbook ... --limit m70_canary --syntax-check`
  - result: pass
- `gh issue list --repo yukon-systems/RFC_Codex_Gentoo-Stage4-LLVM --state open`
  - result: open issue list available for overnight prioritization

## Current Gate

- No Ansible or package merge job is currently running from this lane.
- The package convergence and final initramfs verification chain completed.
- No reboot or power cycle has been performed.
- No live switch, router, PDU outlet, ATS, or UPS mutation has been performed.

## Active Runtime State

- M70 canary SSH remains available at `root@172.16.99.22`.
- X12again distcc target remains `172.16.99.108`.
- The canary package apply path uses the target chroot runner:
  `/root/gentoo-liveiso-work/chroot-runner.sh`.
- NetworkManager remains prohibited by policy.
- Temporary canary netboot and shim state remains in place until the persistent
  boot path is validated and explicitly retired.

## Highest Priority Open Issues

- Issue #130: `FMT2-007: Validate R630 front-end and RDMA fabric policy on Arista 7060`
  - labels: `priority:high`, `status:active`, `needs-validation`
  - best overnight mode: read-only evidence capture and repo-side validation
- Issue #114: `FMT2-005: Bring up BigNetwork L2 path for FMT2/SFO-200 discovery`
  - labels: `priority:high`, `status:active`
  - best overnight mode: dependency-chain validation before any live changes
- Issue #68: `[FMT2-002] Validate FMT2 transport path from RFC99/SUN99`
  - labels: `status:active`
  - best overnight mode: confirm path observations and document gaps
- Issue #31: `[PNR-013] Use NetBox to drive provisioning inventory and IPAM maps`
  - labels: `status:active`
  - best overnight mode: dry-run NetBox/IPAM and DNS gap analysis
- Issue #43: `[PNR-030] Promote K10 and AP7901 PDU operational discoveries into NetBox`
  - labels: `status:active`
  - best overnight mode: source-of-truth cleanup from already observed facts
- Issue #57: `[AAA-005] Enroll APC PDUs, APC ATS, and UPS management cards into central RADIUS auth`
  - labels: `status:active`
  - best overnight mode: read-only auth/SNMP capability capture
- Issue #61: `[OBS-004] Validate SNMP modules for UPS, ATS, PDU, and OOB devices`
  - labels: `status:backlog`
  - best overnight mode: read-only SNMP module discovery; no outlet switching
- Issue #84: `[MT-003] Add post-install assertion stages`
  - labels: `status:backlog`
  - best overnight mode: repo-side test and assertion implementation after the
    canary merge result is known

## Outstanding Actions

1. Commit the universal dracut, DHCP helper, and distcc/package-policy changes
   once runtime verification is complete.
2. Keep the next overnight work lanes read-only unless a lane has isolated
   files, an idempotent dry-run, and no dependency on the live M70 package job.
3. Before the next kernel rebuild, dry-run the reduced-context embedded kernel
   patch hunks that were normalized to satisfy whitespace checking.
