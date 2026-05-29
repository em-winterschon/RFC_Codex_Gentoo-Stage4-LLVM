# RDMA Promotion Readiness

`docs/workflows/rdma-fabric-promotion-readiness.yml` is the unified gate for
Issue #117 (`RDMA-002`), Issue #111 (`RDMA-003`), and Issue #130 (`FMT2-007`).

Issue #117 is closeable after this gate merges because the host RDMA storage
client baseline is defined: NFSv3 over TCP remains default, NFSv4.2 requires
centralized AAA and UID/GID consistency, NFS-RDMA is opt-in, and multipath tools
are present for block-storage paths such as iSCSI, FC, and NVMe-oF.

Issues #111 and #130 remain live-gated. Production RDMA admission is blocked
until the selected OFED/DOCA path, Arista/R630 fabric state, pairwise RDMA smoke,
storage protocol pilots, one-path-failure, and reboot-conformance evidence are
captured.

## Validator

Run:

```bash
scripts/validate-rdma-promotion-readiness.py \
  docs/workflows/rdma-fabric-promotion-readiness.yml
```

The default validator mode checks schema and safety invariants and emits JSON.
Use `--enforce-production-ready` in live promotion pipelines. That mode exits
with status `2` while `production_admission_state` remains blocked.

## Production Blockers

Current blockers are explicit and intentional:

- Vendor OFED/DOCA is not installed and `ofed_info -s` is not reporting an
  accepted driver line.
- RDMA userspace/perftest tooling is not installed everywhere required.
- Arista lossless QoS profile needs approved MTU, PFC, ECN, WRED, DSCP, and PCP
  mapping.
- Pairwise RDMA smoke has not run.
- NFS-RDMA, NVMe-RDMA, and iSER pilots have not run.
- One-path-failure and reboot-conformance tests have not run.
- `pri` ConnectX enumeration remains unresolved.
- `sec` placeholder ConnectX MACs remain unresolved.

## Safety Rules

- Do not enable ConnectX LACP before pairwise RDMA and one-path-failure pass.
- Do not admit in-kernel `mlx5` as production RDMA without a vendor-driver
  decision.
- Do not enable NFS-RDMA or NVMe-RDMA before lossless class validation.
- Do not mutate Arista without pre-change snapshot and rollback commands.
- Keep RDMA out of OpenStack and SLURM scheduling until production admission
  passes.
