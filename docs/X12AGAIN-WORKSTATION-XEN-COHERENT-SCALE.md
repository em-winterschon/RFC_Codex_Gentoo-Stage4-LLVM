# X12AGAIN Workstation Xen Coherent Scale

## ITIL Change Control

Change target: reimage X12AGAIN from the long-running live environment into a
managed LOX Stage5 installed host using profile
`metal-x12again-workstation-xen-coherent`.

Business reason: X12AGAIN must stop being a mutable rescue/build workspace and
become a durable workstation, Xen/QEMU hypervisor, BlueField2/RDMA lab host,
and Project Coherent Flash scale-model host.

## Hard Gates

- K10 E2ET conformance has passed using the Hasslehoff netboot publisher.
- X12AGAIN full and post-shutdown delta backups are verified off-host.
- Netboot, RouterOS serial, Elasticsearch, rsyslog, ntfy, FreeIPA, NetBox, and
  observability duties remain off X12AGAIN.
- `metal-x12again-workstation-xen-coherent` renders through profile lint.
- The install plan preserves a backout decision point before destructive disk
  mutation.

## Implementation Scope

- Install LOX Stage4 amd64 LLVM/OpenRC plus Stage5 workstation Xorg/NsCDE.
- Add Xen/QEMU/libvirt host packages and VFIO/IOMMU readiness.
- Add Optane NVDIMM kernel/userland support for Intel Optane Persistent Memory
  200 namespace inspection.
- Add NFSv3, NFSv4, NFS over TCP, NFS-RDMA intent, NVMe-RDMA intent, iSER
  intent, and multipath packages.
- Keep BlueField2 and DOCA/OFED driver installation gated until kernel headers,
  PCI inventory, and RoCE-v2 switch policy are verified.

## SLURM Admission

X12AGAIN must not be added to the active `slurm_workers` inventory group during
initial imaging. The profile declares `worker_enabled: false` and
`admission_state: gated-until-e2et-pass`.

Admission sequence:

1. Complete installed-host E2ET.
2. Validate FreeIPA/SSSD login and UID/GID consistency.
3. Validate Xorg/NsCDE graphical login and serial console access.
4. Validate Xen/QEMU/libvirt health without consuming the BlueField2 fabric.
5. Validate BlueField2, Optane, and RDMA inventory.
6. Add X12AGAIN as a SLURM worker only after the conformance report passes.

## BlueField2 And RDMA Gate

BlueField2 is a storage/data-plane experiment boundary, not an initial install
dependency. First pass is read-only:

- Capture `lspci -Dnn`, IOMMU groups, kernel modules, firmware, and link state.
- Validate `mlx5_core`, `mlx5_ib`, `ib_uverbs`, `rdma_cm`, and `rdma link show`.
- Keep NFS-RDMA, NVMe-RDMA, and iSER disabled until RoCE-v2 switch policy is
  validated.

## Project Coherent Flash

Project Coherent Flash starts as a simulation-only workload submitted through
SLURM. There is no production storage mutation in this phase.

Initial simulations model:

- KV/prefix cache locality.
- Object/model tier movement.
- RAG/vector tier read/write behavior.
- Synthetic NFS/NVMe-oF/RDMA latency and failure modes.
- DPU boundary decisions for BlueField2.

## Validation

- `git diff --check`
- `bash tests/shell/test_x12again_reimage_coherent_scale.sh`
- `bash tests/shell/test_host_e2et_conformance_report.sh`
- Installed-host E2ET conformance report captured after first boot.
- SLURM admission validation after E2ET: `scontrol show nodes`, `srun hostname`,
  and a Project Coherent dry-run job.

## Backout

- Do not wipe disks until backup paths and rollback media are verified.
- If install fails before disk mutation, keep the current boot state intact.
- If install fails after disk mutation, restore from the verified off-host
  backup or reinstall from the same profile with mutation disabled.
- If network identity fails, keep root break-glass SSH and serial console
  available until FreeIPA/SSSD is repaired.
