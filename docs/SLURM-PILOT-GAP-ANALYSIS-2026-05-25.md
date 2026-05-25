# SLURM Pilot Gap Analysis 2026-05-25

## Scope

This is a repo-side and resolver-side dry run for the RFC99 SLURM pilot while
the M70 canary remains the active boot-path blast target.

No live SLURM apply, MUNGE key creation, MariaDB mutation, or NetBox API write
was performed in this pass.

## Current Intent

| Role | Inventory name | FQDN | Address | Runtime services |
| --- | --- | --- | --- | --- |
| Controller | `sched_sun99_slurmctl_099071` | `sched-sun99-slurmctl-099071.rfc1918.host` | `172.16.99.71` | `munge`, `mariadb`, `slurmdbd`, `slurmctld` |
| First worker | `slurm_worker_node01` | `sched-sun99-slurmwkr-099072.rfc1918.host` | `172.16.99.72` | `munge`, `slurmd` |

The controller remains independent of X12AGAIN. X12AGAIN is a future worker
only after its workstation, hypervisor, RDMA, and storage validation passes.

## Resolver Evidence

System resolver checks from the primary M70:

```text
getent ahostsv4 sched-sun99-slurmctl-099071.rfc1918.host
172.16.99.71    STREAM sched-sun99-slurmctl-099071.rfc1918.host

getent ahostsv4 sched-sun99-slurmctl.rfc1918.host
172.16.99.71    STREAM sched-sun99-slurmctl-099071.rfc1918.host

getent ahostsv4 sched-sun99-slurmwkr-099072.rfc1918.host
172.16.99.72    STREAM sched-sun99-slurmwkr-099072.rfc1918.host
```

This proves the local resolver path currently returns the expected A/CNAME
answers. It does not by itself prove Hetzner zone state or NetBox DNS sync
freshness.

## NetBox Intake Dry Run

Command:

```bash
python3 scripts/netbox_apply_inventory_intake.py \
  --format json \
  --device sched_sun99_slurmctl_099071 \
  --device slurm_worker_node01 \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml
```

Dry-run output included these planned objects:

```text
dcim/device-roles:slurm-controller
dcim/devices:sched_sun99_slurmctl_099071
dcim/interfaces:sched_sun99_slurmctl_099071:eth0
ipam/ip-addresses:172.16.99.71/24
dcim/device-roles:slurm-worker
dcim/devices:slurm_worker_node01
dcim/interfaces:slurm_worker_node01:eth0
ipam/ip-addresses:172.16.99.72/24
```

The dry run also carries the `local-stage4-services` cluster membership entry
that includes the controller and first worker. This is sufficient for a
preflight plan, but the live NetBox reconciliation still needs an API-backed
read or apply pass before runtime mutation.

## Service Modeling

Inventory intake already models service VIP/listener intent:

- `sched-sun99-slurmctl`
  - `172.16.99.71`
  - TCP `6817` for `slurmctld`
  - TCP `6819` for `slurmdbd`
- `sched-sun99-slurmwkr01`
  - `172.16.99.72`
  - TCP `6818` for `slurmd`

MUNGE is intentionally not exposed as a network listener. MariaDB for the pilot
is local to the controller unless a later design splits accounting storage.

## Open Gaps

1. Live NetBox API read/apply has not been rerun in this pass.
2. Hetzner DNS zone audit has not been rerun in this pass.
3. Vault values must be confirmed before live apply:
   - `vault_slurm_munge_key_b64`
   - `vault_slurmdbd_storage_password`
4. Prometheus/VictoriaMetrics/Grafana integration targets are documented but
   still need runtime scrape/dashboard validation after the controller and
   worker are online.
5. Rsyslog and Elasticsearch scheduler log paths are documented but still need
   runtime log-flow validation.
6. M70 canary must not be treated as a stable SLURM worker until its SATADOM
   EFI carrier boot path is complete and accepted.
7. PR `#144` cannot be blindly merged with the current
   `codex/slurm-pilot-control-plane` base; the integration gate is documented
   in `docs/OVERNIGHT-EXECUTION-2026-05-25.md`.

## Allowed Next Steps

1. Run live NetBox read-only reconciliation for the two SLURM VM records.
2. Run Hetzner DNS audit for the controller and worker A/CNAME records.
3. Confirm vault secret presence without printing secret values.
4. Run the SLURM live apply playbook only with
   `slurm_pilot_live_apply_required=true` and only after the controller and
   worker VM targets are confirmed reachable.
5. Keep the M70 canary out of SLURM worker admission until local boot durability
   is complete.
