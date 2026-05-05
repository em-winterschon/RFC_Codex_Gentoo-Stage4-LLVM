# ITIL Change Control: Container Services Safe Move

## Document Control

- Change title: Safe move of container-services workload to Hasslehoff Stage4 VM
- Change type: Normal change until first successful execution, then standard change candidate
- Planned staging hostname: `svc-container-services-safe-move-01.rfc1918.host`
- Planned staging IP: `172.16.99.89/24`
- Planned Proxmox VMID: `1089`
- Planned VM sizing: `8` vCPU, `32 GiB` RAM, `80 GiB` disk
- Hypervisor: `hasslehoff`
- Source workload: local Path B QEMU `container-services` VM at `10.9.8.89`
- Validation model: SLO-style point-in-time service gates

## Purpose

Move the container-services workload onto Hasslehoff without disrupting the
currently running source VM. The staging VM receives only a management-network
address until the service layer validates. Production Path B addressing remains
owned by the source VM until cutover.

## Scope

Included:

- reserve a NetBox/IPAM tracked staging hostname and IP
- create a Stage4 VM from the current Hasslehoff Stage4 base image
- validate source service health before mutation
- provision or migrate container service definitions onto the staging VM
- validate target management and service listeners before any cutover
- document backout and validation evidence

Excluded:

- production DNS writes without explicit apply approval
- moving the `10.9.8.89` production service address before target validation
- deleting or stopping the source VM before post-move validation passes

## Risk Controls

- The staging VM uses `172.16.99.89/24`, not the live `10.9.8.89` service IP.
- The staging HAProxy wrapper must not claim the production `10.9.8.92/32`
  Elasticsearch VIP during validation.
- NetBox is updated before VM creation so IPAM is authoritative.
- VM creation uses the dry-run-first Proxmox helper and aborts on existing VMID.
- Stage4 images use OVMF/UEFI unless a specific image is verified as SeaBIOS
  bootable.
- The source QEMU VM remains the rollback target until the target has passed
  service checks.
- SLO probes validate availability, latency, and HTTP response correctness.

## Implementation Sequence

1. Confirm `172.16.99.89` is unused by ping, ARP, nmap, repo search, and NetBox.
2. Snapshot NetBox VM `1062` before inventory writes.
3. Apply `local-rfc1918-lab.yml` inventory intake to NetBox.
4. Dry-run DNS planning from NetBox and do not apply DNS writes.
5. Dry-run Proxmox VM creation for VMID `1089` with `VM_BIOS=ovmf`.
6. Create the VM stopped.
7. Start the VM and validate SSH management reachability.
8. Run pre-move SLO checks against the source workload.
9. Provision container-host and application service roles on the staging VM.
10. Run target-boot and post-move SLO checks against the staging VM.
11. Only after validation, plan the service-address cutover separately.

Runtime migration helper:

```bash
scripts/migrate-container-services-runtime.sh --dry-run
scripts/migrate-container-services-runtime.sh --apply --start-services
```

In default staging mode the helper copies the runtime layer but patches HAProxy
to bind `:9200` on the staging host instead of claiming `10.9.8.92/32`.

## Backout Plan

If NetBox intake causes incorrect metadata:

1. Revert the intake file commit.
2. Re-apply inventory intake with `netbox_inventory_update_existing=true`.
3. Restore NetBox VM snapshot `nb-pre-safe-move-20260503` if API state is not
   cleanly correctable.

If Proxmox VM creation fails:

1. Keep source VM running.
2. Run `qm stop 1089 || true` on Hasslehoff.
3. Run `qm destroy 1089 --purge 1` on Hasslehoff if the partial VM exists.
4. Remove or mark the NetBox staging device as failed/planned.

If staging service validation fails:

1. Do not cut over any service IP or DNS record.
2. Keep `10.9.8.89` source VM active.
3. Preserve failed VM logs and runbooks for corrective action.
4. Destroy and recreate VMID `1089` only after collecting the failure evidence.

## SLO Validation

The validation manifest is:

`gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/service-slo-definitions/container-services-safe-move.yml`

Run from the Ansible tree:

```bash
ansible-playbook playbooks/service-slo-validate.yml -e slo_phase=pre-move
ansible-playbook playbooks/service-slo-validate.yml -e slo_phase=target-boot
ansible-playbook playbooks/service-slo-validate.yml -e slo_phase=post-move
ansible-playbook playbooks/service-slo-validate.yml -e slo_phase=post-move-elasticsearch-dependency
```

Current execution evidence:

- Pre-move source SLO passed `4/4`.
- Target boot SLO passed `1/1`.
- Post-move core SLO passed `8/8` with source guard checks still passing and
  target SSH, HAProxy HTTP, nginx HTTP, and rsyslog TCP reachable.
- The separate Elasticsearch dependency phase fails with HAProxy `503` because
  the staging VM on `172.16.99.89` cannot reach the existing
  `10.9.8.91` / `10.9.8.92` Elasticsearch network path.

The SLO model follows the practical IBM framing: use measurable SLIs, define an
explicit objective, keep the checks understandable, and alert or block change
progression only when service symptoms indicate objective failure.

The GitLab observability examples under
`/opt/repos/remote/observability/obs-gitlab-com.shallow-master` reinforce the
same operating pattern: prioritize service availability, incident response
duration, corrective action follow-through, and saturation/capacity signals
over noisy internal-only checks.
