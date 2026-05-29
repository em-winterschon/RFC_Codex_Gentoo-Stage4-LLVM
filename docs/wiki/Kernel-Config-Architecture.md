# Kernel Config Architecture

The kernel configuration source of truth is now staged under
`gentoo-liveiso-ansible/kernel-config/`.

Primary files:

- `kernel-profile-map.yml` maps baseline, machine role, hardware subprofile,
  service, storage, and observability overlays.
- `fragments/base/basic-minimal.config` is the review baseline for UEFI,
  initramfs, SquashFS/gzip, serial console, SSH rescue, VM/container primitives,
  and basic networking.
- `fragments/hardware/optane-nvdimm.config` is a hardware subprofile, not a
  generic workstation requirement.
- `fragments/hardware/intel-qat-c3000.config` is the Intel C3000 QAT hardware
  subprofile for M70/C3758 hosts.

Optane policy:

- X12AGAIN / `prinzessin` is a workstation exception because it has Intel Optane
  Series 200 NVDIMMs.
- Normal workstation roles should not inherit NVDIMM support.
- Storage nodes and Coherence/data-tiering nodes can request the Optane overlay
  when inventory proves the hardware exists.

QAT policy:

- M70/C3758 hosts should request `intel-qat-c3000`.
- The kernel profile enables `qat_c3xxx`, C3000 VF support, SR-IOV readiness,
  and QAT VFIO support.
- Stock Gentoo repos currently need an overlay/source path before OpenSSL or
  OpenZFS userspace QAT acceleration can be compiled as default policy.

CPU tuning policy:

- `vars/cpu_profiles.yml` keeps existing live `portage_cpu_profiles` stable.
- The new `cpu_profile_policy` and `cpu_architecture_registry` blocks document
  candidate `-march`/`-mtune` families from
  `/tmp/docs/cpu-arch/RFC1918-CPU-Architectures.md`.
- `CPU_FLAGS_X86` must be captured from hardware with `cpuid2cpuflags` before a
  native host profile is used for live package builds.

Current gap:

- The registry is declarative and has no live build impact yet.
- Path-B, profile YAML, and inventory fragment lists still need to migrate to
  this registry.
- A renderer/validator must merge fragments against the exact kernel source tree
  and fail on unknown symbols before this can drive live kernels.

Next implementation:

- Add a kernel-profile renderer.
- Add symbol validation against selected kernel sources.
- Add E2ET metadata capture for kernel atom, fragment list, and final config
  hash.
