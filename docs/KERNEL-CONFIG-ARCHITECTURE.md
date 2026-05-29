# Kernel Config Architecture

## Purpose

Kernel configuration must become a normalized, requirement-driven layer system
instead of a set of one-off profile comments and script defaults. The new source
of truth is:

- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/kernel-config/kernel-profile-map.yml`
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/kernel-config/fragments/`

Package atoms remain in `profile-package-lists/` and service role atoms remain
in `profile-service-atoms/stage5-role-service-atoms.yml`. Kernel fragments now
use the same model: a baseline plus machine, hardware, storage, network, and
observability overlays.

## Baseline Basic Minimal

The `basic-minimal` fragment is intended for metal, virtual, rescue netboot, and
Path-B images. It includes:

- UEFI and EFI stub boot support.
- initramfs support with `CONFIG_BLK_DEV_INITRD`.
- `devtmpfs`, `procfs`, `sysfs`, `tmpfs`, and pty support.
- SquashFS with gzip and xz, preserving current SquashFS/gzip netboot behavior.
- ext4, vfat, loop, overlayfs, basic NVMe/SCSI, and module support.
- serial console support for `console=ttyS0` workflows.
- cgroups, namespaces, seccomp, BPF, nftables, VLAN, bridge, bonding, tap/tun,
  and veth for VM/container readiness.
- enough crypto/device-mapper support for encrypted or verified boot flows.

This is a review baseline, not a live kernel mutation path yet. The next step is
a renderer that merges selected fragments against the exact kernel source tree
and fails on unknown symbols.

## Machine Role Layers

| Role | Fragment | Intent |
| --- | --- | --- |
| `metal-base` | `fragments/machine/metal-host.config` | ACPI, CPU frequency, RAS/EDAC, PCIe AER, USB serial, local block features. |
| `virtual-guest` | `fragments/machine/virtual-guest.config` | VirtIO, KVM/Xen/Hyper-V guest support, virtio console/network/storage. |
| `base-hypervisor-qemu-libvirt` | `fragments/machine/hypervisor-qemu-libvirt.config` | KVM, VFIO/IOMMU, vhost, tap/macvtap, traffic control. |
| `base-hypervisor-xen` | `fragments/machine/hypervisor-xen.config` | Xen Dom0 and backend drivers. |

## Hardware Subprofiles

Optane NVDIMM is explicitly a hardware subprofile, not a workstation default.
The workstation exception is X12AGAIN, also known as `prinzessin`, because it has
Intel Optane Series 200 NVDIMMs. Normal workstation hosts should not inherit
NVDIMM support unless inventory proves the hardware exists.

The `optane-nvdimm` fragment includes:

- `CONFIG_ACPI_NFIT`
- `CONFIG_LIBNVDIMM`
- `CONFIG_BLK_DEV_PMEM`
- `CONFIG_DEV_DAX`
- `CONFIG_DEV_DAX_PMEM`
- DAX and PMEM support needed by storage-tiering and Coherence-style roles.

The `gpu-universal-xorg` fragment supports monitor output across Intel, AMD,
NVIDIA/Nouveau fallback, QXL, virtio GPU, EFI framebuffer, and DRM/KMS. Userspace
package policy still decides proprietary NVIDIA, CUDA, AMDGPU-PRO, ROCm, and
Intel media/runtime packages.

Intel C3000 QAT is also a hardware subprofile. Use it for M70 and other Intel
Atom C3758 hosts where inventory proves the QuickAssist device is present. The
`intel-qat-c3000` fragment includes:

- `CONFIG_CRYPTO_DEV_QAT`
- `CONFIG_CRYPTO_DEV_QAT_C3XXX`
- `CONFIG_CRYPTO_DEV_QAT_C3XXXVF`
- `CONFIG_QAT_VFIO_PCI`
- `CONFIG_PCI_IOV`

The M70 runtime profile should load `qat_c3xxx`. Stock Gentoo repos checked on
the canary currently do not provide `qatlib`, `qatengine`, an OpenSSL QAT
provider, or QAT USE flags for `dev-libs/openssl`, `sys-fs/zfs`, or
`sys-fs/zfs-kmod`. The kernel and module policy should land first; OpenSSL and
OpenZFS userspace acceleration should follow through an explicit overlay/source
build path with validation before becoming default package policy.

## Service And Storage Overlays

| Overlay | Fragments | Notes |
| --- | --- | --- |
| `nfs-storage-client` | `storage/nfs-client.config` | NFSv3 default, NFSv4 with AAA UID/GID consistency, optional NFS-RDMA. |
| `rdma-storage-fabric` | `network/roce-v2-host.config`, `storage/rdma-storage-fabric.config`, `storage/nvmeof-initiator.config` | RoCE-v2, MLX5/QLogic/Broadcom RDMA, iSCSI, NVMe/TCP, NVMe/RDMA, multipath. |
| `storage-node` | ZFS, RDMA, NVMe-oF, Optane NVDIMM | For storage systems with local media and export duties. |
| `coherence-ce-node` | RDMA, NVMe-oF, Optane NVDIMM | For memory/data-tiering roles. |
| `observability-bmc-client` | `observability/redfish-ipmi.config` | Local IPMI, watchdog, TPM, and USB network support for management tooling. |

## CPU And Portage Tuning

The reference architecture file is `/tmp/docs/cpu-arch/RFC1918-CPU-Architectures.md`.
The datasheet directory is `/tmp/docs/cpu-arch/datasheets`.

Current repo state:

- `vars/cpu_profiles.yml` already drives `make.conf.j2` through
  `portage_cpu_profile`.
- Existing live profile defaults should remain stable until exact host capture
  data is available.
- The new `cpu_profile_policy` and `cpu_architecture_registry` blocks document
  candidate `-march`/`-mtune` selections for AMD EPYC, Intel Xeon/Core, ARM64,
  and POWER9 families.

Required capture for native host profiles:

```bash
cpuid2cpuflags
gcc -march=native -Q --help=target
clang --print-targets
```

Policy:

- Shared binpkg repos should prefer portable baselines such as `x86_64_v2` or
  `x86_64_v3` unless the repo name and consuming fleet are explicitly scoped to
  a CPU generation.
- `CPU_FLAGS_X86` should be generated from `cpuid2cpuflags` on real hardware and
  committed with provenance, not inferred from a datasheet name.
- ARM64 and POWER require Portage template work for CHOST, `-mcpu`, Rust target,
  and LLVM target differences before live optimized profiles are enabled.

## Gap Analysis

- Kernel config intent is currently split across `kernel_config`,
  `kernel_config_requirements`, inventory `kernel_config_fragment_files`, and
  Path-B shell scripts.
- Path-B kernel build flow does not yet consume `kernel-profile-map.yml`.
- Existing profile definitions need migration from inline kernel requirements
  to named kernel overlays.
- No renderer currently merges fragments, validates symbols, or records the
  final kernel config hash into E2ET output.
- Local CPU docs list architecture families, but exact `CPU_FLAGS_X86` values
  need capture from live hardware.
- ARM64 and ppc64le tuning is documented but not enabled in the live
  `make.conf.j2` path because the current template is x86_64 oriented.

## Next Implementation Step

Build `scripts/render_kernel_profile.py` to:

- Load `kernel-profile-map.yml`.
- Resolve baseline, machine role, hardware subprofiles, and service overlays.
- Emit an ordered fragment list and a merged config candidate.
- Validate each symbol against a selected kernel source tree.
- Write artifact metadata: kernel atom, source tree, fragment list, config hash,
  and host/profile identifiers for E2ET conformance.
