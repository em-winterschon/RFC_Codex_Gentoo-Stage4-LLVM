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

The current playbook-based Ansible snapshot was captured on `2026-05-02T02:03:00Z` and is
stored privately under:

```text
/root/operator-private/local-network/hasslehoff-20260501-190301
```

Summary:

- FQDN: `cls0-rfc99-hasslehoff-099009.rfc1918.host`
- OS: Debian `12.12`
- Kernel: `6.8.12-14-pve`
- CPU: `8` vCPUs / `4` cores reported to Ansible
- Memory: `64121` MiB
- Management path: `bond0` over `eno1` + `eno2`, bridged through `vmbr0`
- RoCE-v2 reserved ports: `enp2s0f0np0`, `enp2s0f1np1`
- CCR2004-PCIe card: removed on `2026-05-05` to free the CPU x8/x16 slot
- QLogic QL41232HOCU CNA ports: `enp4s0f0`, `enp4s0f1`
- NVIDIA Quadro K1200: PCIe `0000:01:00.0`, audio function `0000:01:00.1`

## 2026-05-05 PCIe Maintenance Update

Hasslehoff was shut down cleanly for PCIe maintenance. VMs `1062`, `1063`, and
`1089` were stopped before host halt and restarted after the hardware swap.

Installed hardware after maintenance:

| Device | PCIe Address | Linux Interface | Driver | Notes |
| --- | --- | --- | --- | --- |
| NVIDIA Quadro K1200 VGA | `0000:01:00.0` | n/a | `nouveau` observed before reboot policy application | Intended for workstation VM passthrough through `vfio-pci`. |
| NVIDIA Quadro K1200 audio | `0000:01:00.1` | n/a | n/a | Same IOMMU group as VGA function. |
| QLogic QL41232HOCU port 0 | `0000:04:00.0` | `enp4s0f0` | `qede` | Firmware `mfw 8.30.18.0`, PCIe `8GT/s x4`, link down until cabled. |
| QLogic QL41232HOCU port 1 | `0000:04:00.1` | `enp4s0f1` | `qede` | Firmware `mfw 8.30.18.0`, PCIe `8GT/s x4`, link down until cabled. |

The QLogic card is x8-capable but is installed in an x4 electrical slot, so
`8GT/s x4` is expected and is the slot limit. The removed MikroTik
CCR2004-1G-2XS-PCIe card is no longer present in PCI inventory.

Planned QLogic cabling:

| Hasslehoff Port | CRS309 Port | Bundle |
| --- | --- | --- |
| `enp4s0f0` | `sfp-sfpplus4` | `bond-hasslehoff-qlogic` |
| `enp4s0f1` | `sfp-sfpplus5` | `bond-hasslehoff-qlogic` |

Hasslehoff is now a member of the `gpu_compute` inventory group. The
`gpu_host_policy` role renders:

- `/etc/modprobe.d/blacklist-nouveau.conf`
- `/etc/default/grub.d/99-gpu-compute-blacklist.cfg`

Default blacklisted modules:

- `nouveau`
- `nvidiafb`
- `snd_hda_intel` on Hasslehoff only

The role does not reboot the host and does not run `update-grub` or
`update-initramfs` unless the corresponding explicit booleans are enabled.

Hasslehoff-specific passthrough policy binds both K1200 functions to
`vfio-pci` on next reboot:

- `10de:13bc`
- `10de:0fbc`

Live post-reboot validation showed both K1200 functions bound to `vfio-pci`
and available for Proxmox passthrough.

The QLogic CNA is now cabled to CRS309 `sfp-sfpplus4/5` as
`bond-hasslehoff-qlogic`. Hasslehoff runs host-side `bond-qlogic0` and
VLAN-aware bridge `vmbr-qlogic0`. The requested SR-IOV VF design is blocked by
hardware/firmware exposure: neither QLogic PCI function exposes
`sriov_totalvfs`, and `lspci` shows no SR-IOV capability.

## 2026-05-10 USB Serial Console Migration

RouterOS router/switch serial consoles were moved from X12AGAIN to Hasslehoff
through an interim generic VIA Labs USB hub. This removes another live
operational dependency from X12AGAIN before bare-metal reimage work.

The managed Coolgear `CG-4PU3MGD` hub remains the target state for per-port
power control, but it is blocked on a replacement power supply. The interim hub
has no per-port reset capability, so treat it as console connectivity only.

Hasslehoff USB topology:

| Component | USB Path | VID:PID | Notes |
| --- | --- | --- | --- |
| Generic hub USB2 root | `1-11` | `2109:2811` | Active interim serial hub. |
| Generic hub USB3 root | `2-2` | `2109:8110` | Companion SuperSpeed side. |
| Dual-RS232 internal hub | `1-11.2` | `1a40:0101` | Presents the CRS354/CRS309 FTDI ports. |

Validated console mappings:

| Device | Prompt | Stable Device | Current TTY | Baud |
| --- | --- | --- | --- | --- |
| CCR2004 gateway | `[admin@gw-rfc99-mkccr2004-16g] >` | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0` | `/dev/ttyUSB0` | `115200` |
| CRS354 distribution | `[admin@sw-mgmt-mkcrs354] >` | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3W-if00-port0` | `/dev/ttyUSB1` | `115200` |
| CRS309 spine | `[admin@sw-spine-crs309-rfc99] >` | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3X-if00-port0` | `/dev/ttyUSB2` | `115200` |

The `/dev/ttyUSB*` assignments are observed state only. Automation should use
the stable `/dev/serial/by-id` paths or future `/dev/rfc99-serial/*` udev
aliases from the dedicated serial gateway VM.

## Observed Proxmox VMs

| VMID | Name | Status | CPU | Memory MiB | Disk GiB | Tags |
| --- | --- | --- | --- | --- | --- | --- |
| `1001` | `gw-rfc99-vyos-routeprime` | stopped | `2` | `2048` | `0` | `network-appliance`, `router`, `vyos` |
| `1011` | `ctbsd-rfc99-jailerprime-099099` | stopped-retired | `4` | `16384` | `128` | `freebsd`, `jail-host`, `oci-bsd`; former NetBox FreeBSD jail host |
| `1012` | `eph-sun99-sourcebot-099229` | stopped | `4` | `16384` | `64` | `linux`, `rocky`, `sourcebot`, `ephemeral` |
| `1062` | `svc-netbox-stage4` | running | `4` | `16384` | `80` | `gentoo`, `stage4`, `netbox`; replacement NetBox VM |
| `1063` | `svc-identity-ipa01` | running | `4` | `12288` | `80` | `rocky`, `freeipa`, `radius`, `identity`; central RBAC/AAA candidate |
| `1094` | `vm-workstation-nscde-gpu01` | running | `8` | `24576` | `160` | `gentoo`, `stage4`, `workstation-nscde`, `gpu`; K1200 passthrough VM at `172.16.99.94` |

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

The FreeBSD jail path for NetBox is retired. Replacement work now targets
standalone Proxmox VM `1062`, `svc-netbox-stage4`, on `hasslehoff`.

Current replacement VM path:

- Management address: `172.16.99.62/24`
- Proxmox parent: `hasslehoff`
- Proxmox VMID: `1062`
- Base image: populated Stage4 Gentoo LLVM OpenRC QCOW image
- Disk: resized from the imported `24G` root image to `80G`
- Target NetBox release: `v4.5.9`
- Service profile: `vm-netbox-service`
- Deployment method: native source on Gentoo-managed PostgreSQL, Redis, nginx, pip, and virtualenv
- Essentials root: `/opt/netbox-essentials`
- Validated URL: `http://172.16.99.62/api/`
- Validated services: `postgresql-18`, `redis`, `netbox`, `netbox-rq`, `nginx`, `sshd`
- Proxmox recovery snapshot: `codex-netbox-stage4-live`
- Post-essentials snapshot: `codex-netbox-after-essential-import`
- Post-fabric-seed snapshot: `codex-netbox-after-fabric-seed`
- Post-structured-intake snapshot: `codex-netbox-after-intake-apply`

Operational note: NetBox is not packaged in the current Gentoo tree on this
image. The service profile therefore treats NetBox as a native-source
application layer on top of Gentoo-managed platform packages.

Completed deployment sequence:

1. Booted `svc-netbox-stage4` from the populated Stage4 image and assigned `172.16.99.62/24`.
2. Resized the imported root disk to `80G`.
3. Installed NetBox `v4.5.9` from upstream source into `/opt/netbox`.
4. Initialized Gentoo-managed PostgreSQL `18`, Redis, gunicorn, RQ worker, and nginx under OpenRC.
5. Generated local root-only NetBox application secret, API pepper, admin password, and bootstrap token files.
6. Ran migrations, collected static assets, and validated `/api/` from the VM and from the build host.
7. Installed NetBox essential operational integrations under `/opt/netbox-essentials`.
8. Started the essential device-type library import for APC, Arista, Cisco, CyberPower, Eaton, Juniper, MikroTik, and Opengear.
9. Seeded repo-safe local fabric objects into NetBox from `network_fabric.yml`.
10. Applied normalized structured intake from `inventory-intake/sites/local-rfc1918-lab.yml` and validated an idempotent second pass.

Next integration sequence:

1. Move the root-only NetBox secrets into Ansible Vault before codifying repeated deployment.
2. Add NetBox-backed inventory lookups to consume the seeded source of truth.
3. Add the next datacenter or cluster as a new structured intake file, validate
   it, dry-run it, then apply it.
4. Decide whether `netbox_server` remains native-source or becomes a Podman-backed service after the container-services stack is stable.

## Identity Controller Location

The first centralized RBAC/AAA controller is Proxmox VM `1063`,
`svc-identity-ipa01`, on `hasslehoff`.

Current controller path:

- Management address: `172.16.99.63/24`
- Proxmox parent: `hasslehoff`
- Proxmox VMID: `1063`
- Base image: Rocky 9 GenericCloud
- Disk: `80G`
- Hostname: `ipa01.rfc1918.host`
- Realm: `RFC1918.HOST`
- Domain: `rfc1918.host`
- Validated services: `ipa`, `dirsrv`, `krb5kdc`, `httpd`, `sssd`, `radiusd`
- RADIUS listeners: UDP `1812` and `1813`
- Recovery snapshot: `codex-freeipa-radius-live`
- Bootstrap scripts:
  - `scripts/proxmox-create-freeipa-rocky-vm.sh`
  - `scripts/bootstrap-freeipa-rocky.sh`
  - `scripts/configure-freeradius-freeipa.sh`

This is the pragmatic controller path until a repeatable native Gentoo FreeIPA
server package source exists.

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

Use the `svc_netbox_stage4` inventory host for the replacement service. The old
`netbox_jail` inventory target has been removed because VM `1011` is no longer
the intended service path.
