# M70 OVS NIC Reservation Design

## Purpose

M70 `admin-sun99-forge-099070` needs a clean split between stable automation-admin reachability and future packet-processing/Slurm virtualization work. The approved target uses the two Intel i211 ports for the persistent management LACP bond and reserves the four Intel X553 ports for Open-vSwitch with DPDK, VPP, SR-IOV/IOMMU work, and a lightweight Slurm VM.

## Current State

Live validation on 2026-05-24 showed `netboot0` at PCI `0000:02:00.0` using the `igb` driver with MAC `00:07:32:78:65:c6`. The live cutover moved `172.16.99.70/24` and the default route from `netboot0` to `bond0`. `bond0` now contains `netboot0 + enp3s0` in `active-backup` mode with `netboot0` as the primary active slave. `openvpn.fmt2` is back up after the OpenRC network bounce and FMT2 routes are restored through `tun-fmt2`.

`eno1..eno4` are Intel X553 ports reserved for OVS-DPDK/VPP/SR-IOV and remain unnumbered. CCR2004 bridge FDB validation learned `eno1` on `ge3`, `eno2` on `ge4`, `eno3` on `ge5`, and `eno4` on `ge6`. `eno2` no longer has `10.64.64.70/24`; that address must not be restored.

## Target State

Current persistent management target:

- `bond0`: `netboot0 + enp3s0`
- Bond mode: `active-backup`
- Primary slave: `netboot0`
- Management address: `172.16.99.70/24`
- Default route: `172.16.99.1`

Deferred management throughput target:

- Bond mode: 802.3ad after CSS326 SwOS LACP mutation is tested
- LACP rate: fast
- Hash policy: `layer3+4`
- CSS326 LACP member ports: `ge14 + ge17`

Reserved packet-processing target:

- `eno1`: X553, PCI `0000:06:00.0`, MAC `00:07:32:78:65:C8`, target CCR2004 `ge3`
- `eno2`: X553, PCI `0000:06:00.1`, MAC `00:07:32:78:65:C9`, target CCR2004 `ge4`
- `eno3`: X553, PCI `0000:07:00.0`, MAC `00:07:32:78:65:CA`, target CCR2004 `ge5`
- `eno4`: X553, PCI `0000:07:00.1`, MAC `00:07:32:78:65:CB`, target CCR2004 `ge6`

The initramfs boot path still uses `netboot0` by name for iPXE and ZFS-root bootstrapping. The persistent OpenRC root can then enslave `netboot0` into `bond0` and move the service address to `bond0`.

## Cutover Boundary

This design is repo-side source-of-truth and runbook work. It must not perform a live M70 network cutover by itself. The live cutover needs LTC Forge coordination with Forge-Root on M70 because losing M70 also interrupts USB serial, UPS telemetry, RouterOS console access, and the temporary FMT2 OpenVPN transport.

## Backout

For the current `active-backup` live state, restore `/root/m70-net-pre-bond0-cutover.conf.<timestamp>` to `/etc/conf.d/net`, stop `net.bond0`, start `net.netboot0`, and validate SSH to `172.16.99.70`. CSS326 LACP backout is only needed after a future 802.3ad change mutates switch-side LACP membership.
