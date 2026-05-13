# SLURM Pilot Bringup

## Goal

Bring the first RFC99 SLURM control plane online today without blocking on
X12AGAIN reimage. The pilot creates a controller at
`sched-sun99-slurmctl-099071.rfc1918.host` (`172.16.99.71`) and validates one
first worker before any wider scheduler rollout.

## Principle

Do not block SLURM on X12AGAIN reimage.

X12AGAIN is a future high-value worker, workstation, Xen host, BlueField2
RDMA/NVMe-oF lab host, and Project Coherent Flash scale-model host. It is not a
required dependency for the first SLURM controller. The controller must be
usable while X12AGAIN is offline, being reimaged, or being validated.

## Initial Topology

| Role | Hostname | Address | Notes |
| --- | --- | --- | --- |
| Controller | `sched-sun99-slurmctl-099071.rfc1918.host` | `172.16.99.71` | Runs `slurmctld`, local `slurmdbd`, MUNGE, and MariaDB for the pilot. |
| First worker | `slurm-worker-node` profile target | NetBox assigned | Disposable VM or K10 after E2ET pass. |
| Future worker | X12AGAIN | `172.16.99.108` after install | Add only after workstation+hypervisor+RDMA E2ET passes. |

## Partitions

- `build`: Portage, binpkg, rootfs, distcc, and artifact promotion jobs.
- `validation`: E2ET, netboot, service validator, and conformance jobs.
- `gpu-test`: GPU display/compute validation after host-specific GPU evidence.
- `rdma-test`: RoCE-v2, NFS-RDMA, NVMe-oF, and iSER validation after OFED/DOCA
  and fabric checks pass.

The `rdma-test` partition remains drained until live evidence exists. Static
inventory alone is not enough to publish RDMA-capable features.

## Required Gates

### 1. DNS And NetBox

- Create an A record for `sched-sun99-slurmctl-099071.rfc1918.host` at
  `172.16.99.71`.
- Create or validate a CNAME for `sched-sun99-slurmctl.rfc1918.host`.
- Model the controller VM in NetBox with management IP, service role, platform,
  virtual machine metadata, and owner.
- Model the first worker as a scheduler node with management IP, service IP if
  any, power metadata when available, and feature intent.

### 2. Vaulted Secrets

- MUNGE key material is delivered only through vault or approved first-boot
  secret delivery.
- `slurmdbd` storage password is stored as `vault_slurmdbd_storage_password`.
- No MUNGE key, MariaDB password, or Kerberos material is committed to the repo.

### 3. Runtime Services

Controller runtime services:

- `munge`
- `mariadb`
- `slurmdbd`
- `slurmctld`

Worker runtime services:

- `munge`
- `slurmd`

### 4. Observability

The pilot is not accepted until telemetry paths exist for:

- Prometheus scrape target for the controller and first worker.
- VictoriaMetrics ingestion through Prometheus remote-write or current scrape
  pipeline.
- Grafana dashboard stub or dashboard import issue for scheduler health.
- rsyslog routing for `slurmctld`, `slurmdbd`, and `slurmd` logs.
- Elasticsearch full-text search path for scheduler logs.

## Smoke Tests

Run these after controller and first worker are online:

```bash
sinfo
scontrol show nodes
srun hostname
sbatch --wrap='hostname; date -u'
```

Expected result:

- `sinfo` lists the pilot partitions.
- `scontrol show nodes` lists the first worker.
- `srun hostname` returns the worker hostname.
- The wrapped `sbatch` job reaches `COMPLETED`.

## Project Coherent Flash Gate

Project Coherent Flash scale modeling starts after the pilot controller can run
repeatable jobs. The initial model is simulation-only:

- KV/prefix-cache service model.
- Object/model tier model.
- RAG/vector tier model.
- Synthetic RDMA/NVMe-oF/NFS probes.
- BlueField2/DPU boundary model on X12AGAIN after reimage.

The first Project Coherent Flash milestone is a job-submitted simulation bundle,
not production storage implementation.

## Backout

If the pilot destabilizes DNS, routing, or VM host resources:

1. Stop `slurmctld`, `slurmdbd`, `slurmd`, `munge`, and `mariadb` on pilot
   nodes.
2. Remove `sched-sun99-slurmctl-099071.rfc1918.host` from active DNS if it
   points at a failed host.
3. Mark the controller and first worker `offline` in NetBox.
4. Preserve `/etc/slurm`, `/var/log/slurm`, `/var/lib/slurm`, and MariaDB logs
   for forensic review.
5. Keep X12AGAIN reimage blocked only if it became a dependency during the
   failed pilot; otherwise continue X12AGAIN prep independently.

## Completion Criteria

- DNS resolves controller A/CNAME records.
- NetBox has controller and first worker records.
- Vault has MUNGE and `slurmdbd` secret entries.
- Controller starts `munge`, `mariadb`, `slurmdbd`, and `slurmctld`.
- First worker starts `munge` and `slurmd`.
- `sinfo`, `scontrol show nodes`, `srun hostname`, and one wrapped `sbatch`
  job pass.
- Prometheus, VictoriaMetrics, Grafana, rsyslog, and Elasticsearch have defined
  scheduler integration targets.
