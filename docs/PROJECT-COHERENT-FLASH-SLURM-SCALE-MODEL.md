# Project Coherent Flash SLURM Scale Model

## Scope

This is a simulation-only plan for Project Coherent Flash. The first milestone
is a repeatable SLURM job bundle that generates metrics and a conformance report.
It performs no production storage mutation.

## ADR Mapping

| ADR | Simulation job | Output |
| --- | --- | --- |
| ADR-001 | SLO baseline and workload taxonomy | latency, throughput, and durability targets |
| ADR-002 | KV/prefix cache locality model | cache-hit, eviction, and warm-prefix metrics |
| ADR-003 | object/model tier movement model | object tier placement and read-amplification metrics |
| ADR-004 | synthetic RDMA/NVMe-oF/NFS probes | protocol latency and failure-injection metrics |
| ADR-005 | DPU boundary simulation | BlueField2 offload decision matrix |
| ADR-006 | OpenZFS media layout model | pool/dataset/write-path comparison |
| ADR-007 | scheduler locality model | SLURM feature and partition placement evidence |
| ADR-008 | RAG/vector tier simulation | index build/query/update metrics |
| ADR-009 | observability and rollout gate | conformance report and dashboard feed list |

## SLURM Job Classes

- `coherent-kv-prefix-cache`: KV/prefix cache simulation with synthetic prompt
  reuse and eviction pressure.
- `coherent-object-tier`: model weight and corpus object placement simulation.
- `coherent-rag-vector-tier`: RAG/vector tier indexing and query simulation.
- `coherent-rdma-storage-probe`: synthetic NFS, NFS-RDMA, NVMe/TCP, and
  NVMe-RDMA probes after fabric admission.
- `coherent-dpu-boundary`: DPU boundary and BlueField2 offload decision model.

## Initial Host Placement

- Run controller actions from `sched-sun99-slurmctl-099071`.
- Run first simulation jobs on `sched-sun99-slurmwkr-099072`.
- Admit X12AGAIN only after `metal-x12again-workstation-xen-coherent` E2ET
  passes and BlueField2/Optane inventory is captured.

## Artifacts

Each job writes:

- job manifest with git commit, profile ID, partition, and host features.
- metrics JSON for Prometheus/VictoriaMetrics ingestion.
- structured logs for rsyslog to Elasticsearch.
- conformance report tying ADR expectations to observed results.

## Rollout Gate

The simulation bundle can graduate to live storage experiments only after:

- SLURM job bundle is reproducible.
- X12AGAIN E2ET passes.
- RoCE-v2 fabric validation passes.
- Rollback and backup media are verified.
- A human-approved change window explicitly permits storage mutation.
