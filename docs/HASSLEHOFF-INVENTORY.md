# Hasslehoff Inventory

## Current State

Hasslehoff is now represented in the `local-network` inventory as a Proxmox
hypervisor:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/
  hosts.yml
  host_vars/hasslehoff.yml
  group_vars/all/network_fabric.yml
  group_vars/all/vault.yml
```

The encrypted vault stores Proxmox API token values and device bootstrap
credentials. Repo-safe topology and observed host state live in normal YAML.

## Observed Host Facts

The first playbook-based Ansible snapshot was captured on `2026-05-02T01:41:17Z` and is
stored privately under:

```text
/root/operator-private/local-network/hasslehoff-20260501-184118
```

Summary:

- FQDN: `cls0-rfc99-hasslehoff-099009.rfc1918.host`
- OS: Debian `12.12`
- Kernel: `6.8.12-14-pve`
- CPU: `8` vCPUs / `4` cores reported to Ansible
- Memory: `64121` MiB
- Management path: `bond0` over `eno1` + `eno2`, bridged through `vmbr0`
- RoCE-v2 reserved ports: `enp2s0f0np0`, `enp2s0f1np1`
- CCR2004 PCIe-facing ports observed on host: `enp1s0f0` through `enp1s0f3`

## Observed Proxmox VMs

| VMID | Name | Status | CPU | Memory MiB | Disk GiB | Tags |
| --- | --- | --- | --- | --- | --- | --- |
| `1001` | `gw-rfc99-vyos-routeprime` | stopped | `2` | `2048` | `0` | `network-appliance`, `router`, `vyos` |
| `1011` | `ctbsd-rfc99-jailerprime-099099` | stopped | `4` | `16384` | `128` | `freebsd`, `jail-host`, `oci-bsd`; parent VM for NetBox FreeBSD jail |
| `1012` | `eph-sun99-sourcebot-099229` | stopped | `4` | `16384` | `64` | `linux`, `rocky`, `sourcebot`, `ephemeral` |

## Observed Proxmox Cluster

The cluster reports as `prx-rfc99-prime` with two nodes:

| Node | IP | Status | Notes |
| --- | --- | --- | --- |
| `hasslehoff` | `172.16.99.9` | online | Local node; API and SSH validated. |
| `nanoprime` | `172.16.99.13` | offline | Visible in Proxmox cluster state; not yet added as a managed inventory target. |

The cluster currently reports `quorate=0`, which is expected for a two-node
cluster when one node is offline. Do not schedule new HA-sensitive VM changes
until quorum behavior is explicitly addressed.

## NetBox Location

NetBox is not a standalone Proxmox VM in the visible inventory. It runs inside a
FreeBSD jail hosted by VM `1011`, `ctbsd-rfc99-jailerprime-099099`, on
`hasslehoff`.

Discovered service path:

- NetBox jail/API endpoint: `https://172.16.99.62/`
- NetBox UI/API observed version: `3.6.9`
- Parent VM: `1011`, `ctbsd-rfc99-jailerprime-099099`
- API root is reachable without authentication at `/api/`
- `/api/status/` and write workflows require an API token

Next discovery sequence:

1. Add the NetBox API token to Ansible Vault as `vault_netbox_api_token`.
2. Enumerate FreeBSD jails from inside VM `1011` once SSH access is available.
3. Confirm the NetBox jail name and persistent jail configuration.
4. Enable read-only NetBox API snapshots.
5. Enable guarded NetBox write workflows only after token and object model review.

## Refresh Workflow

Run the inventory snapshot playbook through the vault wrapper:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/local-network-inventory.yml
```

By default, snapshots are written outside the repo under:

```text
/root/operator-private/local-network/
```

Set `LOCAL_NETWORK_SNAPSHOT_ROOT` to override that destination.

Validate the vaulted Proxmox API token with:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/proxmox-api-validate.yml
```

The API playbook marks token-bearing URI tasks `no_log: true` and emits only a
sanitized version and VM-count summary.

The current token is privilege-separated and requires an explicit token ACL for
inventory visibility:

```bash
pveum acl modify / --tokens 'root@pam!cdex-root-localnet' --roles PVEAuditor
```

Without that ACL, API authentication succeeds but VM inventory endpoints return
an empty list. With the ACL applied, `proxmox-api-validate.yml` reports Proxmox
`8.4.13` and `vm_count=3`.

Validate NetBox API root reachability with:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-api-validate.yml
```
