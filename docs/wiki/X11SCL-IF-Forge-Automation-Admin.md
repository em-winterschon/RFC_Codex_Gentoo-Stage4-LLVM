# X11SCL-IF Forge Automation Admin

The Supermicro X11SCL-IF is the preferred long-term Forge automation-admin
platform once its replacement CPU heatsink is installed. The M70 remains the
validated continuity host and future QAT/edge/SLURM worker candidate, but the
X11SCL-IF is a better control-plane fit because it has native Supermicro
IPMI/OOB, stronger Xeon E-2176G CPU performance, native M.2 PCIe storage,
conventional SATA SSD bays, and PCIe expansion for RDMA-capable QLogic NICs.

## Target Hardware

| Field | Value |
| --- | --- |
| Board | Supermicro X11SCL-IF |
| CPU | Intel Xeon E-2176G |
| Memory | 32 GiB ECC UDIMM currently installed |
| Persistent storage | 2 x Samsung 883-DCT 2TB SATA SSD, mirrored ZFS |
| Scratch storage | Board M.2 NVMe |
| Network expansion | QLogic QL41234 10/25G or QL41164HLRJ 10G |
| Stage5 profile | `metal-forge-automation-admin` |

## Identity Policy

Do not repoint `forge.rfc1918.host`, `forge-sun99.rfc1918.host`, or
`admin-sun99-forge.rfc1918.host` away from the M70 until the X11SCL-IF passes
all acceptance gates. Final IPAM/DCIM records require physical discovery of the
BMC MAC, primary NIC MAC, switchport, PDU outlet, disk serials, and QLogic NIC
ports.

## Storage Policy

The Samsung 883-DCT pair is the authoritative mirrored `zroot`. The M.2 NVMe is
scratch/build-cache only and must not be the only copy of Forge state, vault
material, repo state, or logs.

## Cutover Policy

The X11SCL-IF becomes primary only after SSH, FreeIPA/SSSD, Ansible vault,
GitHub CLI, NetBox API, local ntfy HTTPS, Hasslehoff, CCR2004, X12AGAIN SoL,
ZFS health, and off-host backup validation pass. The M70 stays online as
rollback through at least one successful post-cutover reboot.

