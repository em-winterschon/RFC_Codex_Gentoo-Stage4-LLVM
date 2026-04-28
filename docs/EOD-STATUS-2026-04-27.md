# End of Day Status: 2026-04-27

## Summary

Today’s work converted the `vm-container-services` profile from a profile
definition into a live validated runtime on the Path B lab, and then carried
the first reusable Gentoo base-container build into a real source-first run.

Validated live:

- Path B `container-services` provisioning succeeds through:
  - provisioner SSH
  - `storage-foundation`
  - `chroot-bootstrap`
  - `target-integration`
- the installed `container-services` VM at `10.9.8.89` has working:
  - `podman`
  - `buildah`
  - `skopeo`
  - `nginx`
  - `ntfy`
  - `haproxy`
- the runtime root for container data is now:
  - `/var/lib/container-services-ephemeral`
- the first source-first Gentoo base-container image build is wired and
  running from the installed target workflow

## Problems Solved Today

1. Stabilized the container-services Stage 5 overlay.
   - fixed package atoms and USE policy for:
     - `buildah`
     - `skopeo`
     - `netavark`
     - `aardvark-dns`
     - `haproxy`
   - kept the repo-wide `without-systemd` posture intact
   - added only narrow scoped exceptions where strictly required
2. Fixed the container runtime ownership boundary.
   - netavark and nftables can coexist on the container-services host
   - app container service wrappers now render and start correctly
3. Normalized image-building inputs.
   - flat package list for the base image already existed
   - added image-local USE overrides
   - added image-local `package.use` overrides
   - added rootfs builder `--sysroot` and config-root support
4. Corrected guest CPU tuning for portable VM and container builds.
   - moved generic guests to `x86_64_v2_generic`
   - avoided host-specific microarchitecture leakage that had broken Rust and
     Python helper binaries with `invalid opcode`
5. Validated the accelerated build lane.
   - rebuilt the Path B container-services VM with:
     - `32` vCPU
     - `32 GiB` RAM
     - tmpfs-backed extra QEMU disks
   - raised target Portage parallelism to:
     - `MAKEOPTS="-j64"`
     - `EMERGE_DEFAULT_OPTS="--jobs=16"`

## Commits Landed Today

- `9244802` Add container-services VM profile and Podman roles
- `f908439` Add tmpfs-backed memory drive workflows
- `bc5f1a9` Add VM serial watcher helper
- `fe09223` Stabilize Path B launchers and modular cloud-init profiles
- `529c7c5` Add Gentoo container image builder and scoped unmask support
- `dd3f9b8` Normalize profile package layers and stage language
- `10fd20c` Add generic VM CPU tuning profiles
- `28541da` Document container-services validation progress
- `7692e67` Fix container profile overrides and identity tasks
- `ec3aa76` Validate container-services runtime stack
- `e61b4fa` Fix nftables ownership for container services
- `c19ccc9` Fix Gentoo base container package atoms
- `45946fa` Sanitize rootfs builder emerge features
- `5b9b416` Add image-level USE overrides for base containers
- `c9ccf3c` Add sysroot support to rootfs builder
- `38c8aba` Add image-scoped package.use support

## Open PRs

- `#13` ntfy reply listener
- `#14` private ntfy server deployment
- `#15` ZFS hostid / ZFSBootMenu commandline follow-up
- `#16` default LLVM/Clang Portage profile and linting
- `#17` Path B iPXE netboot workflow
- `#18` Gentoo system profiles and identity role
- `#19` container-services VM profile, Podman roles, and base-container build
  workflow

## Closed / Merged PRs Today

- none

## Current Build State

There are no currently running base-image builds at this commit point.

Latest attempted build:

- target host: `root@10.9.8.89`
- build root: `/var/lib/container-services-ephemeral/images/gentoo-stage4-rootfs`
- target image ref: `localhost/gentoo-stage4-llvm-clang-hardened:latest`
- package graph size: `482`
- completed successfully before failure: `115`
- failure point: package `116`
- failing atom: `app-alternatives/awk-4`

Observed failure mode:

- merged-usr rootfs build collided on:
  - `/bin/awk`
  - `/usr/bin/awk`
- package still merged with `split-usr` behavior

Current fix now committed:

- image-local `package.use` file:
  - `container-image-definitions/gentoo-stage4-llvm-clang-hardened.package.use`
- scoped rule:
  - `app-alternatives/awk -split-usr`

Expected next action:

1. rerun the base-container build with the image-local `package.use` override
2. verify `app-alternatives/awk` no longer collides in the merged-usr rootfs
3. let the source-first image build complete
4. validate the local Podman image and `.tar.zst`
5. publish to GHCR using the staged token

## Build VM Reference

Current accelerated build VM:

- VM name: `container-services`
- hypervisor: QEMU/KVM on the Gentoo control host
- QEMU PID at latest observation: `64318`
- guest hostname: `gentoo-pathb`
- guest address: `10.9.8.89`
- vCPU: `32`
- RAM: `32 GiB`
- swap: `0`
- boot path:
  - Path B live provisioner environment
  - installed target imported and mounted under `/mnt/gentoo/mnt/gentoo`
- target Portage parallelism:
  - `MAKEOPTS="-j64"`
  - `EMERGE_DEFAULT_OPTS="--jobs=16"`

Attached disks:

- persistent target disk:
  - `/opt/gentoo-netboot/path-b/vms/container-services-profile/container-services-root.qcow2`
- tmpfs-backed ephemeral QEMU disks:
  - `/dev/shm/qemu-memory-drives/pathb-container-services/portage-cache.qcow2`
  - `/dev/shm/qemu-memory-drives/pathb-container-services/container-ephemeral.qcow2`

## Build Timing Assessment

Latest accelerated run:

- observed completed package markers: `115 / 482`
- observed failure at `116 / 482`
- observed completion by count: `23.86%`
- observed failure marker by count: `24.07%`

Interpretation:

- package-count completion is front-loaded by light virtuals and early utility
  packages
- actual CPU-time completion is lower than the raw package-count percentage
- the accelerated lane is still the right choice over the earlier `16` vCPU
  path

Current forecast for the next rerun, assuming the new `awk` fix removes the
collision and no new equivalent packaging blockers appear:

- `p90`: `4` to `5` hours
- `p95`: `5` to `7` hours

Why the estimate is still broad:

- the image build is still effectively an `--emptytree` system-like closure
- the graph is `482` packages, not a minimal runtime-only container set
- heavy toolchain and Python/LLVM components are still later in the closure

## Outstanding Tasks

1. Rerun the Gentoo base-container image build with the new image-local
   `package.use` override.
2. Verify that `app-alternatives/awk` no longer collides under merged-usr.
3. Reduce the final base-container closure over time so the image path trends
   from “mini system build” toward “runtime container build”.
4. Validate the completed local image:
   - `localhost/gentoo-stage4-llvm-clang-hardened:latest`
   - `/var/lib/container-services-ephemeral/images/gentoo-stage4-llvm-clang-hardened.tar.zst`
5. Publish the first validated image to GHCR using:
   - `~/.ssh/codex.d/tokens/GHCR_TOKEN`
6. Decide whether to add a first-class repo helper that stages and launches the
   mounted-target base-image build automatically instead of using the live
   target orchestration script only.

## Tomorrow / Next Tranche

1. restart the base-container build with the scoped `awk` override
2. carry the build to completion
3. import or commit the result into a local Podman image
4. verify the image can run basic commands successfully
5. publish the validated image to GHCR
6. then begin reducing the image closure and introducing repo-native binpkg
   strategy for repeat builds

## Data Safety

Repo-side code, docs, wiki-source mirrors, and current build findings are
committed and pushed on `codex/add-container-services-profile`. No important
state is left only in local uncommitted repository changes.
