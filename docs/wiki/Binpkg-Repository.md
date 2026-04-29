# Stage4 / Stage5 Binpkg Repository

## Purpose

The binpkg repository VM is the durable package cache for source-first Stage4
and Stage5 builds. Builder runs must publish every successfully built package
there, including runs that later fail on a different atom.

Current default repository ID:

```text
stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic
```

That name is intentionally specific. It lets operators switch between package
repositories without confusing Stage4 baseline, Stage5 role, architecture, or
CPU compatibility profile.

## Repository VM

Profile:

- `vm-binpkg-repository`

Important paths:

- repository root: `/srv/stage5-binpkgs`
- default repo path: `/srv/stage5-binpkgs/stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`
- HTTP endpoint: `http://10.9.8.90:8088/stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`

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
  --root /dev/shm/stage5-build/images/gentoo-stage4-rootfs \
  --pkgdir /dev/shm/stage5-build/images/binpkgs \
  --binpkg-repo-id stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic \
  --binpkg-sync-remote root@10.9.8.90 \
  --binpkg-sync-root /srv/stage5-binpkgs \
  --package-list container-image-definitions/gentoo-stage4-llvm-clang-hardened.packages \
  --use-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.use \
  --package-use-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.package.use \
  --host-package-use-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.host.package.use \
  --host-package-mask-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.host.package.mask \
  --rootfs-links-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.rootfs-links \
  --overlay-dir container-image-definitions/overlays/gentoo-stage4-image-fixes \
  --config-root /dev/shm/stage5-build/images/gentoo-stage4-rootfs \
  --sysroot /dev/shm/stage5-build/images/gentoo-stage4-rootfs \
  --engine none \
  --tarball /dev/shm/stage5-build/images/gentoo-stage4-llvm-clang-hardened.tar.zst
```

Set the calling environment for high parallelism:

```bash
export MAKEOPTS="-j60"
export EMERGE_DEFAULT_OPTS="--jobs=24 --load-average=60 --buildpkg=y --usepkg=y --with-bdeps=y --complete-graph=y --autounmask=y --autounmask-backtrack=y --autounmask-continue=y --autounmask-unrestricted-atoms=y --autounmask-use=y --autounmask-write=y --binpkg-respect-use=y"
export FEATURES="buildpkg parallel-install merge-sync"
export PORTAGE_BINPKG_FORMAT="tar"
export BINPKG_COMPRESS="zstd"
export BINPKG_COMPRESS_FLAGS="-2"
```

The helper syncs `PKGDIR` to the repository host on exit when
`--binpkg-sync-remote` is set, including failed exits. That preserves useful
packages from partial runs.

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
