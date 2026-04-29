# End of Day Status: 2026-04-28

## Summary

Today moved the project from "long source build with fragile local state" to a
durable Stage4/Stage5 binpkg workflow with a live repository VM, explicit
builder publication path, and enough synced packages to avoid throwing away
successful work after each blocker.

Validated live:

- `binpkg-repository` VM is online at `10.9.8.90`
- nginx serves the Stage4/Stage5 binhost on port `8088`
- repository ID:
  - `stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`
- current HTTP endpoint:
  - `http://10.9.8.90:8088/stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`
- current repo index after focused `coreutils` sync:
  - `257` package records
  - `259` files
- latest focused package sync completed at approximately `2026-04-28 22:27 PDT`

The scoped `sys-apps/coreutils` overlay blocker was resolved and validated in
isolation. A new base-container rerun is active on `10.9.8.89` against the
binpkg repository, with periodic binpkg sync and an overnight restart watchdog.

## Commits Landed Today

- `e08e3ac` Add host overlay support for image builds
- `6529994` Add host package mask support for image builds
- `b416ef2` Add Jenkins and distcc builder farm scaffolding
- `24d29f0` Add first-node CI builder farm bring-up workflow
- `ed5e000` Disable OpenMP in the base container clang runtime
- `72764f4` Add merged-usr Stage4 variant and container compat
- `2b54e98` Scaffold FreeIPA, SSSD, and FreeRADIUS roles
- `82631ea` Add observability and alternate-access scaffolding
- `7119790` Add telemetry and power observability scaffolding
- `4931286` Add binpkg caching and coreutils image-build fix
- `6e2001a` Add Stage4 Stage5 binpkg repository workflow
- `9822f75` Bootstrap image build config roots
- `8ef57df` Add Path B binpkg repository VM workflow
- `674ad9a` Add binpkg watch sync helper
- `1fb68ae` Fix coreutils overlay patch staging

## Live Runtime State

### Binpkg Repository VM

Host:

- hostname: `binpkg-repository`
- address: `10.9.8.90/24`
- gateway: `10.9.8.108`

Services verified started:

- `NetworkManager`
- `sshd`
- `nginx`
- `rsyslog`
- `node_exporter`

Repository:

- root: `/srv/stage5-binpkgs`
- repo path:
  - `/srv/stage5-binpkgs/stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`
- `Packages` file last observed:
  - `2026-04-28 21:13 PDT`
  - `250718` bytes

### Container-Services Builder VM

Host:

- hostname/profile: `container-services`
- address: `10.9.8.89`
- build root:
  - `/var/lib/container-services-ephemeral/images/gentoo-stage4-rootfs`
- local build PKGDIR:
  - `/var/lib/container-services-ephemeral/images/binpkgs`

Final observed failed build state:

- graph size: `471`
- completed package steps: `247`
- failed package step: `248`
- failing atom:
  - `sys-apps/coreutils-9.10-r1::gentoo-stage4-image-fixes`
- local build PKGDIR count:
  - `51` files
- final binpkg repository count after failed-run sync:
  - `256` package records

Current rerun state:

- graph size: `471`
- last observed progress: `97 / 471`
- active build process on `10.9.8.89`
- focused `coreutils` binpkg is present in the repository VM
- current binpkg repository count after focused `coreutils` sync:
  - `257` package records
  - `259` files

Active safety loops:

- local `watch-sync-binpkgs-to-repo.sh` publishes the remote builder PKGDIR
  every `600` seconds
- remote `watch-container-base-build.sh` syncs binpkgs and relaunches the build
  up to two times if it stops before `completed rootfs build`

Log:

- `/var/log/stage5-binpkg-sync-watch-container-services.log`
- builder watchdog log:
  - `/root/container-base-watchdog.log`

## Major Errors And Direction Changes

### 1. Package-build continuity became a first-class requirement

Problem:

- repeated source-first build failures were wasting successful package work
- there was no durable binpkg repository VM to absorb partial successes

Change:

- created `vm-binpkg-repository`
- added the Path B binpkg repository inventory and install vars
- added `qemu-launch-binpkg-repository-vm.sh`
- wired `vm-container-services` to use the new binhost
- added `sync-binpkgs-to-repo.sh`
- added `watch-sync-binpkgs-to-repo.sh` for externally launched or already
  running builders

Impact:

- failed builds now still advance the shared binpkg cache
- tomorrow's rerun can start with `256` indexed package records instead of a
  cold source-only path

### 2. Direct remote-to-remote package sync was invalid

Problem:

- `rsync` cannot copy from `root@builder:/pkgdir` directly to
  `root@repo:/repo`

Change:

- watch-sync now stages remote PKGDIR content locally under:
  - `/var/tmp/stage5-binpkg-sync/<repo-id>`
- then publishes from the local staging directory to the repository host

Impact:

- the recovery/sync path is now reproducible and does not require manual
  rsync choreography

### 3. Binpkg VM boot and service fixes were needed after installation

Problems:

- installed-disk boot needed a Path B `uefi-disk` mode
- the target had no persistent NVRAM boot entry after direct-kernel install
- available OVMF raw files on host were unusable zero-byte files
- nginx did not include `conf.d`
- rsyslog template had invalid double-percent property expansion
- ZFS child datasets hid files created under `/srv` and `/usr/local` during
  target installation

Changes:

- added `uefi-disk` support to the Path B launcher
- embedded ZFSBootMenu commandline into the EFI binary
- converted usable OVMF qcow2 firmware into raw firmware files
- fixed nginx log directory and `conf.d` inclusion
- fixed rsyslog template rendering
- moved the binpkg repo helper to `/usr/sbin/stage5-binpkg-index`
- ensured repository content lands on the mounted `/srv` dataset

Impact:

- the binpkg VM now boots from disk and serves packages without relying on the
  transient installer environment

### 4. Split-usr versus merged-usr remained the main build-policy tension

Problem:

- container rootfs builds hit collisions when packages behaved as split-usr
  inside a merged-usr container rootfs

Direction change:

- accepted a merged-usr Stage4 variant for container rootfs work as the fastest
  path to a functioning container base image
- kept the broader system policy OpenRC-first and systemd-avoidant
- preserved split-usr expectations for host/VM profiles where they remain
  appropriate

Current practical stance:

- use merged-usr for container rootfs profiles where it removes rootfs layout
  collisions
- keep split-usr viable for metal and VM profiles
- patch ebuild behavior narrowly when the overlay is the real issue

### 5. OpenMP and toolchain blockers were handled pragmatically

Problem:

- the base container path encountered OpenMP/toolchain complexity while trying
  to keep the LLVM/Clang profile moving

Change:

- disabled OpenMP in the base container clang runtime path

Impact:

- reduced one blocker class for the current base-container objective
- can be revisited after the first functional GHCR-published image exists

### 6. Coreutils blocker resolved and guarded

Failure:

```text
sys-apps/coreutils-9.10-r1::gentoo-stage4-image-fixes failed (prepare phase)
patch '-p1' '-f' '-g0' '--no-backup-if-mismatch' failed with
/var/tmp/portage-tmpfs/portage/sys-apps/coreutils-9.10-r1/files/coreutils-9.5-skip-readutmp-test.patch
```

Interpretation:

- the local overlay ebuild is applying a patch that no longer cleanly applies
  to the current `coreutils-9.10-r1` source/patch stack
- this is now a scoped overlay maintenance issue, not a general infrastructure
  failure

Resolution:

- staged the patch files referenced by the local overlay ebuild
- changed the overlay ebuild so split-usr relocation is skipped when building
  merged-usr image roots
- validated `ebuild --skip-manifest clean prepare`
- built `sys-apps/coreutils-9.10-r1::gentoo-stage4-image-fixes` in isolation
- synced the resulting `coreutils-9.10-r1-1.gpkg.tar` into the binpkg repository
- restarted the base-container build against the binhost

## Documentation And Wiki Sync

Updated or added documentation:

- `docs/BINPKG-REPOSITORY.md`
- `docs/CHANGELOG.md`
- `docs/ROADMAP-AND-TODO.md`
- `docs/EOD-STATUS-2026-04-28.md`

Wiki source mirrors updated:

- `docs/wiki/Binpkg-Repository.md`
- `docs/wiki/Changelog.md`
- `docs/wiki/Roadmap-and-TODO.md`
- `docs/wiki/EOD-Status-2026-04-28.md`
- `docs/wiki/Home.md`
- `docs/wiki/_Sidebar.md`
- `docs/wiki/README.md`

## Build Timing Assessment

Previous package-count completion before the blocker:

- `247 / 471` completed
- `248 / 471` failed
- approximately `52.4%` complete by package-step count

This is not equivalent to CPU-time completion because package weight is uneven.
However, GCC and glibc completed before the current `coreutils` failure, which
removes two expensive steps from the next binpkg-assisted rerun.

Estimate for the active binpkg-assisted rerun, assuming no equivalent blocker:

- `p90`: `2` to `4` hours
- `p95`: `4` to `6` hours

Estimate if another overlay/package-policy blocker appears in the next tranche:

- `p90`: `4` to `6` hours
- `p95`: `6` to `8` hours

## Tomorrow Dependency Chain

1. Check `/root/container-base-rerun.log` and `/root/container-base-watchdog.log`
   on `10.9.8.89`.
2. If the active rerun completed, validate the image and tarball locally.
3. If the watchdog restarted the build, inspect the preserved timestamped log.
4. If a new package blocker appears, patch narrowly and preserve binpkg
   continuity.
5. Push the validated image to GHCR after local Podman validation succeeds.

## Data Safety

Repo-side changes are committed and pushed through `1fb68ae` before this EOD
documentation update. Build artifacts already produced have been synced into
the repository VM. The remaining uncommitted files before this report were
pre-existing unrelated workspace noise:

- deleted `AGENT_RULES.md`
- untracked `.gitattributes`
- untracked `.gitconfig`
- untracked `AGENTS.md`

Those files were intentionally not included in the infrastructure commits.
