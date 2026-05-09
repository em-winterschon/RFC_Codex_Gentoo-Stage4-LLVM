# Former LLVM/Clang Portage Policy Notes

This directory stores sanitized policy observations from two former LLVM/Clang
Gentoo hosts:

- `legiongo`: AMD Z1 Extreme class workstation.
- `susse`: Intel i9/Xe graphics class workstation.

The raw archives are intentionally not imported. The `susse` archive contains
GnuPG/private-key material under `/etc/portage/gnupg`, so only policy summaries
and selected advisory package atoms are tracked.

Useful shared policy:

- LLVM/Clang toolchain with `CC=clang`, `CXX=clang++`, and `LD=ld.lld`.
- OpenRC system policy with `-systemd`.
- Xorg-first desktop policy with `X`, `elogind`, `udev`, `opengl`, `vulkan`,
  `vaapi`, and explicit `-wayland`.
- Binary packages enabled with `--buildpkg=y`, `--with-bdeps=y`,
  `--complete-graph=y`, and `--binpkg-respect-use=y`.
- `VIDEO_CARDS` included Intel, AMDGPU, radeonsi, fbdev, and vesa.
- Mesa, QEMU, GTK, Chromium/libva, and related media packages explicitly
  disabled Wayland where the USE flag was available.

These observations support the Stage4 LOX workstation policy:

```text
stage4-lox__stage5-workstation-nscde__<arch>__gpu-universal-xorg
```

CPU-specific tuning remains metadata, not part of the default repository ID.
