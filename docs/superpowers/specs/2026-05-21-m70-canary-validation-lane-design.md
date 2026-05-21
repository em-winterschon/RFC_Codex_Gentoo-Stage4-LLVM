# M70 Canary Validation Lane Design

## Goal

Bring a second M70 online as a canary/blast-test node with the same baseline
machine profile as the primary Forge M70, while keeping risky network, boot,
runtime, and package changes away from the active Forge control-plane host until
they pass repeatable validation gates.

## Roles

The current M70, `admin-sun99-forge-099070.rfc1918.host`, remains the primary
Forge/control-plane host. It should keep stable management, memory, ntfy/FCP,
NetBox automation, and operator workflows available.

The second M70 becomes the ring-0 canary. It can be rebooted, reimaged, package
tested, kernel-argument tested, OVS tested, and runtime tested without affecting
primary Forge workflows.

## Network Design

Use the two Intel i211 ports for management and rescue only:

- `netboot0`: primary management, iPXE, rescue, and first boot path.
- `enp3s0`: post-boot management backup.
- `bond-mgmt`: active-backup management bond after the OS is up.

Keep the management bond outside Open vSwitch. Do not put workload VLANs,
runtime tap devices, or VM/container bridges on the i211 management pair.

Use the four Intel X553 ports for workload networking:

- `eno1`, `eno2`, `eno3`, `eno4`: workload trunk members.
- `br-ovs0`: Open vSwitch bridge.
- OVS bond: active LACP, 802.3ad on the switch side, `balance-tcp` on the OVS
  side.

The X553/OVS side is the intentional blast zone for Kata, Firecracker, QEMU,
LXC, Podman, VLAN, tap, and namespace testing. The i211 management side remains
the recovery path if OVS or workload networking breaks.

## NetBox Source Of Truth

Before workload network changes, NetBox should contain:

- the canary M70 device record, site, role, device type, and cabling placement
- hostname, FQDN, management IP, rack placement, and serial after discovery
- all six physical NIC interfaces, with MAC addresses where known
- `bond-mgmt` as the i211 management LAG intent
- `br-ovs0` and the X553 workload LAG/OVS intent
- switch-port cabling for all six Ethernet links
- serial console cabling once the RS232 path is physically installed and stable
- prefixes, VLANs, and service ownership for workload networks before assigning
  them to OVS

NetBox remains the source of truth. Local host inventory is evidence, not the
authority.

## Confirmed Physical Topology

The initial canary cabling plan uses CSS326 `ge19` through `ge24` for the six
M70 Ethernet links. Those links were operator-confirmed active on 2026-05-21
and verified by CSS326 SwOS snapshot `20260521T232928Z`:

- canary `netboot0`, PCI `0000:02:00.0`, MAC `00:07:32:58:73:34` to CSS326
  `ge19`
- canary `enp3s0`, PCI `0000:03:00.0` to CSS326 `ge20`
- canary `eno1` to CSS326 `ge21`
- canary `eno2` to CSS326 `ge22`
- canary `eno3` to CSS326 `ge23`
- canary `eno4` to CSS326 `ge24`

CRS354 `ether49` management must move from CSS326 `ge24` to CSS326 `ge15` to
free `ge24` for the canary workload LACP set. That move was physically
confirmed on 2026-05-21. NetBox cable `4` now records CSS326 `ge15` to CRS354
`ether49` as connected, and the structured inventory records Chonkers' former
CSS326 `ge15` connection as historical.

NetBox device `m70_canary` now has six physical Ethernet interfaces. NetBox
cables `5` through `10` record the CSS326 `ge19` through `ge24` links, and
cable `11` records AP7901 outlet 7 to the canary power input. The canary RS232
console should use the remaining spare M70 USB-hub RS232 path, with serial
console available for BIOS and iPXE repair after the exact path is identified.

## Validation Gates

1. Cable and inventory gate:
   - power, Ethernet, and RS232 are physically attached
   - NetBox device, interface, Ethernet-cable, and power-cable records exist
   - IP, hostname/FQDN, and serial-console records are added after discovery
   - `/dev/serial/by-id` is stable after the USB hub power change

2. Boot gate:
   - canary boots from `netboot0`
   - console remains reachable through the assigned RS232 path
   - primary Forge M70 remains reachable during canary failures

3. Management network gate:
   - post-boot management uses the approved i211 design
   - failover between management members is validated
   - management stays outside OVS

4. Workload LACP gate:
   - all four X553 links are up
   - switch LACP and OVS LACP agree
   - `br-ovs0` survives member loss and restoration

5. Runtime network gate:
   - QEMU tap path works
   - Firecracker tap path works, after Firecracker package source is selected
   - Kata path works, after Kata package source is selected
   - Podman/container path works
   - LXC or namespace path works if selected for the M70 profile

6. Promotion gate:
   - canary evidence is captured in the repo or linked issue/PR
   - no unresolved NetBox drift remains
   - boot, network, runtime, and rollback checks are documented
   - the same change can be promoted to primary Forge M70 or the rest of the
     M70 pool in rings

## Failure Handling

The canary may be rebooted or reimaged during testing. The primary Forge M70
should not depend on canary state.

If OVS, LACP, bridge, VLAN, tap, or runtime networking breaks, recover through
`netboot0`, the i211 management path, or the RS232 console. Do not debug by
moving workload networking onto the management pair.

During the USB serial hub power swap, treat all attached M70 serial paths as
temporarily unavailable. After power is stable, rescan `/dev/serial/by-id` and
update NetBox/docs if any stable adapter mapping changed.

## Open Decisions

- Exact canary hostname and management IP.
- Exact switch ports for the six Ethernet links.
- Whether the canary gets a local VM/container storage dataset on NVMe, a stage
  disk, or external storage.
- Firecracker package source: masked Gentoo binary ebuild or pinned upstream
  artifact.
- Kata package source: overlay, binary package path, or deferral.
