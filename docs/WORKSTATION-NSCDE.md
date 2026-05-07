# Stage5 NsCDE Workstation VM

## Purpose

`vm-workstation-nscde` is a Stage5 virtual-host usage profile for interactive
desktop validation on the on-host QEMU system before GPU-passthrough testing on
Hasslehoff.

The current target is `Stage4 LOX` plus a Stage5 NsCDE workstation overlay:

- Stage4 LOX means LLVM/Clang, OpenRC, and Xorg
- Canonical ID:
  `stage4-lox__stage5-workstation-nscde__<arch>__gpu-universal-xorg`
- Active amd64 binpkg ID:
  `stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg`
- Xorg, QXL, and SPICE guest integration
- NsCDE source install pinned to upstream tag `2.3`
- NVIDIA Quadro K1200 passthrough validation on Hasslehoff
- AMDGPU/ROCm/AMDGPU-PRO and Intel Xe/Level Zero/OpenCL/Vulkan package
  readiness for later workstation variants
- CUDA userland pinned to the newest locally available CUDA 12.9.1 ebuild
- optional SLiM display-manager session integration
- `startx` / `.xinitrc` starts `/opt/NsCDE/bin/nscde`

Wayland, Plasma, SDDM, XWayland, wlroots, and xdg-desktop-portal are
intentionally rejected in the Stage4 LOX workstation policy.

## Files

- Profile:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-workstation-nscde.yml`
- Metadata:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-workstation-nscde.metadata.yml`
- Package list:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/stage5-virtual-host-workstation-nscde.packages`
- NsCDE source-install role:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nscde_workstation/`
- Cross-OS session-stack role:
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/workstation_session_stack/`
- On-host launcher:
  `gentoo-virt-qemu/qemu-launch-workstation-nscde-vm.sh`

## Workstation Session Stack Model

The repo uses `workstation_session_stack` as the shared moniker for display
manager, desktop environment, and window manager wiring. This keeps the role
taxonomy portable:

- Display manager: `slim`
- Desktop environment: `nscde`
- Window manager: `fvwm3`

The role normalizes OS-family aliases before selecting OS-specific tasks:

- `gentoo` uses Portage atoms such as `x11-misc/slim` and `x11-wm/fvwm3`.
- `debian`, `devuan`, and `ubuntu` share the Debian-family task path.
- `freebsd`, `freebsd14`, and `freebsd-14` share the FreeBSD task path.
- `solaris`, `solaris11`, `solaris-11.4`, `tribblix-ce`, `omnios`, and
  `openindiana` share the Solaris-family task path.

Package installation commands are gated by
`workstation_session_stack_package_install_enabled=false` by default. Gentoo
image builds still prefer package-list driven installation, while FreeBSD and
Solaris-family hosts can opt into their native package-manager commands once
their repository policy is defined.

## Universal Xorg GPU Policy

The active workstation package list now prebuilds the Xorg-capable GPU stack
for expected workstation hardware families:

- NVIDIA proprietary driver and CUDA toolkit remain pinned for the K1200 test
  VM.
- AMD includes Mesa/RADV, ROCm/OpenCL tooling, AMDGPU-PRO Vulkan/AMF userland
  atoms where Gentoo provides them, and AMDGPU Xorg driver support.
- AMDGPU-PRO OpenCL is advisory-only by default because Gentoo's ebuild is
  fetch-restricted and conflicts with the Mesa OpenCL path. Enable it only after
  the required upstream distfile and USE-policy tradeoff are explicit.
- Intel support is display-only by default: Mesa, libdrm, libva, firmware, and
  `x11-drivers/xf86-video-intel` are retained for connected monitors.
- Intel compute/runtime atoms are intentionally excluded from the base
  workstation profile. `dev-util/intel-graphics-compiler` currently hard-locks
  to `LLVM_COMPAT=( 16 )`, which pulls old LLVM slot `16`; keep IGC, Level Zero,
  `intel-compute-runtime`, `intel-metrics-library`, and `gmmlib` in an optional
  hardware-specific overlay if they are ever needed.

The active package list is still curated. Captured host package lists are stored
under `docs/workstation-package-capture/` for review and are not automatically
converted into emerge targets.

Workstation builds emit binpkgs by default under:

```text
/var/cache/binpkgs/stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg
```

On Hasslehoff this path can be backed by an NFS or bind mount from the binpkg
repository VM so package rebuilds survive VM replacement cycles.

The live Hasslehoff binpkg sink currently exports:

```text
/srv/stage5-binpkgs/stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg
```

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

## Hasslehoff GPU Workstation VM

The first Hasslehoff GPU validation VM is:

| Field | Value |
| --- | --- |
| VMID | `1094` |
| Name | `vm-workstation-nscde-gpu01` |
| Management IP | `172.16.99.94/24` |
| Stage5 role | `workstation-nscde` |
| Source image | `/var/lib/vz/template/cache/vm-workstation-nscde.qcow2` |
| GPU passthrough | NVIDIA Quadro K1200 VGA `0000:01:00.0`, audio `0000:01:00.1` |
| Serial console | Proxmox `serial0=socket`; guest kernel uses `console=ttyS0,115200 console=tty0` |
| Management NIC | `net0` on `vmbr0` |
| High-speed test NICs | `net1` / `net2` on `vmbr-qlogic0`, VLAN tags `1098` and `1099` |

QLogic SR-IOV was requested for one VF per physical port, but the installed
QL41232HOCU functions currently expose no SR-IOV capability to Linux:

```text
/sys/bus/pci/devices/0000:04:00.0/sriov_totalvfs: absent
/sys/bus/pci/devices/0000:04:00.1/sriov_totalvfs: absent
lspci SR-IOV capability: absent
```

The operational fallback is a host-side `802.3ad` bond over `enp4s0f0` and
`enp4s0f1`, a VLAN-aware Proxmox bridge `vmbr-qlogic0`, and per-VM virtio NICs
on explicit VLAN tags. This preserves the LACP uplink and keeps VM networking
observable through the host bridge.

Use the Proxmox wrapper from the repo root:

```bash
bash scripts/proxmox-create-workstation-nscde-gpu-vm.sh --dry-run
PROXMOX_APPLY=1 PROXMOX_REPLACE=1 bash scripts/proxmox-create-workstation-nscde-gpu-vm.sh --apply
```

The generic Proxmox VM creator resolves the imported disk from the `unusedN`
entry reported by `qm config` after `qm importdisk`. This avoids stale zvol
suffix assumptions during replacement cycles.

## NVIDIA And CUDA Pinning

The K1200 is a Maxwell GPU, so the workstation profile pins the driver to the
R580 branch rather than letting Portage select newer branches intended for
newer GPUs:

```text
=x11-drivers/nvidia-drivers-580.159.03-r1
=dev-util/nvidia-cuda-toolkit-12.9.1-r1
```

The profile carries the required `~amd64` keyword gates and license grants:

```text
=x11-drivers/nvidia-drivers-580.159.03-r1 ~amd64
=dev-util/nvidia-cuda-toolkit-12.9.1-r1 ~amd64
=x11-drivers/nvidia-drivers-580.159.03-r1 NVIDIA-2025
=dev-util/nvidia-cuda-toolkit-12.9.1-r1 NVIDIA-CUDA
```

It also masks `>x11-drivers/nvidia-drivers-580.159.03-r1` for this profile so
future image builds do not silently advance the K1200 VM onto an incompatible
driver branch.

Live VM `1094` validation after the guest driver blacklist reboot showed:

```text
nouveau modules: none
nvidia modules: nvidia_uvm,nvidia_drm,nvidia_modeset,nvidia
nvidia-smi: Quadro K1200, driver 580.159.03, 4096 MiB
nvcc: CUDA compilation tools, release 12.9, V12.9.86
```

The GPU driver and CUDA userland are validated. Physical video output and the
Xorg physical-output gate was validated through PiKVM after forcing Xorg to
drive the K1200 directly at `1280x720@60`.

The scrambled PiKVM web video was not a WebRTC/H.264/MJPEG issue. A raw
uStreamer snapshot showed the corruption before browser transport. The VM was
booting with QXL as primary framebuffer and NVIDIA as a later secondary
framebuffer, while the K1200 emitted a captureable but corrupted default
console mode. Starting Xorg on the NVIDIA GPU and setting `1280x720@60`
produced a clean PiKVM frame.

The stable path is an opt-in display policy overlay:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/vm-workstation-nscde.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-workstation-nscde-gpu-pikvm.yml"
```

That overlay renders:

```text
/etc/X11/xorg.conf.d/90-workstation-gpu-display.conf
/usr/local/sbin/workstation-gpu-display-test
```

For the live VM, the validation helper leaves Xorg running on display `:7`
with the deterministic `PiKVM K1200 deterministic test pattern` xterm. The
captured PiKVM mode is `1280x720p60` and Direct H.264 is confirmed readable.

## On-Host Image Build

The first workstation build is intentionally staged on the on-host QEMU system
before Hasslehoff validation. The build path uses the standard LLVM/OpenRC
stage3 base plus the workstation package list and injects profile-specific
Portage fragments through the QCOW builder:

```bash
STAGE3_MAKE_CONF_APPEND='
MAKEOPTS="-j48 -l64"
EMERGE_DEFAULT_OPTS="--jobs=3 --load-average=64 --buildpkg=y --with-bdeps=y --complete-graph=y --autounmask=y --autounmask-backtrack=y --autounmask-continue=y --autounmask-unrestricted-atoms=y --autounmask-use=y --autounmask-write=y --binpkg-respect-use=y"
FEATURES="${FEATURES} buildpkg parallel-fetch"
PORTAGE_TMPDIR="/dev/shm/portage-tmpfs"
PKGDIR="/var/cache/binpkgs"
USE="${USE} X dbus gtk qt5 spice truetype xinerama elogind udev -systemd -wayland"
VIDEO_CARDS="${VIDEO_CARDS} intel amdgpu radeonsi fbdev vesa qxl modesetting nvidia"
INPUT_DEVICES="${INPUT_DEVICES} libinput evdev"
PKGDIR="/var/cache/binpkgs/stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg"
'
STAGE3_PACKAGE_USE_APPEND='
app-text/xmlto text
app-emulation/spice-vdagent gtk -systemd
media-libs/mesa X lm-sensors opencl opengl proprietary-codecs vaapi vulkan vulkan-overlay zstd -debug -selinux -test -wayland
media-libs/libva X glx -wayland
media-libs/vulkan-loader X -wayland
media-libs/freetype harfbuzz png
dev-python/pillow -truetype
x11-base/xorg-server xorg elogind udev -systemd
=dev-util/nvidia-cuda-toolkit-12.9.1-r1 clang profiler -debugger -examples -nsight -rdma -sanitizer
=x11-drivers/nvidia-drivers-580.159.03-r1 X tools -kernel-open -persistenced -powerd -wayland
'
STAGE3_PACKAGE_UNMASK_APPEND='
>=dev-python/pyqt5-5.15.11
>=dev-python/pyqt5-sip-12.18.0
'
```

The builder creates `/dev/shm/portage-tmpfs`, `/var/cache/binpkgs`, and
`/var/log/portage` inside the target before running Portage so RAM-backed
temporary builds and binpkg output work during bootstrap.

For the live Hasslehoff GPU VM, use disk-backed `PORTAGE_TMPDIR=/var/tmp/portage`
instead. CUDA preflight requires more than `7 GiB` of workspace and the VM has a
smaller tmpfs than the on-host build machine.

The PyQt5 unmask is explicit because Gentoo masked `dev-python/pyqt5` pending
tree removal while the current NsCDE upstream install path still expects PyQt5.
If NsCDE moves to PyQt6 or a local overlay ebuild replaces that dependency, this
profile should drop the unmask.

`dev-python/pillow -truetype` is scoped to the workstation bootstrap to break
the initial `docutils -> pillow -> harfbuzz -> glib -> docutils` build-time
cycle reported by Portage. Revisit after the first image has binpkgs available.

Current live-build convention:

```bash
tmux attach -t codex-workstation-nscde-build
tail -f /opt/gentoo-virt-qemu/workstation-nscde/logs/latest.log
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
6. Optional SLiM session entry presents `nscde` as the selected desktop
   environment after `workstation_session_stack` has been applied.
7. GPU passthrough guests can run `workstation-gpu-display-test` to force a
   deterministic NVIDIA Xorg mode for PiKVM capture validation.

## Follow-On Work

- Add a local overlay ebuild for NsCDE after the source-install path is
  validated.
- Apply SLiM and the final NsCDE startup path on live VM `1094`; the NVIDIA
  Xorg/PiKVM display policy is now validated independently.
- Decide whether the production display default should remain `1280x720@60` for
  PiKVM stability or move back to `1920x1080@60` after EDID/adapter testing.
