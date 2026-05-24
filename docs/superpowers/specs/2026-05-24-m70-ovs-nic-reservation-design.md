# M70 OVS NIC Reservation Design

## Purpose

M70 `admin-sun99-forge-099070` needs a clean split between stable automation-admin reachability and future packet-processing/Slurm virtualization work. The approved target uses the two Intel i211 ports for the persistent management LACP bond and reserves the four Intel X553 ports for Open-vSwitch with DPDK, VPP, SR-IOV/IOMMU work, and a lightweight Slurm VM.

## Current State

Live validation on 2026-05-24 showed `netboot0` at PCI `0000:02:00.0` using the `igb` driver with MAC `00:07:32:78:65:c6`. It owns `172.16.99.70/24` and the default route. `enp3s0` at PCI `0000:03:00.0` is the second Intel i211 port and currently participates in `bond0`. `eno1` at PCI `0000:06:00.0` is an Intel X553 port and currently also participates in `bond0`. `eno2` had `10.64.64.70/24`; that address was removed live and must not be persisted. `eno3` and `eno4` are X553 ports and should stay unaddressed until OVS-DPDK/VPP owns them.

## Target State

Persistent management target:

- `bond0`: `netboot0 + enp3s0`
- Bond mode: 802.3ad
- LACP rate: fast
- Hash policy: `layer3+4`
- Management address: `172.16.99.70/24`
- Default route: `172.16.99.1`
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

If the cutover fails, restore CSS326 LACP group 2 to `ge17/ge18`, restore `/etc/conf.d/net` so `netboot0` owns `172.16.99.70/24` and the default route, restart `net.netboot0`, and validate SSH to `172.16.99.70` before disabling `bond0`.
