# AI/ML HPC Supercomputer Hardware And Network Meta-Analysis

## Source Boundary

This first pass uses public benchmark/list data and should be treated as a
planning analysis, not a procurement recommendation. Primary references:

- TOP500 November 2025 list: <https://www.top500.org/lists/top500/list/2025/11/>
- Green500 November 2025 list: <https://www.top500.org/lists/green500/list/2025/11/>
- HPCG November 2025 list: <https://www.top500.org/lists/hpcg/2025/11/>

## Observed 2025 Pattern

The current high-end trend is heterogeneous accelerator nodes with very high
fabric bandwidth and explicitly tuned storage/data paths:

- AMD integrated CPU/GPU and HPE Slingshot dominate the leading US exascale
  entries, represented by El Capitan and Frontier.
- Intel CPU plus Intel GPU architecture remains represented by Aurora.
- NVIDIA GH200/H100 systems show strong AI/HPC specialization, with JUPITER
  Booster and cloud-scale H100 systems illustrating the direction.
- Interconnect is not incidental: Slingshot-11, NVIDIA InfiniBand NDR/NDR200,
  and equivalent high-bisection fabrics are core design inputs.
- Efficiency rankings increasingly reward dense accelerator nodes and
  integrated memory/fabric designs, not just peak LINPACK.

## Workload Specialization Matrix

| Workload | Hardware Bias | Network Bias | Storage Bias |
| --- | --- | --- | --- |
| Dense AI training | NVIDIA H100/GH200 class or comparable accelerator nodes | NDR/NDR200 or equivalent low-latency GPU fabric | high-throughput object and checkpoint storage |
| Coupled simulation | CPU/GPU systems with strong memory bandwidth | low-latency high-bisection fabric | parallel filesystem, burst buffer, restart/checkpoint path |
| Sparse linear algebra | memory bandwidth and cache behavior matter more than peak tensor ops | predictable latency and topology awareness | lower bandwidth but consistent latency |
| Inference serving | accelerator density, MIG/partitioning, and power efficiency | service mesh plus east/west model-cache traffic | model registry and local cache tier |
| Data analytics | memory capacity and storage locality | scale-out Ethernet or InfiniBand depending on shuffle cost | object store, parquet/lakehouse, metadata acceleration |

## Implications For RFC99/SUN99/FMT2

For this lab infrastructure, the practical translation is:

- keep management and storage fabrics separate
- treat RoCE-v2 as a controlled storage class, not a general VLAN decoration
- use NFSv3 as bootstrap compatibility, but move durable identity-aware home
  directories toward NFSv4 with FreeIPA UID/GID consistency
- add NFS-RDMA, iSER, and NVMe-RDMA only after link, queue, and telemetry gates
  are enforced
- keep GPU/LLM service roles independent from storage-path roles so accelerator
  scheduling does not depend on fragile mount behavior

## Open Research Tasks

- Pull exact TOP500/Green500/HPCG records into a local CSV cache for repeatable
  comparison.
- Add a workload taxonomy for LLM training, RAG inference, scientific
  simulation, and storage-heavy analytics.
- Map local hardware inventory to the matrix: X12AGAIN, Hasslehoff, K10,
  GPU servers, QNAP/archive, and future FMT2 hosts.
- Produce a scored design table with cost, operational risk, fabric complexity,
  power/cooling, and expected workload fit.
