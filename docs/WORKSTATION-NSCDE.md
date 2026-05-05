# Stage5 NsCDE Workstation VM

## Purpose

`vm-workstation-nscde` is a Stage5 virtual-host usage profile for interactive
desktop validation on the on-host QEMU system before GPU-passthrough testing on
Hasslehoff.

The first target is deliberately conservative:

- Stage4 merged-usr LLVM/OpenRC VM base
- Xorg, QXL, and SPICE guest integration
- NsCDE source install pinned to upstream tag `2.3`
- no display manager requirement for the first pass
- `startx` / `.xinitrc` starts `/opt/NsCDE/bin/nscde`

## Files

- Profile:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-workstation-nscde.yml`
- Metadata:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-workstation-nscde.metadata.yml`
- Package list:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/stage5-virtual-host-workstation-nscde.packages`
- Role:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nscde_workstation/`
- On-host launcher:
  `gentoo-virt-qemu/qemu-launch-workstation-nscde-vm.sh`

## NsCDE Source Policy

The upstream install guide documents a Gentoo dependency set and a source
install path using `./configure`, `make`, and `make install`.

Current local Gentoo package naming differs from the upstream list in several
places, so the profile normalizes package atoms:

- `x11-base/xorg-x11` becomes explicit `xorg-server`, `xorg-apps`,
  `xorg-drivers`, `xorg-fonts`, and `xinit` atoms.
- `dev-python/PyQt5` becomes `dev-python/pyqt5`.
- `x11-wm/fvwm` becomes `x11-wm/fvwm3`.
- `dev-qt/qtstyleplugins` is omitted until a current local package or overlay
  source is selected.

NsCDE is pinned to:

```text
version: 2.3
source_url: https://github.com/NsCDE/NsCDE/archive/refs/tags/2.3.tar.gz
source_sha256: fc4fd5f16b901b865f44b7483fa01a28189b5d5b95766375e026cc317456b297
```

## QEMU SPICE Defaults

Use:

```bash
QEMU_LAUNCH_DRY_RUN=1 bash gentoo-virt-qemu/qemu-launch-workstation-nscde-vm.sh
```

Default workstation launch settings:

- `INSTANCE_NAME=vm-workstation-nscde`
- `QEMU_DISPLAY_MODE=spice`
- `QEMU_VIDEO_DEVICE=qxl-vga`
- `QEMU_SPICE_PORT=5931`
- `SSH_READY_PORT=2231`
- `QEMU_SMP=16`
- `QEMU_MEMORY_MIB=32768`

Connect from the host with a SPICE client such as:

```bash
remote-viewer spice://127.0.0.1:5931
```

## Validation

Minimum validation gates:

1. Shell tests pass for profile registration and SPICE command rendering.
2. The VM boots and SSH responds on the selected forwarded port.
3. `rc-service dbus status` succeeds.
4. `rc-service spice-vdagent status` succeeds when launched with SPICE agent
   channel support.
5. `startx` starts NsCDE using `/root/.xinitrc` or a user inherited from
   `/etc/skel/.xinitrc`.

## Follow-On Work

- Add a local overlay ebuild for NsCDE after the source-install path is
  validated.
- Add display-manager support only after the manual `startx` session is stable.
- Add Hasslehoff GPU passthrough validation after hardware selection and
  installation.
