# Workstation NsCDE VM Design

## Goal

Add a Stage5 workstation VM profile that layers Xorg, SPICE guest support, and
NsCDE onto the existing Stage4 VM base, then validate it first on the on-host
QEMU system before Hasslehoff GPU passthrough testing.

## Architecture

The implementation keeps server profiles unchanged and introduces a separate
`vm-workstation-nscde` usage overlay. The overlay enables X11 and SPICE USE
policy only for the workstation profile, installs a normalized Xorg/NsCDE
package list, and delegates NsCDE source installation to a dedicated Ansible
role.

QEMU workstation launch support extends the existing stage3 launcher with
SPICE/QXL rendering and a virtio serial SPICE agent channel. A thin wrapper
sets workstation-safe defaults for instance name, display mode, SPICE port,
memory, vCPU count, serial port, and SSH forwarding.

## Components

- `vm-workstation-nscde.yml`: profile overlay and workstation-specific
  Portage, module, OpenRC, NsCDE, and readiness defaults.
- `stage5-virtual-host-workstation-nscde.packages`: normalized package atom
  list for Xorg, SPICE, fvwm3, and NsCDE runtime/build dependencies.
- `nscde_workstation`: Ansible role that downloads the pinned upstream source
  archive, verifies SHA256, builds NsCDE in the target chroot, installs
  `.xinitrc`, and adds the optional X session entry when present.
- `qemu-launch-workstation-nscde-vm.sh`: on-host QEMU launcher wrapper using
  SPICE/QXL defaults.
- Shell tests: assert profile registration and command rendering.

## Constraints

- OpenRC remains mandatory; systemd remains disabled.
- No display manager is required for the first pass.
- NsCDE is pinned to upstream tag `2.3` until a local overlay ebuild is added.
- Hasslehoff GPU passthrough is explicitly deferred until the on-host QEMU path
  is repeatable.

## Validation

The first validation pass is repo-local and non-destructive: shell tests verify
profile registration, SPICE command rendering, and wrapper defaults. The live
validation pass boots the VM on the on-host QEMU system, connects over SSH,
starts DBus and `spice-vdagent`, connects with a SPICE client, and starts NsCDE
through `startx`.
