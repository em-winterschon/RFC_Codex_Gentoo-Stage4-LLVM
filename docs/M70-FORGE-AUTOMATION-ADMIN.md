# M70 Forge Automation Admin

## Purpose

The first M70 node becomes the replacement automation-admin host before
X12AGAIN/Prinzessin is reimaged. Its job is to run Codex/Forge workflows,
Ansible, GitHub CLI, vault tooling, infrastructure validation, and X12AGAIN SoL
access from a stable installed system instead of the long-lived X12AGAIN live
environment.

## Reserved Identity

| Field | Value |
| --- | --- |
| Inventory key | `admin_sun99_forge_099070` |
| FQDN | `admin-sun99-forge-099070.rfc1918.host` |
| Alias | `admin-sun99-forge.rfc1918.host` |
| Address | `172.16.99.70/24` |
| Gateway | `172.16.99.1` |
| Primary NIC | `eth0` |
| Primary MAC | `00:07:32:78:65:C6` |
| Switch port | `sw_mgmt_css326 ge14` |
| PDU outlet | `pdu-rfc99-corectrl-099241 outlet 4` |
| Serial console | Hasslehoff `/dev/ttyUSB3` |
| Stage5 profile | `metal-forge-automation-admin` |

## Provisioning Plan

The M70 is tracked as a UEFI-only `pxe-to-ipxe` install target. RouterOS desired
state reserves a static DHCP lease for `172.16.99.70` and sends boot file
`m70-forge-ipxe.efi` from the SUN99 netboot publisher at `172.16.99.88`.

The current first-stage binary is the M70-specific
`/opt/gentoo-netboot/path-b/m70-forge-ipxe-172.16.99.88-ipxe.efi` artifact,
published as `m70-forge-ipxe.efi`.

Live validation on 2026-05-13 found that the firmware can put `Network` first
in the fixed UEFI boot order, but did not expose a usable UEFI PXE NIC entry.
The operational workaround is a local SATADOM ESP chainloader: the original
BSDRP `BOOTX64.EFI` was backed up on the ESP, then replaced with the
M70-specific iPXE binary. That path successfully DHCPs, chains
`hosts/admin-sun99-forge-099070.ipxe`, downloads the Gentoo kernel/initramfs and
`rootfs.img`, and reaches SSH at `172.16.99.70`.

The follow-up reboot validation also passed with the corrected dracut interface
name: `bootdev=netboot0`, `ifname=netboot0:00:07:32:78:65:c6`, and static
`ip=...:netboot0:none`. The live OS now exposes the primary management
interface as `netboot0`.

On 2026-05-13 a later reachability check found `172.16.99.70` not answering
ARP from X12AGAIN or Hasslehoff while CSS326 `ge14` still reported link up and
the serial console was at a live Linux login prompt. A PDU outlet-4 reboot
restored iPXE chainload and SSH. Post-boot evidence showed `netboot0` up with
`172.16.99.70/24`, default route via `172.16.99.1`, `sshd` running, `dhcpcd`
marked crashed, hostname still `gmktek-k10-stage5`, and `sssd` stopped due to a
missing `/etc/sssd/sssd.conf`. Treat this as a live-rootfs profile durability
defect, not an SSH source filter or switch/VLAN defect.

Observed hardware note: Linux/BSDRP serial validation reported 32 GiB available
memory, while the planned inventory expected 64 GiB. Validate DIMM population
before scheduling memory-heavy workloads on this node.

## Current Blockers

- The live HTTP rootfs still carries `/etc/conf.d/hostname` from the K10 image:
  `gmktek-k10-stage5`.
- `sssd` is installed but `/etc/sssd/sssd.conf` is absent, so RBAC/AAA
  acceptance is blocked until the automation-admin image gets its own firstboot
  identity/enrollment overlay or rebuilt rootfs.
- FreeIPA currently has no `admin-sun99-forge-099070.rfc1918.host` host entry.
  The IPA controller host keytab can authenticate but does not have permission
  to add the host principal; an admin ticket or generated host OTP is required
  before live or firstboot enrollment can complete.
- `dhcpcd` is marked crashed after boot even though the dracut-provided static
  management route is up on `netboot0`; installed-system networking should be
  rendered by the automation-admin profile instead of relying on this live-rootfs
  behavior.

## Acceptance Gates

The M70 is not ready to replace X12AGAIN as the automation-admin host until it
passes these checks:

- SSH works as the expected administrative account with vault-backed access.
- `ansible --version`, `ansible-vault`, `git`, and `gh` work from the host.
- `/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin` can open X12AGAIN SoL.
- Hasslehoff, CCR2004, NetBox, FreeIPA, local ntfy HTTPS, GitHub, and the
  off-host backup target are reachable.
- Restored continuity paths exist for `/root`, `/opt`, `/var/lib/ansible`,
  `/var/lib/codex`, `/var/lib/forge-memory`, and `/var/lib/git`.
- Forge memory spool writes to `/var/lib/forge-memory/spool`.

## Backout

No X12AGAIN reimage should start until the M70 passes acceptance. If M70
provisioning fails, leave X12AGAIN online, keep using Hasslehoff-hosted service
VMs for infrastructure services, and retry M70 provisioning after correcting
BIOS, DHCP, iPXE, or storage layout issues.
