# X11SCL-IF Forge Automation Admin

## Purpose

The Supermicro X11SCL-IF is the preferred long-term Forge automation-admin
platform once its replacement CPU heatsink is installed. The M70 remains the
validated continuity host and future QAT/edge/SLURM worker candidate, but the
X11SCL-IF is a better fit for sustained automation control-plane use because it
has native Supermicro IPMI/OOB, stronger single-threaded CPU performance,
native M.2 PCIe storage, conventional SATA SSD bays, and real PCIe expansion for
RDMA-capable NICs.

No X12AGAIN/Prinzessin reimage should begin until either the M70 or the
X11SCL-IF passes the automation-admin acceptance gates.

## Platform Decision

| Field | Value |
| --- | --- |
| Target role | Primary Forge automation-admin host |
| Board | Supermicro X11SCL-IF |
| CPU | Intel Xeon E-2176G, 6 cores / 12 threads |
| Current memory | 32 GiB ECC UDIMM, 2 x 16 GiB |
| Maximum practical memory | 64 GiB ECC UDIMM class for this board family |
| OOB | Supermicro BMC/IPMI |
| Primary persistent storage | 2 x Samsung 883-DCT 2TB SATA SSD, mirrored ZFS |
| Fast local storage | Board M.2 NVMe, scratch/build-cache role |
| Network expansion | QLogic QL41234 10/25G or QL41164HLRJ 10G, RDMA/RoCE capable |
| Temporary predecessor | `admin-sun99-forge-099070.rfc1918.host` on M70 |

## Reserved Identity

The final X11SCL-IF host identity is not assigned until physical installation
and NIC/BMC MAC discovery are complete.

Recommended naming if it replaces the M70 as the primary Forge host:

| Field | Planned Value |
| --- | --- |
| Inventory key | `admin_sun99_forge_primary` or a numbered `admin_sun99_forge_0990xx` key after IP assignment |
| Primary FQDN | `admin-sun99-forge-0990xx.rfc1918.host` |
| Stable aliases | `admin-sun99-forge.rfc1918.host`, `forge.rfc1918.host`, `forge-sun99.rfc1918.host` |
| Stage5 profile | `metal-forge-automation-admin` |
| Network boot flow | UEFI iPXE preferred, PXE-to-iPXE fallback acceptable |
| BMC DNS | Assign under the existing `ipmi-*` naming convention after BMC IP selection |

Do not repoint the stable Forge aliases away from the M70 until the X11SCL-IF
passes all acceptance gates and the M70 has a verified rollback path.

## Storage Layout

The preferred durable layout is:

- SATA SSD mirror: `zroot`, mirrored over the two Samsung 883-DCT 2TB SSDs.
- `zroot/ROOT/gentoo`: persistent Gentoo/OpenRC root.
- ZFS datasets for `/home`, `/opt`, `/srv`, `/var/lib`, `/var/log`,
  `/usr/local`, and `/tmp`.
- Board M.2 NVMe: non-authoritative scratch/build-cache storage only.
- EFI boot: local ESP on a small SATA/SATADOM device if available, otherwise a
  small partition on one mirrored SATA SSD plus documented replacement steps.

The NVMe scratch device must not be the only copy of Forge state, vault
material, repo state, or automation logs. Any NVMe cache content must be
rebuildable from git, binpkg repositories, off-host backups, or service APIs.

## Network And RDMA

Install one RDMA-capable QLogic NIC if cooling and slot layout allow it. The
preferred order is:

1. QLogic QL41234 when 10/25G fabric validation is the priority.
2. QLogic QL41164HLRJ when 4 x 10GBASE-T port fanout is more useful.

Initial automation-admin traffic should still use a simple management NIC on
the SUN99 management subnet. RDMA/RoCE/NVMe-oF traffic should stay on dedicated
fabric VLANs and must not become a prerequisite for SSH, Ansible, vault access,
or X12AGAIN SoL recovery.

## Migration Sequence

1. Install the replacement heatsink and validate POST, BMC access, and stable
   temperatures before adding migration-critical storage.
2. Discover and record board serial, BMC MAC, management NIC MACs, QLogic NIC
   PCI IDs, disk serials, and PCIe topology.
3. Assign NetBox/IPAM records, DNS records, switchport, and PDU outlet metadata.
4. Provision the host with the `metal-forge-automation-admin` profile.
5. Build mirrored ZFS persistent root on the Samsung 883-DCT pair.
6. Restore Forge continuity paths from the off-host X12AGAIN backup or from the
   validated M70 continuity state.
7. Validate FreeIPA/SSSD, GitHub CLI, Ansible vault, ntfy HTTPS, NetBox API,
   Hasslehoff, CCR2004, and X12AGAIN SoL.
8. Repoint Forge aliases only after validation passes.
9. Keep the M70 online until at least one successful X11SCL-IF backup and one
   reboot-durable validation cycle complete.

## Acceptance Gates

The X11SCL-IF can become the primary Forge automation-admin host only after:

- Root login and the non-root administrative account both work over SSH.
- `ansible`, `ansible-vault`, `git`, `git-lfs`, and `gh` work locally.
- `/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin` can reach X12AGAIN SoL.
- FreeIPA/SSSD resolves the expected floating admin user and SSH keys.
- Local ntfy HTTPS is reachable.
- NetBox API is reachable and has the host/IPAM/DCIM records.
- Hasslehoff SSH/API and CCR2004 RouterOS access validate.
- The mirrored ZFS pool is healthy after reboot.
- Off-host backup push and restore smoke tests pass.
- Stable aliases resolve to the new host only after the prior checks pass.

## Backout

If the X11SCL-IF build fails, leave Forge aliases on the M70, keep X12AGAIN
online, and do not start the X12AGAIN reimage. The X11SCL-IF can be rebuilt
without impacting the currently validated M70 continuity path.

If the X11SCL-IF passes initial provisioning but later fails acceptance, revert
DNS aliases to the M70 and keep the X11SCL-IF as an offline repair candidate
until storage, thermal, NIC, or BMC faults are corrected.

