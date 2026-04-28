# Container Building

## Current base-image path

The first reusable base image path for this repo is:

1. Build a Gentoo rootfs with `emerge --root`.
2. Archive it with `zstd -2 --rsyncable --auto-threads=physical --exclude-compressed`.
3. Import or commit it into a local Podman-compatible image.
4. Publish the validated image through `scripts/publish-container-ghcr.sh`.

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

## Rootfs build helper

Use:

```bash
bash scripts/build-gentoo-rootfs-container.sh \
  --root /var/lib/container-services/images/gentoo-stage4-rootfs \
  --package-list container-image-definitions/gentoo-stage4-llvm-clang-hardened.packages \
  --use-file container-image-definitions/gentoo-stage4-llvm-clang-hardened.use \
  --image-ref localhost/gentoo-stage4-llvm-clang-hardened:latest \
  --tarball /var/lib/container-services/images/gentoo-stage4-llvm-clang-hardened.tar.zst \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo Stage4 LLVM/Clang hardened base container"
```

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

## Notes

- Keep `without-systemd` as the default repo posture.
- Use narrow package-local compatibility exceptions only when required.
- Build on the validated container-services VM so Portage policy, LLVM defaults,
  and package exceptions match the intended runtime host.
