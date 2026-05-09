# Stage4 LOX Workstation GPU Binpkg Design

## Goal

Normalize the Gentoo workstation profile language around `Stage4 LOX`, preserve
captured workstation package intent, enforce an Xorg-only policy, and prepare
workstation builds to generate reusable binary packages in a Hasslehoff-hosted
repository.

## Naming

The canonical workstation binpkg/profile ID is:

```text
stage4-lox__stage5-workstation-nscde__<arch>__gpu-universal-xorg
```

`stage4-lox` means LLVM/Clang, OpenRC, and Xorg. The `<arch>` axis is one of
`amd64`, `arm64`, `ppc64le`, or `riscv`. CPU ABI or microarchitecture tuning is
metadata, not part of the default ID, unless two repositories for the same arch
must coexist.

## Inputs

The package inputs are:

- X12AGAIN live ISO package capture in `docs/workstation-package-capture/x12again-2026-05-06/`.
- Microbox live ISO package capture imported from `/tmp/microbox.gentoo-state-capture.tar`.
- Sanitized advisory Portage policy from former LLVM/Clang hosts:
  `/tmp/gentoo-portage-legiongo.tar` and `/tmp/gentoo-portage-susse.tar`.

The former Portage archives must not be imported wholesale because one archive
contains GnuPG/private-key material.

## Package Policy

The active NsCDE workstation profile remains a curated package list. Captured
host package lists are review inputs, not immediate active package targets.

The workstation GPU baseline is universal Xorg:

- NVIDIA proprietary driver and CUDA toolkit remain pinned.
- AMD support includes Mesa/RADV, ROCm/OpenCL tools, and AMDGPU-PRO userland
  atoms where Gentoo provides them.
- Intel support includes Mesa, Intel compute runtime, Level Zero, VAAPI, Vulkan,
  and Xorg driver support.
- Wayland, Plasma, SDDM, XWayland, wlroots, and xdg-desktop-portal are rejected
  from the Stage5 workstation primary candidate list.

## Binpkg Policy

Workstation builds should build packages by default and publish them under:

```text
/var/cache/binpkgs/stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg
```

For Hasslehoff builds, this path can be an NFS mount or bind mount backed by the
binpkg repository VM. The repository ID is stable and architecture-specific, so
future `arm64`, `ppc64le`, and `riscv` build farms can reuse the same naming
schema without embedding duplicate CPU ABI detail.

## Validation

Tests must verify:

- The workstation metadata exposes the normalized canonical ID.
- The workstation package policy includes NVIDIA, AMD, and Intel GPU support.
- Active workstation profile policy explicitly disables Wayland.
- Generated review candidates exclude the Wayland/Plasma reject set.
- Sanitized former-host policy docs do not include raw GnuPG material.
