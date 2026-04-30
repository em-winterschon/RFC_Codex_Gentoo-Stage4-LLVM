# Changelog

This changelog tracks operator-visible changes to the Stage4/Stage5
infrastructure work. It is intentionally higher level than `git log`.

## 2026-04-29

### Added

- Added an explicit compiler/runtime bootstrap package phase for the Gentoo
  rootfs container builder.

### Changed

- Split container rootfs builds into a small runtime bootstrap phase followed
  by the main image graph, so clang sysroot ABI failures are detected before
  the long dependency tree reaches CMake packages.

### Fixed

- Fixed the repeated `dev-libs/json-c` CMake ABI failure path by bootstrapping
  `llvm-runtimes/libunwind`, `libcxxabi`, `libcxx`, and `compiler-rt` with a
  temporary `libgcc`/`libstdc++` fallback, then verifying normal
  clang/libunwind C and C++ linking against the target rootfs.
- Fixed the generated local container profile repository lookup by exposing the
  config-root profile overlay through a host-side `/var/db/repos` symlink while
  the builder is active.

## 2026-04-28

### Added

- Added a Path B `vm-binpkg-repository` workflow for a durable custom Portage
  binary package repository.
- Added `qemu-launch-binpkg-repository-vm.sh` for installer and installed-disk
  launch paths.
- Added a Stage4/Stage5-specific binpkg repo ID:
  - `stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`
- Added `sync-binpkgs-to-repo.sh` for explicit PKGDIR publication.
- Added `watch-sync-binpkgs-to-repo.sh` for active or externally launched
  builders, including SSH-remote PKGDIR staging.
- Added `watch-container-base-build.sh` so detached container-image builds can
  sync binpkgs and relaunch a bounded number of times after failure.
- Added Jenkins controller and `distcc` builder-farm scaffolding.
- Added first-node builder-farm bring-up workflow.
- Added FreeIPA, SSSD, and FreeRADIUS scaffolding for RBAC/AAA.
- Added observability, telemetry, power, SNMP, IPMI, and Redfish scaffolding.

### Changed

- Moved the container base-image path toward a merged-usr Stage4 variant while
  keeping split-usr viable for host and VM profiles.
- Kept the repo-wide OpenRC and without-systemd posture, with scoped exceptions
  only where required by selected packages.
- Updated container-services Portage settings to build binpkgs, use binpkgs,
  pull from the new repository, and preserve autounmask continuity.
- Updated boot handling so ZFSBootMenu can carry an embedded commandline when
  NVRAM boot entries are unavailable.
- Updated the binpkg repository role so nginx includes `conf.d`, has its log
  directory, and serves a dataset-backed repository path.
- Updated rsyslog templating to use valid property expansion.
- Hardened the rootfs builder so inherited host `distcc` and `ccache`
  `FEATURES` are explicitly disabled for isolated container-image builds.

### Fixed

- Fixed binpkg repository VM installed-disk boot by adding Path B `uefi-disk`
  launch support and using valid OVMF firmware images.
- Fixed hidden repository/helper content caused by ZFS child datasets mounted
  over files created during target installation.
- Fixed invalid remote-to-remote package sync by staging remote PKGDIR content
  locally before publishing.
- Fixed `sync-binpkgs-to-repo.sh` executable mode so helper chaining works.
- Fixed watch-mode process tracking by adding `--watch-pid`.
- Fixed the `coreutils-9.10-r1` image overlay by staging the referenced patch
  files and preventing the split-usr install path from re-splitting merged-usr
  image roots.

### Active Build State

- The `coreutils` blocker was validated in isolation and its binpkg was
  published to the Stage4/Stage5 binpkg repository.
- The base-container build was restarted against the binhost and had advanced
  past early binary merges at last observation.
- A local binpkg watch-sync loop and a remote build restart watchdog are active
  for the overnight run.

## 2026-04-27

### Added

- Added the `vm-container-services` profile and Podman service roles.
- Added tmpfs-backed QEMU memory-drive workflows for faster ephemeral build and
  provision cycles.
- Added VM serial watcher helpers for Path B build visibility.
- Added modular cloud-init profile definitions.
- Added the Gentoo rootfs/container image builder flow.
- Added image-level USE, `package.use`, and `sysroot` support for the rootfs
  builder.

### Changed

- Normalized profile/package language around Stage3, Stage4, and Stage5 layers.
- Moved generic VM CPU tuning toward portable `x86_64_v2_generic`.
- Sanitized rootfs builder `FEATURES` so host distcc/ccache state does not leak
  into isolated container builds.

### Fixed

- Fixed container-services runtime stack validation for Podman, Buildah,
  Skopeo, netavark, nftables, nginx, ntfy, and HAProxy.
- Fixed initial `app-alternatives/awk` merged-usr collision through scoped
  container image overrides.
