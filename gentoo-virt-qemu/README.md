# gentoo-virt-qemu

Host-side helper files for bringing up a Gentoo QEMU/KVM VM with EDK2 firmware and selected PCIe passthrough devices.

Contents:
- `gentoo-install-qemu-edk2.sh`: installs the basic QEMU/EDK2/minicom package set on the host
- `qemu-pci-remap.sh`: binds selected host PCI devices to `vfio-pci` for passthrough
- `qemu-launch-minimal-vm.sh`: launches a minimal QEMU/KVM VM with EDK2 firmware and the hard-coded passthrough devices
- `etc_portage_make.conf`: host-side `make.conf` snippet tuned for the QEMU/EDK2 workflow used here

Notes:
- `qemu-pci-remap.sh` is machine-specific as committed. Review and edit the PCI BDFs and device expectations before running it on another host.
- `qemu-pci-remap.sh` now detects devices that are already unbound, refuses to continue when a device has no visible IOMMU group and unsafe no-IOMMU mode is disabled, and prints bind diagnostics when `vfio-pci` does not attach.
- Use `QEMU_PCI_REMAP_DRY_RUN=1 bash gentoo-virt-qemu/qemu-pci-remap.sh` to inspect the remap sequence without writing to sysfs.
- `qemu-launch-minimal-vm.sh` is also host-specific as committed. Review the passthrough device BDFs, ISO paths, firmware path, CPU/memory sizing, and console settings before using it elsewhere.
- The `make.conf` fragment is policy-specific; treat it as a starting point rather than a universal default.

Validation and debugging:
- `bash tests/shell/test_qemu_launch_minimal_vm.sh` runs the unit tests for `qemu-launch-minimal-vm.sh`
- `bash tests/shell/test_qemu_pci_remap.sh` runs the unit tests for `qemu-pci-remap.sh`
- `bash tests/shell/run-tests.sh` runs the shell validation sequence used in CI
- `bash tests/shell/debug-qemu-launch-minimal-vm.sh` launches `qemu-launch-minimal-vm.sh` under `bashdb` with dry-run mode enabled by default
