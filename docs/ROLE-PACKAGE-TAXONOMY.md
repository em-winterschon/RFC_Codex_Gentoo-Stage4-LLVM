# Role Package Taxonomy

This repository tracks Stage 5 role package atoms as composable layers instead
of one-off host package lists. The intent is to keep bare-metal, VM, and
container-service builds auditable while preserving existing compatibility
profiles.

## Baseline Layers

- `base-minimal-nox`: non-graphical baseline for SSH, rsyslog, chrony, Portage
  tooling, diagnostics, shell operations, and standard UNIX network tools
  including `ethtool`, `ifconfig`, and `netstat`. It also carries the stable
  local monitoring set: `lm_sensors`, `htop`, `btop`, `iotop-c`, `lsof`,
  `psmisc`, `parallel`, `numactl`, `numad`, `time`, `anacron`,
  `daemontools`, `wait_on_pid`, and `watchpid`.
- `base-minimal-xorg-slim`: extends `base-minimal-nox` with Xorg, SLiM, xinit,
  xterm, libinput, and basic font support. Wayland remains explicitly out of
  scope for this layer.
- `base-hypervisor-xen`: extends `base-minimal-nox` plus common hypervisor
  storage/network atoms with Xen and Xen tools.
- `base-hypervisor-qemu-libvirt`: extends `base-minimal-nox` plus common
  hypervisor storage/network atoms with QEMU, Libvirt, and guestfs tooling.
- `base-hypervisor-xen-qemu-libvirt`: composes the Xen and QEMU/Libvirt
  hypervisor subtype package layers for hosts that must support both stacks.

VM roles compose the same base-minimal package layer rather than redefining
basic host behavior:

- `virt-minimal`: `base-minimal-nox` plus qemu-guest-agent and VM network
  diagnostics.
- `virt-xorg`: `virt-minimal` plus `base-minimal-xorg-slim` and SPICE/QXL guest
  display helpers.

Container service roles remain separated into the existing container runtime VM
profile and service-layer image definitions. The role atom registry references
`vm-container-services` so the runtime dependency chain remains visible.

Keyworded or Guru-only monitoring tools such as `bashtop`, `psinfo`, `rtirq`,
`pipectl`, and `procenv` are tracked as opt-ins rather than default base atoms
so stable profile builds do not depend on external overlays.

## Files

- Profile definitions: `gentoo-liveiso-ansible/profile-definitions/`
- Package lists: `gentoo-liveiso-ansible/profile-package-lists/`
- Service atom registry:
  `gentoo-liveiso-ansible/profile-service-atoms/stage5-role-service-atoms.yml`

The service atom registry tracks package atoms, OpenRC services, kernel modules,
and protocol surfaces for each role type. It is intentionally declarative; role
playbooks still own mutation and host-specific configuration.

## Compatibility

Existing profiles such as `vm-guest-simple-ipxe.yml`,
`vm-container-services.yml`, and `hypervisor-xen-qemu-libvirt-host.yml` are left
in place. New provisioning should prefer the explicit `base-*` and `virt-*`
profiles, while existing workflows can migrate incrementally.
