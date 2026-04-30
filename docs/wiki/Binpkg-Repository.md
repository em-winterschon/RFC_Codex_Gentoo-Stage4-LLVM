# Stage4 / Stage5 Binpkg Repository

## Purpose

The binpkg repository VM is the durable package cache for source-first Stage4
and Stage5 builds. Builder runs must publish every successfully built package
there, including runs that later fail on a different atom.

Current default repository ID:

```text
stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic
```

That name is intentionally specific. It lets operators switch between package
repositories without confusing Stage4 baseline, Stage5 role, architecture, or
CPU compatibility profile.

## Repository VM

Profile:

- `vm-binpkg-repository`

Important paths:

- repository root: `/srv/stage5-binpkgs`
- default repo path: `/srv/stage5-binpkgs/stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic`
- HTTP endpoint: `http://10.9.8.90:8088/stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic`

Role behavior:

- creates the repository directories
- renders an nginx static package host
- installs `stage5-binpkg-index`
- enables `nginx`

Path B launch modes:

```bash
# Installer LiveISO mode for provisioning.
bash gentoo-virt-qemu/qemu-launch-binpkg-repository-vm.sh

# Installed-disk mode after provisioning.
QEMU_PATHB_BOOT_MODE=uefi-disk \
EFI_FIRM=/opt/gentoo-netboot/path-b/firmware/OVMF_CODE_4M.fd \
EFI_VARS_TEMPLATE=/opt/gentoo-netboot/path-b/firmware/OVMF_VARS_4M.fd \
bash gentoo-virt-qemu/qemu-launch-binpkg-repository-vm.sh
```

The binpkg repository VM uses a static NetworkManager profile for
`10.9.8.90/24` via `10.9.8.108`.

## Builder Portage Settings

Build hosts should enable:

```text
--buildpkg=y
--usepkg=y
--with-bdeps=y
--complete-graph=y
--binpkg-respect-use=y
```

The Portage role exposes these through:

- `portage_buildpkg_enabled`
- `portage_usepkg_enabled`
- `portage_getbinpkg_enabled`
- `portage_pkgdir`
- `portage_binhost`
- `portage_binrepos`
- `portage_emerge_default_opts_extra`

The `vm-container-services` example is configured to build with local binpkgs
enabled and pull from the Stage4/Stage5 repository URL above.

## On-Host High-Performance Build Shape

The current host has 64 hardware threads and `/dev/shm` sized near 1 TiB. Use
that for fast ephemeral rootfs and binpkg work while keeping a few CPU threads
available for QEMU, SSH, and operator tasks.

Recommended starting point:

```bash
mkdir -p /dev/shm/stage5-build/images

bash scripts/build-gentoo-rootfs-container.sh \
  --root /dev/shm/stage5-build/images/gentoo-stage3-llvm-clang-openrc-rootfs \
  --pkgdir /dev/shm/stage5-build/images/gentoo-stage3-llvm-clang-openrc-binpkgs \
  --binpkg-repo-id stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic \
  --binpkg-sync-remote root@10.9.8.90 \
  --binpkg-sync-root /srv/stage5-binpkgs \
  --stage3-target amd64-llvm-openrc \
  --stage3-cache-dir /dev/shm/stage5-build/stage3-cache \
  --reset-rootfs \
  --package-list container-image-definitions/gentoo-stage3-llvm-clang-openrc.packages \
  --use-file container-image-definitions/gentoo-stage3-llvm-clang-openrc.use \
  --package-use-file container-image-definitions/gentoo-stage3-llvm-clang-openrc.package.use \
  --config-root /dev/shm/stage5-build/images/gentoo-stage3-llvm-clang-openrc-rootfs \
  --sysroot /dev/shm/stage5-build/images/gentoo-stage3-llvm-clang-openrc-rootfs \
  --engine none \
  --tarball /dev/shm/stage5-build/images/gentoo-stage3-llvm-clang-openrc.tar.zst
```

Set the calling environment for high parallelism:

```bash
export MAKEOPTS="-j60"
export EMERGE_DEFAULT_OPTS="--jobs=24 --load-average=60 --buildpkg=y --usepkg=y --with-bdeps=y --complete-graph=y --autounmask=y --autounmask-backtrack=y --autounmask-continue=y --autounmask-unrestricted-atoms=y --autounmask-use=y --autounmask-write=y --binpkg-respect-use=y"
export FEATURES="-distcc -ccache buildpkg parallel-install merge-sync"
export PORTAGE_BINPKG_FORMAT="tar"
export BINPKG_COMPRESS="zstd"
export BINPKG_COMPRESS_FLAGS="-2"
```

The helper syncs `PKGDIR` to the repository host on exit when
`--binpkg-sync-remote` is set, including failed exits. That preserves useful
packages from partial runs.

For overnight or unattended reruns, pair the sync helper with the build
watchdog. The watchdog does not diagnose new package blockers by itself; it
preserves continuity by syncing binpkgs and relaunching a bounded number of
times if the detached build exits before `completed rootfs build`.

```bash
setsid -f bash -c 'exec scripts/watch-container-base-build.sh \
  --launch-script /root/run-container-base-build-coreutils-fix.sh \
  --build-log /root/container-base-rerun.log \
  --watch-pattern "build-gentoo-rootfs-container.sh --root /var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc-rootfs" \
  --pkgdir /var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc-binpkgs \
  --repo-id "$1" \
  --sync-remote root@10.9.8.90 \
  --sync-root /srv/stage5-binpkgs \
  --interval 600 \
  --max-restarts 2 \
  --watch-log /root/container-base-watchdog.log \
  >>/root/container-base-watchdog.runner.log 2>&1' \
  stage5-container-watch "${repo_id}"
```

For already-running or externally launched builders, use the watch-sync helper.
It stages remote PKGDIRs locally first, then publishes them to the repository:

```bash
repo_id=stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic

setsid -f bash -c 'exec bash scripts/watch-sync-binpkgs-to-repo.sh \
  --pkgdir root@10.9.8.89:/mnt/gentoo/mnt/gentoo/var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc-binpkgs \
  --repo-id "$1" \
  --remote root@10.9.8.90 \
  --remote-root /srv/stage5-binpkgs \
  --staging-dir /var/tmp/stage5-binpkg-sync/container-services \
  --watch-remote root@10.9.8.89 \
  --watch-pattern "build-gentoo-rootfs-container.sh --root /var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc-rootfs" \
  --interval 600 \
  < /dev/null >>/var/log/stage5-binpkg-sync-watch-container-services.log 2>&1' \
  stage5-binpkg-sync-watch "${repo_id}"
```

Use `--watch-pattern` rather than `--watch-pid` when a build restart watchdog
is active; a PID watcher exits after the first failed process, while the
pattern watcher survives bounded relaunches.

## Environmental Continuity

Do not rely on the Path B live environment as the long-term builder state. It is
acceptable for installer orchestration, but package build state must live in:

- `PKGDIR`, synced to the binpkg repository VM
- explicit rootfs workspace paths under `/dev/shm` or the container-services
  runtime storage
- committed overlay fixes under `container-image-definitions/overlays`

The current container image overlay carries scoped fixes for:

- `app-alternatives/awk`
- `sys-apps/coreutils`
