# RDMA Storage Fabric Plan

## Goal

Define the baseline for hosts, VMs, and storage services that require RDMA
access to the storage fabric while keeping management, VM bridge, and lossless
storage classes separate.

## Protocol Scope

Required protocol families:

- NFSv3 over TCP for simple bootstrap mounts and legacy compatibility
- NFSv4 with UID/GID consistency from FreeIPA/SSSD
- NFS-RDMA for validated RoCE-capable hosts
- iSER for iSCSI over RDMA where arrays or targets require block semantics
- NVMe-RDMA for NVMe-oF namespaces
- non-RDMA iSCSI as a fallback protocol

## Host Baseline

Bare-metal and VM profiles that opt into RDMA storage must include:

- `rdma-core`
- OFED/DOCA alignment for Mellanox/NVIDIA hosts where required
- kernel support for SUNRPC RDMA, iSER, NVMe-RDMA, DM multipath, and ZFS
- `multipath-tools` where block devices have redundant paths
- metrics exporters for link state, queue drops, retransmits, RDMA counters,
  multipath path state, and filesystem latency

Containers should not mount fabric storage directly by default. Prefer host or
VM mount ownership, then bind-mount into containers with explicit read/write
policy.

## Switch Tuning Profile

RoCE-v2 switch profiles need explicit, reversible configuration:

- dedicated VLAN or class for lossless storage traffic
- MTU consistency across host NICs and switch ports
- PFC only on the storage traffic class, not globally
- ECN/WRED where supported
- DSCP/PCP mapping documented per switch family
- LACP behavior validated before carrying RDMA traffic
- rollback configuration snapshot before mutation

## Validation Gates

Each RDMA-capable host must pass:

- interface link speed/duplex/MTU validation
- route and VLAN validation against NetBox/IPAM
- RDMA device enumeration
- `rping` or equivalent pairwise test
- protocol-specific mount or namespace attach
- fio-style latency/IOPS smoke test
- failure test for one path down where multipath is expected
- telemetry emission into Prometheus/VictoriaMetrics

## Open Dependencies

- Final switch family mapping for CRS309, CRS354, future Arista, and Juniper
  devices.
- QNAP/archive role decision: archive NAS, NFS home service, or temporary
  staging only.
- NVMe-oF array inventory, dual-port drive mapping, and ZFS dataset ownership.
- FreeIPA UID/GID policy must be stable before shared home directories become
  authoritative.
