# Role Package Taxonomy

Stage 5 role package atoms are tracked as composable layers:

- `base-minimal-nox`: SSH, rsyslog, chrony, Portage tooling, diagnostics, and shell tools.
- `base-minimal-xorg-slim`: Xorg, SLiM, xinit, xterm, libinput, fonts, and no Wayland.
- `base-hypervisor-xen`: common hypervisor atoms plus Xen and Xen tools.
- `base-hypervisor-qemu-libvirt`: common hypervisor atoms plus QEMU, Libvirt, and guestfs tooling.
- `base-hypervisor-xen-qemu-libvirt`: combined Xen plus QEMU/Libvirt host profile.
- `virt-minimal`: `base-minimal-nox` plus qemu-guest-agent.
- `virt-xorg`: `virt-minimal` plus `base-minimal-xorg-slim` and SPICE/QXL guest helpers.

Service atoms are tracked in:

`gentoo-liveiso-ansible/profile-service-atoms/stage5-role-service-atoms.yml`

Existing compatibility profiles remain available while new provisioning moves
toward explicit `base-*` and `virt-*` composition.
