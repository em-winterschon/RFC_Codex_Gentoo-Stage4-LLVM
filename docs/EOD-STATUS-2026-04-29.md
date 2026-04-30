# EOD Status 2026-04-29

## Executive State

The hardened source-first base-container build was stopped as the active path.
It repeatedly produced late dependency-tree failures in a large `--emptytree`
graph, primarily around toolchain runtime continuity and filesystem layout
assumptions. The active base-container path now uses Gentoo's official
`amd64-llvm-openrc` stage3 as the rootfs base and layers only the Stage5
service-container package list on top.

## Major Direction Change

Active image:

- `localhost/gentoo-stage3-llvm-clang-openrc:latest`

Active binpkg repo ID:

- `stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic`

Active build source:

- Gentoo latest metadata:
  - `https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-llvm-openrc/latest-stage3-amd64-llvm-openrc.txt`
- Latest observed metadata at refactor time:
  - `stage3-amd64-llvm-openrc-20260426T153103Z.tar.xz`

Operational decision:

- use the standard llvm-clang OpenRC stage3 first
- keep the hardened Stage4 image as a later hardening track
- avoid synthetic hardened profile generation for this first container base
- avoid `--emptytree` for the stage3-backed package layering pass

## Code Changes

Added builder support for:

- `--stage3-target`
- `--stage3-tarball`
- `--stage3-cache-dir`
- `--stage3-mirror-root`
- `--stage3-verify-checksum`
- `--main-emptytree`
- `--reset-rootfs`

The builder now:

- resolves latest Gentoo stage3 metadata
- downloads the stage3 tarball and `.sha256`
- verifies SHA256 before extraction
- resets the target rootfs when requested
- extracts the stage3 rootfs with xattrs and numeric ownership
- preserves the stage3 profile unless explicit profile parents are provided
- layers the package list without `--emptytree` for stage3-backed builds

Added active container definition files:

- `container-image-definitions/gentoo-stage3-llvm-clang-openrc.metadata.yml`
- `container-image-definitions/gentoo-stage3-llvm-clang-openrc.packages`
- `container-image-definitions/gentoo-stage3-llvm-clang-openrc.use`
- `container-image-definitions/gentoo-stage3-llvm-clang-openrc.package.use`

Updated launchers:

- `scripts/run-container-base-build-pathb.sh`
- `scripts/start-container-base-watchdog-pathb.sh`

## Validation

Local validation passed:

```bash
bash tests/shell/test_build_gentoo_rootfs_container.sh
bash -n scripts/build-gentoo-rootfs-container.sh scripts/run-container-base-build-pathb.sh scripts/start-container-base-watchdog-pathb.sh
```

Dry-run validation confirmed:

- stage3 target: `amd64-llvm-openrc`
- stage3 current dir: `current-stage3-amd64-llvm-openrc`
- main package pass: `main-emptytree=false`
- rootfs reset: `reset-rootfs=true`
- active package count: `6`

## Outstanding Actions

1. Stop any remaining hardened/source-first builder process on `10.9.8.89`.
2. Sync this repo to the builder chroot.
3. Install the updated Path B launcher inside the builder chroot.
4. Start the stage3-backed watchdog run.
5. Validate local image and tarball when the build finishes.
6. Push the validated image to GHCR.
7. Resume hardened Stage4 container work only after the stage3-backed base image is published.

## Dependency Tracking

| ID | Item | Depends On | State |
| --- | --- | --- | --- |
| `BASE-STAGE3-001` | Stage3-backed builder support | local tests | complete |
| `BASE-STAGE3-002` | Path B launcher refactor | `BASE-STAGE3-001` | complete |
| `BASE-STAGE3-003` | Builder VM restart | `BASE-STAGE3-002` | pending |
| `BASE-STAGE3-004` | Local image validation | `BASE-STAGE3-003` | pending |
| `BASE-STAGE3-005` | GHCR publish | `BASE-STAGE3-004` | pending |
| `HARDENED-001` | Hardened Stage4 image revival | `BASE-STAGE3-005` | deferred |

## Notes For Resumption

The next operator-visible result should be a much smaller build graph. If it
still attempts a hundreds-package LLVM rebuild, that is a signal that the
stage3 profile was accidentally overridden or the package list grew beyond the
intended service-container additions.
