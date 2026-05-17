# HPC Workload Scheduler Plan

## Purpose

This plan turns the scheduler research notes in
`/tmp/docs/hpc-schedulers/hpc-workload-schedulers-review.md` into an execution
track for distributed builds, batch jobs, RDMA-aware host validation, and later
HPC/AI workloads.

## Recommendation

Use SLURM first.

SLURM is the best first scheduler for this environment because it gives
deterministic resource partitions, explicit CPU/memory/GPU constraints,
operator-friendly accounting, and mature node health integration. That maps
directly to Portage/binpkg build jobs, disposable builder VMs, K10/X12AGAIN
validation jobs, GPU workstation validation, and future RDMA workloads.

HTCondor remains valuable as a later opportunistic-computing overlay for mixed
or federated resources, but it should not block the first build/HPC control
plane. Galaxy, UNICORE, ARC, and CVMFS are later layers once the local
scheduler, identity, storage, and observability baseline is stable.

## Candidate Stack

| Layer | First Choice | Later Evaluation |
| --- | --- | --- |
| Scheduler | SLURM | HTCondor |
| Node Health | NHC | Check_MK and E2ET integration |
| Data Distribution | NFSv3/NFSv4 first | CVMFS, object storage, RDMA transports |
| Provisioning | Ansible roles | OpenTofu for selected infrastructure state |
| User Portal | None first | Galaxy, UNICORE, ARC-CE |

## Phase 0: Preconditions

- FreeIPA or equivalent AAA must provide stable UID/GID identity.
- NetBox must model scheduler nodes, management IPs, service IPs, interfaces,
  and power control metadata.
- DNS automation must create A/CNAME records for scheduler services.
- NTP/chrony must be stable; the Stratum 1 time authority work should feed this.
- NFSv3 must exist for immediate shared artifacts, with NFSv4/RBAC and
  NFS-RDMA tracked as follow-up.
- Prometheus, VictoriaMetrics, Grafana, rsyslog, and Elasticsearch must collect
  scheduler and node telemetry.

## Phase 1: SLURM Pilot

Initial topology:

- Controller VM: `sched-sun99-slurmctl-0990xx.rfc1918.host`
- Database VM or colocated service: MariaDB for `slurmdbd`
- First worker partition: disposable builder VM plus K10 once stable
- Optional later worker partition: GPU workstation VM and X12AGAIN after reimage

Initial partitions:

- `build`: Portage, binpkg, distcc, rootfs, and artifact promotion jobs.
- `validation`: E2ET, netboot, service validator, and conformance jobs.
- `gpu-test`: NVIDIA/AMDGPU/Intel-display validation when hardware is present.
- `rdma-test`: RoCE-v2 and NFS-RDMA validation after switch/NIC tuning lands.

## Phase 2: Build Integration

- Convert long-running build scripts into batch job wrappers.
- Add job metadata for Stage4/Stage5 profile name, CPU profile, target
  architecture, package atom set, source branch, and output artifact path.
- Publish build artifacts to the binpkg/Nexus/NFS paths only after validation.
- Record job IDs and output artifact hashes in repo change logs or build
  metadata manifests.

## Phase 3: Node Feature Model

Use NetBox and Ansible inventory to generate SLURM node features:

- CPU vendor, generation, and microarchitecture.
- ISA flags relevant to Portage tuning.
- Memory capacity class.
- GPU vendor and model.
- RDMA capability.
- Storage locality.
- Power-control method.

These features allow jobs to request constraints such as `intel`, `amd`,
`nvidia`, `rdma`, `large-mem`, or future CPU microarchitecture labels without
hardcoding hostnames.

Issue #118 tracks this as `HPC-003`.

Initial feature taxonomy key:

```yaml
scheduler_node_feature_taxonomy:
  cpu_vendor:
    examples: [intel, amd, ibm-power]
    source: NetBox platform, Ansible facts, cpuid2cpuflags capture
  cpu_generation:
    examples: [raptor-lake, alder-lake, zen4, power9]
    source: CPU architecture registry and host facts
  isa_flags:
    examples: [avx2, avx512, aes, sha, fma]
    source: cpuid2cpuflags or equivalent architecture capture
  memory_class:
    examples: [standard-mem, large-mem, huge-mem]
    source: NetBox inventory and Ansible memory facts
  gpu_class:
    examples: [nvidia-compute, amd-display, intel-display]
    source: PCI inventory, driver policy, workstation role metadata
  rdma_class:
    examples: [rdma-none, roce-v2, nvme-rdma, nfs-rdma]
    source: RDMA-002/RDMA-003 validation and NIC inventory
  storage_locality:
    examples: [local-nvme, nfs-client, nvmeof-client]
    source: storage client profiles and mounted-filesystem E2ET evidence
  power_control:
    examples: [pdu-apc, ipmi-redfish, pikvm, manual]
    source: NetBox power-chain and BMC inventory
```

Do not mark a worker node eligible for `rdma-test` or storage-sensitive
partitions from static inventory alone. Require live E2ET or role validation
evidence before publishing the feature into generated `slurm.conf` intent.

## Phase 4: HTCondor And Grid Layer Review

Evaluate HTCondor after SLURM can run build and validation jobs reliably.

HTCondor is a better fit for opportunistic, heterogeneous, or federated compute.
It should be tested as an overlay rather than as the first critical-path
scheduler. Galaxy, UNICORE, and ARC should remain portal/grid experiments until
the local SLURM control plane is proven.

## Phase 5: Data Distribution

Start with NFS because it is the fastest path to shared artifacts.

Then evaluate:

- NFSv4 with FreeIPA-backed UID/GID consistency.
- NFS-RDMA once OFED/DOCA and RoCE-v2 tuning are stable.
- CVMFS for large read-only datasets, toolchains, and reproducible payloads.
- Object storage for agent memory and immutable build artifacts.

## Repo Scaffold State

Initial SLURM profile scaffolding is now repo-managed:

- Controller profile: `vm-slurm-controller`
- Worker overlay: `slurm-worker-node`
- Role: `slurm_cluster`
- Controller package list:
  `profile-package-lists/stage5-virtual-host-slurm-controller.packages`
- Worker package list:
  `profile-package-lists/stage5-slurm-worker-node.packages`
- Service atoms: `vm-slurm-controller` and `slurm-worker-node`

The scaffold is intentionally render-first. It writes `slurm.conf`,
`slurmdbd.conf`, and `cgroup.conf`, registers OpenRC action-service intent for
`slurmctld`, `slurmd`, and `slurmdbd`, and refuses to store MUNGE key material
in the repository. Live deployment still requires vaulted MUNGE/database
secret delivery, DNS/IPAM records, NetBox node features, and a non-production
controller VM.

## Immediate Action Items

- Create the first non-production SLURM controller VM from `vm-slurm-controller`.
- Add a scheduler service profile to the roadmap.
- Model scheduler nodes and partitions in NetBox.
- Add Ansible variables for node features and partition membership.
- Build a non-production SLURM controller VM.
- Run one no-op job, one E2ET validator job, and one small Portage build job.
- Add observability dashboards before expanding worker count.
