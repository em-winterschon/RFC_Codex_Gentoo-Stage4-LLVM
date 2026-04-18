# gentoo-virt-qemu

Host-side helper files for bringing up a Gentoo QEMU/KVM VM with EDK2 firmware and selected PCIe passthrough devices.

Contents:
- `gentoo-install-qemu-edk2.sh`: installs the basic QEMU/EDK2/minicom package set on the host
- `qemu-pci-remap.sh`: binds selected host PCI devices to `vfio-pci` for passthrough
- `etc_portage_make.conf`: host-side `make.conf` snippet tuned for the QEMU/EDK2 workflow used here

Notes:
- `qemu-pci-remap.sh` is machine-specific as committed. Review and edit the PCI BDFs and device expectations before running it on another host.
- The `make.conf` fragment is also policy-specific; treat it as a starting point rather than a universal default.
