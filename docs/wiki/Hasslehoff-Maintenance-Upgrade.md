# Hasslehoff Maintenance Upgrade Plan

This plan keeps Hasslehoff on Proxmox VE `8.x` while applying normal PVE 8 /
Debian 12 package maintenance. Do not move this host to Proxmox VE 9 until the
mixed cluster state and `nanoprime` compatibility are explicitly resolved.

## Current Upgrade Lane

- Current host: Proxmox VE `8.4.13`
- Current kernel observed: `6.8.12-14-pve`
- Current OS lane: Debian `bookworm`
- Avoid for now: Debian `trixie` / Proxmox VE `9`

## Ansible Role

The `proxmox_host_upgrade` role is plan-only by default:

```yaml
proxmox_host_upgrade_apply: false
```

It validates the PVE major lane, refuses PVE9/Trixie-like apt sources, and
prints the planned ZFS snapshots and package actions. It only mutates the host
when `proxmox_host_upgrade_apply: true`.

Plan command:

```bash
scripts/with-ansible-vault-env.sh bash -lc '
  cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible &&
  ANSIBLE_STDOUT_CALLBACK=default ansible-playbook \
    -i inventories/local-network/hosts.yml \
    --limit hasslehoff \
    playbooks/proxmox-host-upgrade.yml
'
```

Apply command for a maintenance window:

```bash
scripts/with-ansible-vault-env.sh bash -lc '
  cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible &&
  ANSIBLE_STDOUT_CALLBACK=default ansible-playbook \
    -i inventories/local-network/hosts.yml \
    --limit hasslehoff \
    -e proxmox_host_upgrade_apply=true \
    -e proxmox_host_upgrade_reboot=false \
    playbooks/proxmox-host-upgrade.yml
'
```

Run the reboot as a separate controlled step after VM shutdown.

## ZFS Snapshot Sequence

The role snapshots the active root dataset recursively:

```text
rpool/ROOT/pve-1@pve8-maint-pre-<timestamp>
rpool/ROOT/pve-1@pve8-maint-post-<timestamp>
```

The pre snapshot is created before `apt update` / `apt dist-upgrade`. The post
snapshot is created after package upgrade and `proxmox-boot-tool refresh`, but
before any optional reboot.

## Backout Notes

If the host fails after an upgrade, prefer the IPMI/Redfish console first. The
rollback path should be a deliberate boot environment or ZFS rollback action,
not an automatic role action. The repo intentionally does not automate ZFS root
rollback because an incorrect rollback can destroy later VM or configuration
state.

## OFED/DOCA Note

The `nvidia_doca_ofed` role is also gated. NVIDIA DOCA/OFED package selection
is version and OS specific, and Hasslehoff runs a Proxmox kernel rather than a
stock Debian kernel. The role requires an explicit repo package URL or local
repo `.deb`, matching kernel headers, and an explicit custom-kernel
acknowledgement before it will install anything.

The role now performs a read-only PCI detection pass with `lspci -Dnn` before
any apply path. The expected device classes are BlueField-2, ConnectX-4,
ConnectX-5, ConnectX-6, and ConnectX-7 family NVIDIA/Mellanox adapters under
PCI vendor `15b3`. If no supported device is detected, the install path is
refused unless
`nvidia_doca_ofed_skip_device_detection` is deliberately set for a documented
lab exception. The rendered plan also lists the required kernel modules
(`mlx5_core`, `mlx5_ib`, `ib_uverbs`, `rdma_cm`) and the first-pass RoCE
validation commands (`ofed_info -s`, `ibv_devinfo`, `rdma link show`,
`rdma resource show`). For ConnectX hosts admitted to the RDMA fabric,
in-kernel `mlx5_core` without `ofed_info` is an interim discovery state, not the
steady-state driver policy.
