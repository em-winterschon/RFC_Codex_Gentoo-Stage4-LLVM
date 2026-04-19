# gentoo-virt-qemu

Host-side helper files for bringing up a Gentoo QEMU/KVM VM with EDK2 firmware and selected host storage devices.

Contents:
- `gentoo-install-qemu-edk2.sh`: installs the basic QEMU/EDK2/minicom package set on the host, with optional `virt-viewer` and `libvirt`
- `qemu-pci-remap.sh`: binds selected host PCI devices to `vfio-pci` for passthrough
- `qemu-launch-minimal-vm.sh`: launches a minimal QEMU/KVM VM with EDK2 firmware, four host disks, and configurable console/display settings
- `etc_portage_make.conf`: host-side `make.conf` snippet tuned for the QEMU/EDK2 workflow used here

Recommended USE flags:
- `app-emulation/qemu`: `X gtk sdl slirp spice vnc`
  Why: `slirp` keeps `-netdev user` available, `gtk` and `sdl` cover local display modes, and `vnc`/`spice` cover remote graphics output.
- `app-emulation/virt-viewer`: `libvirt spice vnc`
  Why: `spice` and `vnc` let `virt-viewer` or `remote-viewer` connect to those QEMU backends, while `libvirt` keeps the client compatible if we later move this VM under libvirt management.

The prep script writes those flags into `${PACKAGE_USE_FILE:-/etc/portage/package.use/codex-qemu}` before the initial `emerge`. Override them with `QEMU_USE_FLAGS=...` or `VIRT_VIEWER_USE_FLAGS=...` if this host needs a different mix.

Notes:
- `qemu-pci-remap.sh` is machine-specific as committed. Review and edit the PCI BDFs and device expectations before running it on another host.
- `qemu-pci-remap.sh` now detects devices that are already unbound, refuses to continue when a device has no visible IOMMU group and unsafe no-IOMMU mode is disabled, and prints bind diagnostics when `vfio-pci` does not attach.
- Use `QEMU_PCI_REMAP_DRY_RUN=1 bash gentoo-virt-qemu/qemu-pci-remap.sh` to inspect the remap sequence without writing to sysfs.
- `qemu-launch-minimal-vm.sh` defaults to the four host disks from the current test layout:
  `BPOOL_DISK0` and `BPOOL_DISK1` for the mirrored SATADOM boot pool, plus `RPOOL_DISK0` and `RPOOL_DISK1` for the mirrored SATA root pool.
- The launcher presents those disks over AHCI so the guest sees SATA-style disks.
- The default net backend is `user`, which requires QEMU to be built with `USE=slirp`. The launcher checks backend support up front and suggests an alternate `QEMU_NETDEV_BACKEND` when that support is missing.
- The default display mode is `nographic`. Additional modes are available through `QEMU_DISPLAY_MODE`:
  `none`, `gtk`, `sdl`, `vnc`, and `spice`.
- `QEMU_DISPLAY_MODE=vnc` requires QEMU built with `USE=vnc`; `QEMU_DISPLAY_MODE=spice` requires QEMU built with `USE=spice` and is intended to be paired with `app-emulation/virt-viewer`.
- `QEMU_SERIAL_MODE` controls the serial path: `auto`, `stdio`, `pty`, or `none`. In `auto`, `nographic` uses QEMU's integrated stdio console, while graphical/remote display modes add `-serial mon:stdio`.
- `PCI_NETWK` is optional and blank by default. If you set it, the launcher validates that the device is on real IOMMU-backed VFIO before adding `vfio-pci,host=...`.
- `qemu-launch-minimal-vm.sh` explicitly rejects devices that only appear as `/dev/vfio/noiommu-<group>` because that is not the real IOMMU-backed VFIO path this workflow needs.
- `app-emulation/virt-viewer` is the right client-side package for SPICE or VNC console access on Gentoo.
- `app-emulation/libvirt` is only needed if the workflow moves to libvirt-managed domains and you specifically want `virsh console <vmname>`. The current launcher is raw QEMU, so `virsh console` does not apply yet.
- `dev-python/pyvirtualdisplay` is not part of the recommended workflow here. It is a Python wrapper around Xvfb/Xephyr/Xvnc for host-side application displays, not a VM console transport.
- The `make.conf` fragment is policy-specific; treat it as a starting point rather than a universal default.

Examples:
- Text-mode installer over stdio:
  `bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- GTK window plus serial console on the launching terminal:
  `QEMU_DISPLAY_MODE=gtk bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- VNC display on localhost port 5901 plus serial console on the launching terminal:
  `QEMU_DISPLAY_MODE=vnc QEMU_VNC_ADDRESS=127.0.0.1:1 bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- SPICE display on localhost port 5930 plus serial console on the launching terminal:
  `QEMU_DISPLAY_MODE=spice QEMU_SPICE_PORT=5930 bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- PTY serial console with no graphics:
  `QEMU_DISPLAY_MODE=none QEMU_SERIAL_MODE=pty bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`

Validation and debugging:
- `bash tests/shell/test_qemu_launch_minimal_vm.sh` runs the unit tests for `qemu-launch-minimal-vm.sh`
- `bash tests/shell/test_qemu_pci_remap.sh` runs the unit tests for `qemu-pci-remap.sh`
- `bash tests/shell/run-tests.sh` runs the shell validation sequence used in CI
- `bash tests/shell/debug-qemu-launch-minimal-vm.sh` launches `qemu-launch-minimal-vm.sh` under `bashdb` with dry-run mode enabled by default

Sources:
- Gentoo `app-emulation/qemu`: https://packages.gentoo.org/packages/app-emulation/qemu
- Gentoo `app-emulation/virt-viewer`: https://packages.gentoo.org/packages/app-emulation/virt-viewer
- Gentoo `app-emulation/libvirt`: https://packages.gentoo.org/packages/app-emulation/libvirt
- Gentoo `dev-python/pyvirtualdisplay`: https://packages.gentoo.org/packages/dev-python/pyvirtualdisplay
- `virsh console` manual: https://www.libvirt.org/manpages/virsh.html
- libvirt domain graphics formats: https://libvirt.org/formatdomaincaps.html
