# FMT2 R630 HCI Staged Rebuild

## Purpose

Prepare the three Dell R630 FMT2 virtualization hosts for staged Gentoo
hypervisor, OpenStack, OpenShift, and VM-migration work without putting the
only currently useful local ZFS pool at risk.

This is a staged rebuild plan. It is not permission to wipe any host.
Destructive actions require a host-specific maintenance gate.

## Hosts

| Host | LAN IP | iDRAC IP | Current state | Rebuild role |
| --- | --- | --- | --- | --- |
| `kvm-sfo200-pri-9922` | `10.200.99.22` | `172.18.20.122` | Ping and iDRAC reachable; current Forge SSH key rejected. | First destructive rebuild candidate. |
| `kvm-sfo200-sec-9923` | `10.200.99.23` | `172.18.20.123` | Rocky 8.9, kernel `6.3.8-1.el8.elrepo`, libvirt inactive. | Second rebuild candidate after `pri` validates. |
| `kvm-sfo200-ter-9924` | `10.200.99.24` | `172.18.20.124` | Rocky 8.9, kernel `6.3.8-1.el8.elrepo`, libvirt inactive, healthy `dstore` ZFS pool. | Storage-preserving provisioning anchor. |

All three iDRACs answered Redfish root service probes and IPMI chassis status
on 2026-05-19. iDRAC firmware reported `2.83`.

## Network Fabric Policy

All three R630 virtualization hosts should converge on the same physical NIC
role split:

| Interface set | Hardware | Intended role | VM exposure |
| --- | --- | --- | --- |
| `eno1` + `eno2` | Intel X710 10GbE | Host management LACP bond. | Host-only management path. |
| `eno3` + `eno4` | Intel X710 10GbE | VM front-end LACP bond. | Open vSwitch bridge plus SR-IOV VFs where host firmware exposes them. |
| `enp130s0f0np0` + `enp130s0f1np1` | Mellanox ConnectX-4 50GbE | Back-end storage, RoCEv2, NVMe-oF, iSER, NFS-RDMA. | Prefer SR-IOV VF passthrough for RDMA VMs; only use OVS switchdev/representors after host and switch validation. |

Do not put RDMA/RoCE traffic on the host management bond. Keep front-end VM
traffic and lossless storage traffic in separate VLANs/classes even when both
are attached to the same Arista leaf.

The ConnectX-4 ports should not be modeled as a generic Linux LACP bond until
RoCEv2 behavior is explicitly validated. The preferred first-pass design is two
independent 50GbE RDMA paths with protocol-layer multipath or failover:
NVMe-oF multipath, iSER multipath, NFS-RDMA path selection, or workload-level
placement. Hardware LAG or OVS switchdev can be added later if the exact
firmware, driver, and Arista configuration prove lossless behavior under link
failure.

Live evidence from `kvm-sfo200-sec-9923` and `kvm-sfo200-ter-9924` on
2026-05-19:

- All four X710 10GbE ports were `UP` at `10000Mb/s`.
- Both ConnectX-4 ports were `UP` at `50000Mb/s`.
- `rdma link show` reported `mlx5_0` and `mlx5_1` as `ACTIVE` on both hosts.
- `sec` exposed `32` X710 SR-IOV VFs per port; `ter` exposed `0` X710 VFs.
- Both hosts exposed `0` ConnectX-4 VFs at the time of discovery.
- Both hosts had `ofed_info` absent and `mlx5_core`/`mlx5_ib` loaded from the
  in-kernel module tree. This is acceptable for discovery only; production
  RDMA admission requires the selected vendor OFED/DOCA driver path.
- `sec` reported placeholder ConnectX MACs `00:00:00:00:12:34` and
  `00:00:00:00:12:35`; fix or explain that firmware state before using those
  MACs in NetBox, DHCP, switch ACLs, or VF policy.

## Gentoo stage4 kernel pivot

The production path for `kvm-sfo200-pri-9922` is now a Gentoo stage4 rebuild
using the `metal-fmt2-r630-openstack-roce` profile and the validated source
kernel atom:

```text
kernel_strategy: gentoo-kernel
kernel_package_atom_override: =sys-kernel/gentoo-kernel-6.18.18
profile: metal-fmt2-r630-openstack-roce
```

This avoids spending production time forcing MLNX_OFED 24.10 onto the old
Rocky 8.9 ELRepo `6.3.8` kernel. The first rebuilt R630 should boot a
repo-defined Gentoo kernel with the R630 hypervisor, NFS, iSER, NVMe-RDMA,
RoCEv2, ZFS, OVS, AAA, rsyslog, and observability fragments applied before
OpenStack is admitted as a workload.

Keep `ter` as the storage-preserving anchor while `pri` is rebuilt. Do not
convert `ter` to this profile until `pri` and then `sec` provide replacement
capacity or `dstore` has a separate preservation decision.

## `ter` MLNX_OFED diagnostic-only source-build path

`kvm-sfo200-ter-9924` runs the ELRepo kernel
`6.3.8-1.el8.elrepo.x86_64`. The NVIDIA MLNX_OFED 24.10 RHEL 8.9 repository
contains prebuilt `kmod-mlnx-ofa_kernel` packages for the stock
`4.18.0-513.5.1.el8_9` kernel, so those kmods must not be installed as the
driver answer for `ter`.

The old Rocky source-build path is retained as diagnostic-only evidence and as
a reusable builder pattern for RHEL-like hosts. It is not the current
production critical path for the FMT2 R630 rebuild. The diagnostic attempt uses
the staged source bundle:

```text
/var/tmp/MLNX_OFED_SRC-24.10-4.1.4.0.tgz
sha256: 6401c0e49f12da0bceb1b03037e39eed2b11e3624dcba139485d2e1631ce5682
kernel: 6.3.8-1.el8.elrepo.x86_64
kernel sources: /usr/src/kernels/6.3.8-1.el8.elrepo.x86_64
```

Build tooling lives in an isolated buildroot under `dstore`, not in the live
OS package set:

```text
buildroot: /srv/stage/mlnx-ofed-buildroot
output: /srv/stage/mlnx-ofed-builds/24.10-4.1.4.0/6.3.8-1.el8.elrepo.x86_64
script: scripts/fmt2-build-mlnx-ofed-rhel-kernel.sh
```

The live host remains admitted for storage-anchor duties only after the source
build and install gates are explicit. A successful source build is not itself
permission to install or reboot; install and reboot require a host-specific
change gate because `ter` is the current FMT2 storage anchor.

First source-build result: the full kernel-only package set failed at `iser`
against kernel `6.3.8-1.el8.elrepo.x86_64` because MLNX_OFED 24.10 iSER source
references `struct scsi_cmnd.request`, which is absent from that kernel API.
This is tracked as a kernel/package compatibility gate, not a missing
dependency. Do not chase this as the steady-state FMT2 solution unless a
separate maintenance gate explicitly chooses to keep a RHEL-like OS on one of
the R630s.

Acceptance gate before fabric automation mutates host or switch state:

1. Confirm BIOS SR-IOV/IOMMU settings on all three R630s.
2. Confirm firmware and driver versions for X710 and ConnectX-4.
3. Install or stage the vendor OFED/DOCA driver package compatible with the
   target OS/kernel and verify `ofed_info -s`.
4. Confirm Arista DCS-7060CX-32S port mappings for every X710 and ConnectX
   link.
5. Snapshot Arista configuration and collect interface counters before changes.
6. Validate MTU, VLANs, LACP groups, LLDP neighbors, PFC, ECN/WRED, and
   DSCP/PCP mapping in read-only mode.
7. Enable VFs only after persistent host profile and rollback commands exist.
8. Run RDMA pairwise tests and one-path-failure tests before advertising the
   hosts as RDMA-capable to SLURM, OpenStack, OpenShift, or storage roles.

Arista access note: HTTPS/eAPI on `172.18.20.10:443` is reachable through the
FMT2 path and redirects to `/eapi/`. SSH on `22/tcp` is restricted by the
switch `mgmt-acl`, which permits CheckMK `10.200.99.27` and Prometheus
`10.200.99.46`, but not M70 `172.16.99.70` or NASA `10.200.99.18`. Live
read-only access works from M70 by proxying through CheckMK with the
`verwalterin.vernetzen.id_rsa` key:

```bash
ssh 7060 "show hostname"
```

The M70 FMT2 SSH profile must connect to the switch as `verwalterin`, never
`root`; the typo alias `sw-sfo200-7060cx32s-2010.vernetzezn.io` is treated as
an alias for the live management IP to prevent root fallback. Live 2026-05-19
checks showed `Management1` at `172.18.20.10/24` via DHCP, default route via
`172.18.20.1`, and SSH enabled in the default VRF. The archived ACL line
`permit host 172.18.20.0` permits only the `.0` address, not the whole
`172.18.20.0/24` subnet.

Live Arista port evidence collected on 2026-05-19:

- `pri` X710 ports are `Et3/1`-`Et3/4`, split into `Po312` for management and
  `Po334` for VM front-end VLAN 20.
- `sec` X710 ports are `Et4/1`-`Et4/4`, split into `Po412` for management and
  `Po434` for VM front-end VLAN 20.
- `ter` X710 ports are `Et5/1`-`Et5/4`, split into `Po512` for management and
  `Po534` for VM front-end VLAN 20.
- `sec` ConnectX-4 ports are `Et7/1` and `Et7/3`, currently attached to
  `Po713` as `dot1q-tunnel` access VLAN 50.
- `ter` ConnectX-4 ports are `Et8/1` and `Et8/3`, currently attached to
  `Po813` as `dot1q-tunnel` access VLAN 50.
- Existing R630 port-channels `Po312`, `Po334`, `Po412`, `Po434`, `Po512`,
  `Po534`, `Po713`, and `Po813` were down because the hosts are not currently
  running matching LACP bonds.
- R630-facing switch interfaces reported zero error counters during the
  read-only sample.
- ConnectX switch-side MTU is `9214`, while `ter` host-side X710 and
  ConnectX interfaces are still MTU `1500` on the temporary Rocky install.
- No live QoS, PFC, ECN, WRED, class-map, or policy-map config was found in
  the EOS running-config include scan.

RoCEv2 tuning must therefore start from an explicit change plan: either keep
the current `Po713`/`Po813` LACP design and configure matching host bonds only
after RDMA behavior is tested, or remove ConnectX ports from LACP and run two
independent VLAN 50 jumbo paths first. The safer first admission path is two
independent 50GbE RoCEv2 links with protocol-layer multipath; promote LACP or
OVS switchdev only after one-link-failure testing is clean.

## `ter` Storage Policy

`kvm-sfo200-ter-9924` is the temporary FMT2 storage and provisioning anchor.
Do not reimage it until both of these are true:

1. `kvm-sfo200-pri-9922` and `kvm-sfo200-sec-9923` have working replacement
   capacity.
2. The `dstore` pool contents are either intentionally preserved in place,
   replicated elsewhere, or explicitly declared disposable.

The operating-system RAID1 SATA SSD set on `ter` is OS-only. It must not be
used for VM disks, VM images, migration staging, backups, ISO caches, package
repositories, or scratch data. Standard OS use is acceptable: `/`, `/boot`,
`/boot/efi`, swap, package manager state, logs, and minimal service config.

All storage-related operations on `ter` should use the existing `dstore` ZFS
pool:

- QEMU/libvirt file-backed VM images.
- QEMU/libvirt zvol-backed VM block devices.
- Hasslehoff VM migration staging.
- FMT2 provisioning artifacts.
- Backup relay targets.
- ISO and installer caches.
- Temporary data-transfer work areas.

Observed `dstore` state on 2026-05-19:

- Topology: `draid2:4d:8c:0s-0` across eight HGST SAS SSDs.
- Cache: Intel Optane `INTEL_SSDPED1D480GA_PHMB7474003H480DGN`.
- Health: `ONLINE`, no known data errors.
- Pool properties: `compression=lz4`, `atime=off`, `mountpoint=none`.
- Existing dataset: `dstore/testing` mounted at
  `/opt/storage/local/zfs/dstore`.

## Live `dstore` Dataset Layout

These non-destructive dataset additions were created on 2026-05-19 after
confirming no conflicting datasets existed. They are the live storage namespace
for FMT2 staging on `ter`.

```bash
zfs create -o mountpoint=/srv/libvirt dstore/libvirt
zfs create -o mountpoint=/srv/libvirt/images -o recordsize=1M -o compression=zstd dstore/libvirt/images
zfs create -o mountpoint=none dstore/libvirt/zvols
zfs create -o mountpoint=/srv/provisioning -o recordsize=1M -o compression=zstd dstore/provisioning
zfs create -o mountpoint=/srv/backups -o recordsize=1M -o compression=zstd dstore/backups
zfs create -o mountpoint=/srv/backups/hasslehoff -o recordsize=1M -o compression=zstd dstore/backups/hasslehoff
zfs create -o mountpoint=/srv/iso -o recordsize=1M -o compression=zstd dstore/iso
zfs create -o mountpoint=/srv/stage -o recordsize=1M -o compression=zstd dstore/stage
```

Recommended zvol pattern for libvirt block devices:

```bash
zfs create -V 128G -o volblocksize=16K -o compression=zstd dstore/libvirt/zvols/example-root
```

Use file-backed QCOW2 images under `dstore/libvirt/images` for portable VM
imports and early migration testing. Use zvol-backed disks under
`dstore/libvirt/zvols` for high-I/O VMs after the libvirt storage-pool
automation is validated.

## Libvirt Storage Pools

The current Rocky 8.9 libvirt build on `ter` reports `pool type='zfs'
supported='no'`, so do not model ZFS zvols as a native libvirt ZFS pool on the
temporary OS. Use the directory pool for portable QCOW2 images and attach zvols
explicitly by block-device path when a VM needs zvol-backed storage.

| Pool | Type | Backing path | Use |
| --- | --- | --- | --- |
| `dstore-images` | libvirt `dir` pool | `/srv/libvirt/images` | QCOW2 imports, temporary VM disks, migration tests. |
| `dstore-zvols` | manual zvol mapping | `/dev/zvol/dstore/libvirt/zvols/*` | Stable high-I/O VM disks after explicit zvol creation. |

Do not define a default libvirt storage pool on the OS RAID1 root filesystem.
If libvirt creates `/var/lib/libvirt/images`, it should remain empty or be
replaced with a deliberate symlink only after the `dstore-images` dataset is
mounted.

## 2026-05-19 Live Libvirt Smoke Test

Validation performed from M70 through the FMT2 OpenVPN path:

1. Confirmed Rocky 8.9 has libvirt `8.0.0`, qemu-kvm `6.2.0`, `virt-install`,
   and active `libvirtd`.
2. Defined `dstore-images` as a persistent autostart libvirt `dir` pool backed
   by `/srv/libvirt/images`.
3. Confirmed libvirt storage capabilities report native ZFS pool support as
   unavailable on the temporary Rocky install.
4. Created and destroyed a 128 MiB zvol
   `dstore/libvirt/zvols/forge-zvol-smoke`, confirming it appeared at
   `/dev/zvol/dstore/libvirt/zvols/forge-zvol-smoke -> /dev/zd0`.
5. Created a disposable no-network KVM domain `forge-dstore-smoke` with a
   256 MiB QCOW2 disk at `/srv/libvirt/images/forge-dstore-smoke.qcow2`.
6. Started the domain and verified `domstate-after-start=running`.
7. Destroyed the domain and verified `domstate-after-destroy=shut off`.
8. Created and listed a stopped-disk snapshot with `qemu-img snapshot`.
9. Undefined the domain, removed the QCOW2 disk, refreshed the pool, and
   verified no leftover domain exists.
10. Verified `/var/lib/libvirt/images` remains empty.

Result: `ter` can run KVM/libvirt workloads backed by `dstore-images` without
placing VM payloads on the OS RAID1 mirror. Zvol-backed disks are viable as
manual block-device mappings, but native libvirt ZFS pool management waits for
the final Gentoo hypervisor profile or a libvirt build with ZFS storage-driver
support.

## Staged Rebuild Sequence

1. Keep M70 as the out-of-band automation source and FMT2 OpenVPN transport.
2. Keep `ter` powered and avoid destructive changes to `dstore`.
3. Use `ter` for FMT2 staging storage and, if needed, a temporary provisioning
   VM or service backed by `dstore`.
4. Reimage `pri` first through iDRAC PXE or virtual media.
5. Validate `pri` as a Gentoo stage4 hypervisor using
   `metal-fmt2-r630-openstack-roce` with AAA, NTP, observability, rsyslog,
   ZFS, libvirt, OVS, RDMA storage fragments, and iDRAC control.
6. Reimage `sec` second after `pri` can host migrated services or test VMs.
7. Keep `ter` on its existing OS until the `dstore` preservation or migration
   plan is complete.

## Platform Direction

Use Gentoo stage4 as the bare-metal hypervisor substrate for these R630s:

- OpenRC, no systemd.
- QEMU/libvirt as the first hypervisor layer.
- ZFS for local VM storage.
- FreeIPA/SSSD for AAA.
- rsyslog, node exporter, collectd, and Check_MK agent for observability.
- iDRAC Redfish/IPMI for power, boot override, inventory, and recovery.

Treat OpenStack and OpenShift as workloads to host on top of the Gentoo
hypervisor substrate during this transition. Do not try to make the first FMT2
R630 rebuild depend on native Gentoo OpenStack or OpenShift control-plane
packaging.

## Acceptance Gates

Before wiping `pri`:

1. iDRAC boot override is validated read-only.
2. Current `pri` SSH failure is captured as evidence.
3. Netboot or virtual-media artifact URL is reachable from the iDRAC network.
4. Backout path is documented: iDRAC console, power cycle, boot override clear,
   and alternate installer media.

Before using `ter` for VM migration:

1. `zpool status dstore` reports `ONLINE`.
2. The `dstore` live datasets exist and are mounted at the intended paths.
3. Libvirt `dstore-images` points only at `/srv/libvirt/images`.
4. Zvol-backed VM disks are attached only through explicit
   `/dev/zvol/dstore/libvirt/zvols/*` paths.
5. A test VM can be created, started, stopped, snapshotted, and deleted without
   writing VM payloads to the OS RAID1 root filesystem.

Before reimaging `ter`:

1. `dstore` contents are inventoried.
2. Required VMs, backups, and staging data are moved or declared disposable.
3. Replacement storage capacity exists on `pri`, `sec`, NASA, or another
   approved target.
4. A host-specific wipe gate is approved.
