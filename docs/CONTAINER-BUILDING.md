# Container Building

## Current base-image path

The first reusable base image path for this repo is:

1. Extract the official Gentoo `amd64-llvm-openrc` stage3 tarball.
2. Preserve the upstream stage3 profile instead of synthesizing a hardened profile.
3. Layer the Stage5 service-container package list with `emerge --root`.
4. Archive it with `zstd -2 --rsyncable --auto-threads=physical --exclude-compressed`.
5. Import or commit it into a local Podman-compatible image.
6. Publish the validated image through `scripts/publish-container-ghcr.sh`.

The active base image is intentionally not hardened. Hardened Stage4 container
builds remain a follow-on track after the simple stage3-derived image is
functional and publishable.

The rootfs builder now caches local binpkgs by default under a sibling
`binpkgs/` directory next to the rootfs path and reuses them on reruns.

This is intended to run first on the validated `vm-container-services` host profile.

CPU tuning note:

- for generic VM and container-builder targets, prefer `x86_64_v2_generic`
- use `x86_64_v3_generic` only when the guest fleet contract supports it
- avoid host-specific microarchitecture profiles for portable guest/container
  images because Rust/Python build helpers can fault later with `invalid opcode`
- the active stage3-backed workflow keeps the upstream stage3 filesystem and
  profile layout unchanged

## Default image definition

- metadata:
  - `container-image-definitions/gentoo-stage3-llvm-clang-openrc.metadata.yml`
- package list:
  - `container-image-definitions/gentoo-stage3-llvm-clang-openrc.packages`
- USE overrides:
  - `container-image-definitions/gentoo-stage3-llvm-clang-openrc.use`
- package.use overrides:
  - `container-image-definitions/gentoo-stage3-llvm-clang-openrc.package.use`

## Rootfs build helper

Use:

```bash
bash scripts/build-gentoo-rootfs-container.sh \
  --root /var/lib/container-services/images/gentoo-stage3-llvm-clang-openrc-rootfs \
  --pkgdir /var/lib/container-services/images/gentoo-stage3-llvm-clang-openrc-binpkgs \
  --binpkg-repo-id stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic \
  --binpkg-sync-remote root@10.66.40.20 \
  --binpkg-sync-root /srv/stage5-binpkgs \
  --stage3-target amd64-llvm-openrc \
  --stage3-cache-dir /var/lib/container-services/stage3-cache \
  --reset-rootfs \
  --package-list container-image-definitions/gentoo-stage3-llvm-clang-openrc.packages \
  --use-file container-image-definitions/gentoo-stage3-llvm-clang-openrc.use \
  --package-use-file container-image-definitions/gentoo-stage3-llvm-clang-openrc.package.use \
  --config-root /var/lib/container-services/images/gentoo-stage3-llvm-clang-openrc-rootfs \
  --sysroot /var/lib/container-services/images/gentoo-stage3-llvm-clang-openrc-rootfs \
  --image-ref localhost/gentoo-stage3-llvm-clang-openrc:latest \
  --tarball /var/lib/container-services/images/gentoo-stage3-llvm-clang-openrc.tar.zst \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo Stage3 LLVM/Clang OpenRC base container"
```

Use `--stage3-target amd64-llvm-openrc` to resolve the current Gentoo stage3
from `latest-stage3-amd64-llvm-openrc.txt`. The builder downloads the tarball
and `.sha256`, verifies the checksum, extracts the rootfs, and then layers the
package list without `--emptytree`.

For fast lab reruns, set `CONTAINER_STAGE3_TARBALL=/path/to/stage3.tar.xz`
when launching `scripts/run-container-base-build-pathb.sh`. That bypasses the
WAN metadata/download step and extracts the known local stage3 tarball instead.

Use `--pkgdir` to pin the local binpkg cache location explicitly. If omitted,
the helper defaults to `$(dirname ROOT)/binpkgs`, enables `buildpkg`, and
reuses matching local binpkgs on reruns with `--usepkg=y`.

Use `--binpkg-sync-remote` with `--binpkg-repo-id` to push every successfully
built package to the Stage4/Stage5 binpkg repository host on script exit,
including failed exits.

Use `--overlay-dir` only when the image build needs a narrow ebuild fix in the
build host dependency path. The deferred hardened image overlay patches:

- `app-alternatives/awk`
- `sys-apps/coreutils`

Those fixes normalize merged-usr host-side install trees so reruns do not stop
on `/bin/*` versus `/usr/bin/*` internal collisions.

Use `--host-package-use-file` and `--host-package-mask-file` only for the
deferred source-first hardened image path. They are not part of the active
standard stage3 base-container path.

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
  --local-image localhost/gentoo-stage3-llvm-clang-openrc:latest \
  --image-name gentoo-stage3-llvm-clang-openrc \
  --tag git-$(git rev-parse --short HEAD) \
  --namespace em-winterschon \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo Stage3 LLVM/Clang OpenRC base container"
```

## Service layers

Service-image build intent is tracked in:

- `container-image-definitions/service-layers.yml`

The manifest pins service-layer work to the published stage3 base image and
splits services by build mode:

- `portage-layer`
  - build a small service image from the GHCR base image plus service packages
- `upstream-image`
  - keep using an upstream image until a Gentoo ebuild or overlay exists

Current `portage-layer` candidates:

- `www-servers/nginx`
- `net-proxy/haproxy`
- `app-admin/rsyslog`

Current upstream-only service:

- `ntfy`, because no Portage atom was present in the current builder tree

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
- the active base-image build now uses:
  - guest size: `32` vCPU, `32 GiB` RAM
  - Portage parallelism: `MAKEOPTS="-j64"`, `EMERGE_DEFAULT_OPTS="--jobs=16"`
  - source: official `stage3-amd64-llvm-openrc` tarball
  - package layering graph: Stage5 service-container additions only
- prior hardened/source-first blocker class:
  - repeated late failures in a large `--emptytree` graph
  - split-usr versus merged-usr and libc++ sysroot continuity issues
- completed rerun after refactor:
  - binhost: `10.9.8.90:8088`
  - repo ID: `stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic`
  - image: `localhost/gentoo-stage3-llvm-clang-openrc:latest`
  - tarball: `/var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc.tar.zst`
  - tarball size: `633M`
  - smoke test passed for `/etc/gentoo-release`, `curl`, `ip`, and `ps`
