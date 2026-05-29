# Kernel Config Layering Design

## Approved Design

Create a repo-owned kernel configuration registry that mirrors the package and
service role taxonomy:

- A baseline `basic-minimal` kernel fragment.
- Machine overlays for metal, virtual guests, QEMU/Libvirt hypervisors, and Xen.
- Hardware subprofiles for Optane NVDIMM and universal Xorg GPU support.
- Storage/network overlays for NFS, RDMA, NVMe-oF, ZFS, and RoCE-v2.
- Observability overlay for IPMI/BMC/Redfish client support.

This pass is declarative only. It must not change live netboot or installed
kernel behavior until a renderer and validator are implemented.

## Key Decision

Optane NVDIMM support is a hardware subprofile. X12AGAIN / `prinzessin` is a
workstation exception because it has Optane Series 200 NVDIMMs. Storage and
Coherence/data-tiering nodes can also request the Optane overlay when inventory
proves the hardware exists.

## Acceptance

- Kernel fragments live under `gentoo-liveiso-ansible/kernel-config/`.
- `kernel-profile-map.yml` maps profile composition.
- Docs identify current gaps and next renderer work.
- Tests prove the registry exists and contains the required baseline, Optane,
  service, and CPU tuning references.
