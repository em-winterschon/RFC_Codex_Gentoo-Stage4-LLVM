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
| Stage5 profile | `metal-forge-automation-admin` |

## Provisioning Plan

The M70 is tracked as a UEFI-only `pxe-to-ipxe` install target. RouterOS desired
state reserves a static DHCP lease for `172.16.99.70` and sends boot file
`m70-forge-ipxe.efi` from the SUN99 netboot publisher at `172.16.99.88`.

The current first-stage binary is intentionally sourced from the already
validated `172.16.99.88` snponly artifact and published under the M70-specific
name. Follow-up work should rebuild a generic first-stage binary name so the
source artifact is no longer K10-labeled.

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
