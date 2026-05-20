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
- vendor OFED/DOCA alignment for Mellanox/NVIDIA ConnectX and BlueField hosts
  admitted to the RDMA fabric; in-kernel `mlx5_core` alone is discovery-only
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

## FMT2 R630 / Arista 7060 Profile

The FMT2 R630 HCI cluster uses Intel X710 ports for management and front-end VM
traffic, and Mellanox ConnectX-4 ports for the back-end RDMA fabric:

- `eno1` + `eno2`: host management LACP bond.
- `eno3` + `eno4`: VM front-end LACP bond, OVS bridge, and X710 SR-IOV VFs
  where firmware exposes them.
- `enp130s0f0np0` + `enp130s0f1np1`: 2x 50GbE RoCEv2 storage paths connected
  to the Arista DCS-7060CX-32S.

For the ConnectX-4 RDMA path, use independent 50GbE fabrics first. Do not
assume Linux bonding, LACP, or OVS will preserve RDMA offload semantics until
the exact NIC firmware, kernel driver, OVS mode, and Arista lossless profile
are validated. VMs that need RDMA should receive ConnectX VFs directly before
any OVS switchdev or representor design is promoted.

The current R630 discovery state uses in-kernel `mlx5_core`/`mlx5_ib` and has
no `ofed_info` tool present. Treat that as a temporary inventory state only.
For admission policy, in-kernel `mlx5_core` remains discovery-only until the
selected vendor OFED/DOCA path and E2ET gates pass.
Before these hosts are admitted as RDMA production endpoints, install or stage
the selected vendor OFED/DOCA driver path, verify `ofed_info -s`, and converge
SR-IOV enablement consistently across all three R630s.

`kvm-sfo200-sec-9923` is the current positive-control host for the R630 RDMA path.
Live 2026-05-20 evidence shows the intended successful physical path:
X710 ports enumerate and link at 10G with 32 total VFs per PF, ConnectX-4
endpoints enumerate as Mellanox MT27700 `[15b3:1013]`, both ConnectX ports link
at 50G, `rdma link show` reports `mlx5_0` and `mlx5_1` as `ACTIVE`, and the
Arista 7060 sees LLDP neighbors on `Et7/1` and `Et7/3`. That makes `sec` the
right comparison target for `pri`, but not a production RDMA endpoint yet:
`ofed_info` and ibverbs/perftest tooling are absent, the driver is still
in-kernel `mlx5`, and the placeholder ConnectX MACs must be fixed or explained
before NetBox/IPAM/VF policy consumes them.

Gentoo stage4 R630 admission target: `kvm-sfo200-pri-9922` should be rebuilt
first with `metal-fmt2-r630-openstack-roce`, `kernel_strategy: gentoo-kernel`,
and `=sys-kernel/gentoo-kernel-6.18.18`. That profile carries the R630
hypervisor, NFS, iSER, NVMe-RDMA, RoCEv2, ZFS, OVS, AAA, rsyslog, and
observability contract for FMT2. The old Rocky 8.9 `ter` MLNX_OFED source
builder is diagnostic-only after the iSER API mismatch on kernel
`6.3.8-1.el8.elrepo.x86_64`; do not make it the production driver path unless
a separate maintenance gate keeps a RHEL-like OS on one of the R630s.
MLNX_OFED source builder is diagnostic-only for the current FMT2 R630 rebuild
path.

Arista DCS-7060CX-32S changes require a pre-change config snapshot, live port
mapping, jumbo MTU, storage-class PFC only, ECN/WRED where available, and
rollback commands. SSH was filtered during the 2026-05-19 check, while HTTPS
eAPI on `172.18.20.10:443` was reachable. A second 2026-05-19 check from the
CheckMK VM showed SSH open on `22/tcp`, but authentication failed. Until
credentials or key placement are resolved, switch automation should use eAPI or
CheckMK-sourced SSH only for read-only validation.

Follow-up on 2026-05-19 resolved CheckMK-sourced SSH by using the
`verwalterin.vernetzen.id_rsa` key and the M70 `7060` SSH alias with
`ProxyJump verwalterin@checkmk`. The switch management ACL still restricts SSH
to approved source IPs; do not add M70 or NASA to the ACL until a switch
change-control snapshot and rollback plan exist.

The live 7060 config already has jumbo MTU on the ConnectX-facing interfaces
and VLAN 50 named `cx4-dual-50g-ceph`, but it does not yet have an explicit
lossless RoCEv2 QoS profile. The current ConnectX-facing ports are configured
as LACP port-channels (`Po613` for `pri`, `Po713` for `sec`, `Po813` for
`ter`) in VLAN 50 or `dot1q-tunnel` VLAN 50 modes; those port-channels were
down during discovery because the temporary host OS instances are not running
matching bonds. First-pass RoCEv2 admission should prefer independent 50GbE
paths on VLAN 50, then add LACP or switchdev only after host OFED, switch QoS,
RDMA pair tests, and one-path-failure tests pass.

`pri` has an additional 2026-05-20 admission blocker: its disposable
firmware-maintenance OS and iDRAC hardware inventory do not enumerate any
Mellanox/ConnectX device, even though the Arista reports `Et6/1` and `Et6/3`
connected at 50G and assigned to `Po613`. BIOS SR-IOV and MMIO above 4G are
enabled, BIOS slot-disablement reports Slot 1 enabled, DMI reports Slot 1 as
available, `lspci -tvnn` shows no Mellanox endpoint, and Arista LLDP reports no
neighbors on `Et6/1` or `Et6/3`. Resolve the physical slot/card/cabling or
inventory mismatch before using `pri` as the first RDMA endpoint.

The physical ConnectX replacement path is now the preferred unblock route for
`pri`. A replacement or reseat is not enough by itself: production RDMA
admission requires Linux PCI enumeration, iDRAC hardware inventory, Arista LLDP,
vendor OFED/DOCA reporting, pairwise RDMA smoke, protocol-specific storage
smoke, and one-path-failure evidence. Until those gates pass, use `sec` and
`ter` for RDMA discovery and keep `pri` limited to firmware, X710, and
non-RDMA Gentoo preparation.

The `sec` positive-control workflow therefore runs concurrently with the `pri`
replacement workflow but does not depend on it. Safe concurrent work is:
read-only `sec` evidence capture, Arista `Et7/1`/`Et7/3` comparison capture,
NVIDIA DOCA/OFED preflight with `apply=false`, and staging the userspace RDMA
tooling required for later `sec` to `ter` pairwise smoke. Destructive `sec`
rebuild, live vendor-driver install, LACP promotion, and storage protocol
promotion remain separate gates.

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
