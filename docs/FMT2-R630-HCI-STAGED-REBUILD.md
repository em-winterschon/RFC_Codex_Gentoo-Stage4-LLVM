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
5. Validate `pri` as a Gentoo stage4 hypervisor with AAA, NTP, observability,
   rsyslog, ZFS, libvirt, and iDRAC control.
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
