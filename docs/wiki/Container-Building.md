# Container Building

## Current base-image path

The first reusable base image path for this repo is:

1. Build a Gentoo rootfs with `emerge --root`.
2. Archive it with `zstd -2 --rsyncable --auto-threads=physical --exclude-compressed`.
3. Import or commit it into a local Podman-compatible image.
4. Publish the validated image through `scripts/publish-container-ghcr.sh`.

The rootfs builder now caches local binpkgs by default under a sibling
`binpkgs/` directory next to the rootfs path and reuses them on reruns.

This is intended to run first on the validated `vm-container-services` host profile.

CPU tuning note:

- for generic VM and container-builder targets, prefer `x86_64_v2_generic`
- use `x86_64_v3_generic` only when the guest fleet contract supports it
- avoid host-specific microarchitecture profiles for portable guest/container
  images because Rust/Python build helpers can fault later with `invalid opcode`
- container rootfs builds in this workflow are merged-usr, so the image-level
  USE override file disables `split-usr`

## Default image definition

- metadata:
  - `container-image-definitions/gentoo-stage4-llvm-clang-hardened.metadata.yml`
- package list:
  - `container-image-definitions/gentoo-stage4-llvm-clang-hardened.packages`
- USE overrides:
  - `container-image-definitions/gentoo-stage4-llvm-clang-hardened.use`
- package.use overrides:
  - `container-image-definitions/gentoo-stage4-llvm-clang-hardened.package.use`
- host package.use overrides:
  - `container-image-definitions/gentoo-stage4-llvm-clang-hardened.host.package.use`
- host package.mask overrides:
  - `container-image-definitions/gentoo-stage4-llvm-clang-hardened.host.package.mask`
- rootfs compatibility links:
  - `container-image-definitions/gentoo-stage4-llvm-clang-hardened.rootfs-links`
- local overlay fixes:
  - `container-image-definitions/overlays/gentoo-stage4-image-fixes`

## Rootfs build helper

Use:

```bash
bash scripts/build-gentoo-rootfs-container.sh \
  --root /var/lib/container-services/images/gentoo-stage4-rootfs \
  --pkgdir /var/lib/container-services/images/binpkgs \
  --package-list container-image-definitions/gentoo-stage4-llvm-clang-hardened.packages \
  --use-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.use \
  --package-use-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.package.use \
  --host-package-use-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.host.package.use \
  --host-package-mask-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.host.package.mask \
  --rootfs-links-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.rootfs-links \
  --overlay-dir container-image-definitions/overlays/gentoo-stage4-image-fixes \
  --config-root /var/lib/container-services/images/gentoo-stage4-rootfs \
  --sysroot /var/lib/container-services/images/gentoo-stage4-rootfs \
  --image-ref localhost/gentoo-stage4-llvm-clang-hardened:latest \
  --tarball /var/lib/container-services/images/gentoo-stage4-llvm-clang-hardened.tar.zst \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo Stage4 LLVM/Clang hardened base container"
```

Use `--package-use-file` for scoped image quirks such as `app-alternatives/awk`
under merged-usr. Keep those exceptions image-local rather than weakening the
host or Stage 4 profile globally.

Use `--host-package-use-file` when host-side build dependencies still default to
split-usr behavior even though the container root is merged-usr. The current
definition uses this to force merged-usr-safe host dependency behavior for
`sys-apps/coreutils`.

Use `--pkgdir` to pin the local binpkg cache location explicitly. If omitted,
the helper defaults to `$(dirname ROOT)/binpkgs`, enables `buildpkg`, and
reuses matching local binpkgs on reruns with `--usepkg=y`.

Use `--overlay-dir` when the image build needs a narrow ebuild fix in the build
host dependency path. The current image overlay patches:

- `app-alternatives/awk`
- `sys-apps/coreutils`

Those fixes normalize merged-usr host-side install trees so reruns do not stop
on `/bin/*` versus `/usr/bin/*` internal collisions.

Use `--host-package-mask-file` when the build host must be forced away from a
broken generic atom selection. The current image definition masks
`=app-alternatives/awk-4::gentoo` on the host so the patched overlay package
wins for the source-first image build.

Use `--rootfs-links-file` when the target container root should materialize
merged-usr compatibility links such as `/bin -> usr/bin` and `/sbin -> usr/sbin`
before `emerge --root` begins.

Engine behavior:

- `--engine auto`
  - prefers `buildah`
  - falls back to `podman import`
- `--engine buildah`
  - uses `buildah from scratch` and `buildah commit`
- `--engine podman-import`
  - imports a tar stream into Podman
- `--engine none`
  - builds only the rootfs and optional tarball

## Publish flow

After validating the local image:

```bash
bash scripts/publish-container-ghcr.sh \
  --local-image localhost/gentoo-stage4-llvm-clang-hardened:latest \
  --image-name gentoo-stage4-llvm-clang-hardened \
  --tag git-$(git rev-parse --short HEAD) \
  --namespace em-winterschon \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo Stage4 LLVM/Clang hardened base container"
```

## Build telemetry

Export package burn-down and builder workload data from the live logs with:

```bash
python3 scripts/export_build_metrics.py \
  --emerge-log /mnt/gentoo/mnt/gentoo/var/log/emerge.log \
  --builder-log /mnt/gentoo/mnt/gentoo/root/container-base-rerun.log \
  --output-dir /tmp/build-metrics
```

Artifacts produced:

- `summary.json`
- `emerge-events.csv`
- `builder-samples.csv`
- `burndown.svg`
- `builder-load.svg`
- `report.html`

## Notes

- Keep `without-systemd` as the default repo posture.
- Use narrow package-local compatibility exceptions only when required.
- Build on the validated container-services VM so Portage policy, LLVM defaults,
  and package exceptions match the intended runtime host.

## Current Validation State

- container-services runtime validation is complete on the Path B lab VM
- the first source-first base-image build currently uses:
  - guest size: `32` vCPU, `32 GiB` RAM
  - Portage parallelism: `MAKEOPTS="-j64"`, `EMERGE_DEFAULT_OPTS="--jobs=16"`
  - package graph: `482`
- latest stop point:
  - completed package markers: `115`
  - failing package marker: `116`
  - failing atom: `app-alternatives/awk-4`
- next rerun should use the image-local package.use rule:
  - `app-alternatives/awk -split-usr`
- current timing forecast for the next rerun:
  - `p90`: `4` to `5` hours
  - `p95`: `5` to `7` hours
