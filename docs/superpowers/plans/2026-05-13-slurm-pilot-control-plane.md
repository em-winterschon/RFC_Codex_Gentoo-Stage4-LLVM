# SLURM Pilot Control Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the first RFC99 SLURM pilot online at `sched-sun99-slurmctl-099071.rfc1918.host` (`172.16.99.71`) with one validated first worker, then expand to physical M70 worker `sched-sun99-slurmwkr-099073.rfc1918.host` (`172.16.99.73`) after inventory evidence is provided.

**Architecture:** Deploy a small non-production SLURM controller VM with local MUNGE, MariaDB, `slurmdbd`, and `slurmctld`, then attach one disposable worker using the existing `slurm-worker-node` profile. The next gainful expansion is a second physical M70 as a real worker, not nested workers inside the current Forge M70. X12AGAIN remains out of the critical path until it is reimaged and passes workstation+hypervisor+RDMA E2ET.

**Tech Stack:** Gentoo/OpenRC Stage4 profiles, Ansible role `slurm_cluster`, MUNGE, MariaDB, SLURM, NetBox, Hetzner DNS automation, Prometheus, VictoriaMetrics, Grafana, rsyslog, Elasticsearch.

---

### Task 1: Repository Readiness Gates

**Files:**
- Create: `tests/shell/test_slurm_pilot_readiness.sh`
- Modify: `tests/shell/run-tests.sh`
- Create: `docs/SLURM-PILOT-BRINGUP.md`
- Create: `docs/wiki/SLURM-Pilot-Bringup.md`
- Create: `docs/workflows/stage5-slurm-pilot-bringup.json`

- [ ] **Step 1: Write the failing readiness test**

```bash
bash tests/shell/test_slurm_pilot_readiness.sh
```

Expected before implementation: FAIL because the readiness docs and workflow
manifest do not exist.

- [ ] **Step 2: Add readiness documentation**

Create `docs/SLURM-PILOT-BRINGUP.md` and
`docs/wiki/SLURM-Pilot-Bringup.md` with the controller address, first-worker
gates, MUNGE/`slurmdbd` vault requirements, DNS/NetBox requirements,
observability requirements, smoke tests, physical M70 expansion target
`sched-sun99-slurmwkr-099073` / `172.16.99.73`, Project Coherent Flash gate,
and backout plan.

- [ ] **Step 3: Add workflow manifest**

Create `docs/workflows/stage5-slurm-pilot-bringup.json` with these stages:

```text
preflight-no-x12again-dependency
dns-netbox-preflight
vault-secret-preflight
controller-profile-render
first-worker-profile-render
observability-readiness
slurm-runtime-smoke
project-coherent-flash-model-gate
```

- [ ] **Step 4: Verify readiness test**

Run:

```bash
bash tests/shell/test_slurm_pilot_readiness.sh
```

Expected: PASS.

### Task 2: Controller And Worker Live Gate

**Files:**
- Existing: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-slurm-controller.yml`
- Existing: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/slurm-worker-node.yml`
- Existing: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/slurm_cluster/`

- [ ] **Step 1: Confirm DNS/IPAM target**

Run:

```bash
dig +short sched-sun99-slurmctl-099071.rfc1918.host
dig +short sched-sun99-slurmctl.rfc1918.host
```

Expected after DNS automation: `172.16.99.71` resolves for the A record and the
CNAME target resolves to the same host.

- [ ] **Step 2: Confirm vaulted secrets**

Run an Ansible vault lookup or encrypted-vars inspection that confirms:

```text
vault_slurmdbd_storage_password
vault_slurm_munge_key
```

Expected: both exist outside plaintext repo files.

- [ ] **Step 3: Render controller profile**

Run from the Ansible root:

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/local-network/hosts.yml \
  --limit sched_sun99_slurmctl_099071 \
  --sequence target-integration \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/sched_sun99_slurmctl_099071.target-integration.jsonl
```

Expected: `slurm.conf`, `slurmdbd.conf`, `cgroup.conf`, and OpenRC action
service intent render successfully.

- [ ] **Step 4: Render first worker profile**

Run from the Ansible root:

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/local-network/hosts.yml \
  --limit slurm_worker_node01 \
  --sequence target-integration \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/slurm_worker_node01.target-integration.jsonl
```

Expected: worker profile renders `slurmd` action service intent and no
controller-only `slurmdbd` service.

### Task 3: Runtime Validation

**Files:**
- Runtime target: `sched-sun99-slurmctl-099071.rfc1918.host`

- [ ] **Step 1: Validate controller services**

Run on the controller:

```bash
rc-service munge status
rc-service mariadb status
rc-service slurmdbd status
rc-service slurmctld status
```

Expected: all return running status.

- [ ] **Step 2: Validate worker service**

Run on the first worker:

```bash
rc-service munge status
rc-service slurmd status
```

Expected: both return running status.

- [ ] **Step 3: Validate SLURM job path**

Run from the controller:

```bash
sinfo
scontrol show nodes
srun hostname
sbatch --wrap='hostname; date -u'
```

Expected: partitions visible, first worker visible, `srun hostname` returns a
worker hostname, and the wrapped `sbatch` job reaches `COMPLETED`.

### Task 4: Observability And Project Coherent Flash Handoff

**Files:**
- Existing: `docs/SLURM-PILOT-BRINGUP.md`
- Existing: `docs/HPC-WORKLOAD-SCHEDULER-PLAN.md`
- Reference: `/opt/RFC_Project-Coherent-Storage/RFC_Proj-Coherent-Storage-ADRs.2026-Q2.v1/README.md`

- [ ] **Step 1: Validate observability targets**

Confirm scheduler integration targets exist for Prometheus, VictoriaMetrics,
Grafana, rsyslog, and Elasticsearch.

- [ ] **Step 2: Submit Project Coherent Flash modeling gate**

Submit a scheduler placeholder job that records the intended simulation lanes:

```bash
sbatch --job-name=coherent-flash-model-gate --wrap='printf "%s\n" "KV prefix cache" "object model tier" "RAG vector tier" "BlueField2 DPU boundary"'
```

Expected: job completes and its output names the simulation lanes. This is a
modeling gate only; it does not implement production storage.

### Task 5: Physical M70 Worker Expansion

**Files:**
- Existing: `docs/SLURM-PILOT-BRINGUP.md`
- Existing: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml`
- Existing: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml`

- [ ] **Step 1: Collect physical worker inputs**

Record the second M70 values before inventory mutation:

```text
hostname: sched-sun99-slurmwkr-099073.rfc1918.host
address: 172.16.99.73
profile: slurm-worker-node
required: primary MAC, switch name, switch port, PDU name, PDU outlet, serial path if connected
```

Expected: no inventory change occurs until the physical identity and power path
are known.

- [ ] **Step 2: Add the physical worker to inventory**

Add the host under `slurm_workers` with `stage5_profile: slurm-worker-node`,
`slurm_cluster_role: physical-worker`, `slurm_node_name:
sched-sun99-slurmwkr-099073`, `slurm_node_cpus: 8`, `slurm_node_features:
[build, validation, qat]`, and the operator-provided MAC/switch/PDU metadata.

Expected: `bash tests/shell/test_slurm_pilot_readiness.sh` passes after the
inventory-intake mirror is updated.

- [ ] **Step 3: Join and validate**

Run the live apply playbook against the new worker, then validate:

```bash
scontrol show node sched-sun99-slurmwkr-099073
srun --nodes=1 --nodelist=sched-sun99-slurmwkr-099073 hostname
```

Expected: node is visible, not drained, and `srun` returns
`sched-sun99-slurmwkr-099073`.
