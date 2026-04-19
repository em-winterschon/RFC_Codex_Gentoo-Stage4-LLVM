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
- The launcher now chooses a display device automatically:
  `qxl-vga` for `spice`, `virtio-vga` for `gtk`/`sdl`/`vnc`, and `std` VGA for text-oriented modes. Override with `QEMU_VIDEO_DEVICE=` if needed.
- `QEMU_DISPLAY_MODE=vnc` requires QEMU built with `USE=vnc`; `QEMU_DISPLAY_MODE=spice` requires QEMU built with `USE=spice` and is intended to be paired with `app-emulation/virt-viewer`.
- `QEMU_SERIAL_MODE` controls the serial path: `auto`, `stdio`, `pty`, `tcp`, or `none`. In `auto`, `nographic` uses QEMU's integrated stdio console, while graphical/remote display modes add `-serial mon:stdio`.
- `QEMU_SERIAL_MODE=tcp` requires this PR #7 launcher revision or later. Older host-local copies such as `/opt/gentoo-virt-qemu/qemu-launch-minimal-vm.sh` may only support `auto`, `stdio`, `pty`, and `none`.
- `PCI_NETWK` is optional and blank by default. If you set it, the launcher validates that the device is on real IOMMU-backed VFIO before adding `vfio-pci,host=...`.
- `qemu-launch-minimal-vm.sh` explicitly rejects devices that only appear as `/dev/vfio/noiommu-<group>` because that is not the real IOMMU-backed VFIO path this workflow needs.
- `app-emulation/virt-viewer` is the right client-side package for SPICE or VNC console access on Gentoo.
- `app-emulation/libvirt` is only needed if the workflow moves to libvirt-managed domains and you specifically want `virsh console <vmname>`. The current launcher is raw QEMU, so `virsh console` does not apply yet.
- `dev-python/pyvirtualdisplay` is not part of the recommended workflow here. It is a Python wrapper around Xvfb/Xephyr/Xvnc for host-side application displays, not a VM console transport.
- The `make.conf` fragment is policy-specific; treat it as a starting point rather than a universal default.

What to connect to:
- SPICE is a graphics/display channel. It does not replace the guest serial console by itself.
- For reliable text interaction during install, use one of the serial modes (`stdio`, `pty`, or `tcp`) in addition to or instead of SPICE/VNC.
- If SPICE shows corrupted or useless output, the first things to verify are that QEMU actually has `USE=spice`, the launcher is using `qxl-vga`, and the guest is not relying solely on a serial console that SPICE will never show.

Exact connection commands:
- Local text-mode installer on the launching terminal:
  `bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- GTK window plus serial console on the launching terminal:
  `QEMU_DISPLAY_MODE=gtk bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- SDL window plus serial console on the launching terminal:
  `QEMU_DISPLAY_MODE=sdl bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- VNC on the QEMU host, listening on localhost display `:1` and serial on the launching terminal:
  `QEMU_DISPLAY_MODE=vnc QEMU_VNC_ADDRESS=127.0.0.1:1 bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- Connect to that VNC session from another host with a tunnel:
  `ssh -L 5901:127.0.0.1:5901 qemu-host`
  then either `remote-viewer vnc://127.0.0.1:5901` or a VNC client pointed at `127.0.0.1:5901`
- SPICE on the QEMU host, listening on all interfaces port `5930`, plus a TCP serial console on port `4555`:
  `QEMU_DISPLAY_MODE=spice QEMU_SPICE_OPTIONS='port=5930,addr=0.0.0.0,disable-ticketing=on' QEMU_SERIAL_MODE=tcp QEMU_SERIAL_TCP='0.0.0.0:4555,server=on,wait=off,telnet=on' bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
- Connect to that SPICE session from another host:
  `remote-viewer spice://qemu-host:5930`
  If you prefer an encrypted hop, tunnel it instead:
  `ssh -L 5930:127.0.0.1:5930 qemu-host`
  then `remote-viewer spice://127.0.0.1:5930`
- Connect to the TCP serial console from another host:
  `telnet qemu-host 4555`
  or over SSH tunnel:
  `ssh -L 4555:127.0.0.1:4555 qemu-host`
  then `telnet 127.0.0.1 4555`
- PTY serial console with no graphics on the QEMU host:
  `QEMU_DISPLAY_MODE=none QEMU_SERIAL_MODE=pty bash gentoo-virt-qemu/qemu-launch-minimal-vm.sh`
  QEMU will print the allocated PTY path, which you can open locally with `screen`, `minicom`, or `picocom`.

Raw QEMU equivalents:
- SPICE graphics with QXL and TCP serial:
  `-device qxl-vga -display none -spice port=5930,addr=0.0.0.0,disable-ticketing=on -serial tcp:0.0.0.0:4555,server=on,wait=off,telnet=on`
- VNC graphics with virtio VGA and stdio serial:
  `-device virtio-vga -display none -vnc 127.0.0.1:1 -serial mon:stdio`

Validation and debugging:
- Check display backends:
  `qemu-system-x86_64 -display help`
- Check net backends:
  `qemu-system-x86_64 -netdev help`
- Check device availability:
  `qemu-system-x86_64 -device help | grep -E 'qxl|virtio-vga|virtio-gpu'`
- Run the launcher unit tests:
  `bash tests/shell/test_qemu_launch_minimal_vm.sh`
- Run the shell validation sequence used in CI:
  `bash tests/shell/run-tests.sh`
- Launch under `bashdb` with dry-run mode enabled by default:
  `bash tests/shell/debug-qemu-launch-minimal-vm.sh`

Sources:
- Gentoo `app-emulation/qemu`: https://packages.gentoo.org/packages/app-emulation/qemu
- Gentoo `app-emulation/virt-viewer`: https://packages.gentoo.org/packages/app-emulation/virt-viewer
- Gentoo `app-emulation/libvirt`: https://packages.gentoo.org/packages/app-emulation/libvirt
- Gentoo `dev-python/pyvirtualdisplay`: https://packages.gentoo.org/packages/dev-python/pyvirtualdisplay
- QEMU virtio-gpu docs: https://www.qemu.org/docs/master/system/devices/virtio-gpu.html
- SPICE user manual: https://www.spice-space.org/spice-user-manual.html
- `virsh console` manual: https://www.libvirt.org/manpages/virsh.html
- libvirt domain graphics formats: https://libvirt.org/formatdomaincaps.html
