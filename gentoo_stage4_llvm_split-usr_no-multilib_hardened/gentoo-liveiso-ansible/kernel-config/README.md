# Kernel Config Registry

This directory is the repo-owned source of truth for Stage4/Stage5 kernel
configuration intent.

The fragments are reviewable Linux Kconfig fragments. They are not yet the live
renderer for netboot or installed-host kernels. A follow-on implementation
should merge the selected fragments against the exact kernel source tree, fail
on unknown symbols, and record the selected package atom plus the final config
hash in the host E2ET report.

Primary map:

- `kernel-profile-map.yml`: base, machine-role, hardware-subprofile, and
  service-overlay composition map.

Fragment layout:

- `fragments/base/`: common minimum kernel support.
- `fragments/machine/`: bare-metal, virtual guest, and hypervisor overlays.
- `fragments/hardware/`: hardware-dependent overlays such as Optane NVDIMM and
  universal Xorg GPU support.
- `fragments/storage/`: NFS, RDMA storage, NVMe-oF, and ZFS compatibility.
- `fragments/network/`: fabric-specific networking such as RoCE-v2 hosts.
- `fragments/observability/`: BMC/IPMI/Redfish local host support.
