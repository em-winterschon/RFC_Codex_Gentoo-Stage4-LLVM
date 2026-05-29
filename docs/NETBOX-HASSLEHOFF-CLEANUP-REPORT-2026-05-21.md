# NetBox Hasslehoff Cleanup Report

Generated from live NetBox and Hasslehoff reconciliation evidence on
2026-05-21. This is a review report only. No destructive NetBox cleanup actions
were applied.

## Current Clean State

The active Hasslehoff Proxmox cluster is modeled as `prx-rfc99-prime`.

Validated state after reconciliation:

- `15` live QEMU VMs on Hasslehoff are present in NetBox as virtualization VMs.
- `0` LXC containers are present on Hasslehoff.
- VM interfaces, MACs, configured IPs, and expected service records were created
  for the live VM inventory.
- Live VLAN tags `1098` and `1099` are present in NetBox.
- `hasslehoff` and `nanoprime` are assigned to `prx-rfc99-prime`.
- The dry-run reconciler returned no conflicts, creates, or updates after the
  final pass.

Final rollback marker for the broader reconciliation pass:

- NetBox VM `1062` snapshot: `nb-post-hhof-final-05211351`

ATS-specific rollback markers:

- Pre: `nb-pre-ats-05211357`
- Post: `nb-post-ats-05211400`

## Stale VM-As-DCIM Placeholder Candidates

These DCIM device records overlap with VMs now represented in NetBox
virtualization. Most have no primary IP after the IP assignment migration. They
should be reviewed before retirement because some may still carry comments,
historical context, power mappings, or future desired state.

| DCIM device | Device status | Device role | Primary IP | Interfaces | Matching VM | VM status | Recommended next action |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| `ctbsd_rfc99_jailerprime_099099` | `offline` | `retired-freebsd-jail-host` | none | 0 | `ctbsd-rfc99-jailerprime-099099` | `offline` | Likely retire or decommission after confirming no historical metadata is still needed. |
| `svc_netbox_stage4` | `active` | `ipam-dcim` | none | 0 | `svc-netbox-stage4` | `active` | Treat as duplicate placeholder; migrate any remaining comments/context to the VM before changing status. |
| `svc_identity_ipa01` | `active` | `identity-controller` | none | 0 | `svc-identity-ipa01` | `active` | Treat as duplicate placeholder; migrate context to VM before changing status. |
| `obs_sun99_prometheus_099064` | `planned` | `observability-prometheus` | none | 1 | `obs-sun99-prometheus-099064` | `active` | Likely retire placeholder after checking interface notes. |
| `obs_sun99_vmetrics_099065` | `planned` | `observability-victoriametrics` | none | 1 | `obs-sun99-vmetrics-099065` | `active` | Likely retire placeholder after checking interface notes. |
| `obs_sun99_grafana_099066` | `planned` | `observability-grafana` | none | 1 | `obs-sun99-grafana-099066` | `active` | Likely retire placeholder after checking interface notes. |
| `sched_sun99_slurmctl_099071` | `planned` | `slurm-controller` | none | 1 | `sched-sun99-slurmctl-099071` | `active` | Likely retire placeholder after checking Slurm roadmap dependencies. |
| `slurm_worker_node01` | `planned` | `slurm-worker` | none | 1 | `sched-sun99-slurmwkr-099072` | `active` | Rename/migrate context if this was intended as a generic future worker; otherwise retire placeholder. |
| `svc_container_services_safe_move_01` | `planned` | `container-services-staging` | none | 0 | `svc-container-services-safe-move-01` | `active` | Treat as duplicate placeholder; migrate context to VM before changing status. |

Do not delete these records until a human confirms they have no useful comments,
cable records, change-history value, or future desired-state purpose.

## Empty Cluster Candidate

| Cluster | Type | VM count | Device count | Status | Recommended next action |
| --- | --- | ---: | ---: | --- | --- |
| `hasslehoff-proxmox` | `proxmox` | 0 | 0 | `active` | Retire or delete only after confirming no external automation still references the old cluster name. |

`prx-rfc99-prime` is the active modeled cluster and currently owns the live VM
and host membership.

## Console Modeling Gaps

NetBox currently has:

- `2` console-port records:
  - `ats-rfc99-corepower-p10-099242:Serial`
  - `gw_rfc99_mkcrs309:serial0`
- `0` console-server-port records.
- No NetBox cables for the active M70-attached RouterOS console paths.

Known M70 serial paths are documented in
[`M70-SERIAL-CONSOLE-MAP.md`](M70-SERIAL-CONSOLE-MAP.md). The safe additive
NetBox model would be:

1. Add console-server ports on `admin_sun99_forge_099070` for:
   - `rfc99-serial/ccr2004-gateway`
   - `rfc99-serial/crs354-distribution`
   - `rfc99-serial/crs309-spine`
2. Add missing console ports on:
   - `gw_rfc99_mkccr2004_16g`
   - `sw_mgmt_mkcrs354`
   - `sw_spine_crs309_rfc99`
3. Cable the M70 console-server ports to those device console ports.
4. Add ATS/PDU/UPS console cables only after the RJ12 adapters are installed and
   the FTDI port identity is validated.

## Power Device Follow-Up

| Device | Role | Model | Primary IP | Serial | Follow-up |
| --- | --- | --- | --- | --- | --- |
| `pdu_rfc99_corectrl_ap7901` | `power-distribution-unit` | `AP7901` | `172.16.99.241/24` | blank | Fill serial from faceplate or authenticated NMC query. |
| `ats-rfc99-corepower-p10-099242` | `automatic-transfer-switch` | `AP4450A` | `172.16.99.242/24` | blank | Verify exact model/serial through faceplate or corrected NMC credential. |
| `ups_sun99_cyberpower_cp1500` | `ups` | `CP1500PFCRM2U` | none | `BHWNZ7000431` | USB/NUT inventory is present; add network/serial console only if a management path is installed. |

No power-control actions, SNMP writes, RADIUS changes, or credential changes were
performed while generating this report.

## Apply Plan For A Later Maintenance Window

1. Export or snapshot NetBox VM `1062`.
2. Confirm stale placeholder records with the operator.
3. Migrate any useful comments or custom fields from placeholders to VM records.
4. Change confirmed placeholders to `decommissioning` or delete them according to
   the site's NetBox lifecycle convention.
5. Retire or delete `hasslehoff-proxmox` after checking automation references.
6. Add console-server-port/cable modeling for the three active M70 RouterOS
   console paths.
7. Add ATS/PDU/UPS console modeling after physical RJ12 adapter installation.
