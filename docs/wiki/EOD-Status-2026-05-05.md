# EOD Status 2026-05-05

## Completed

- Added Hasslehoff GPU host policy scaffolding for the installed NVIDIA Quadro
  K1200:
  - blacklists `nouveau`, `nvidiafb`, and `snd_hda_intel`
  - stages `vfio-pci` binding for GPU functions `10de:13bc` and `10de:0fbc`
  - supports Proxmox `/etc/kernel/cmdline` management without forcing a live
    boot-tool refresh by default
- Added a plan-only Proxmox VE 8 maintenance-upgrade role with Debian
  `bookworm` and PVE `8.x` guards.
- Added gated NVIDIA DOCA/OFED scaffolding for future ConnectX-5/RoCE hosts.
  The role does not install drivers unless explicitly enabled and applied.
- Documented the Hasslehoff QLogic QL41232HOCU to CRS309 LACP cabling plan.
- Validated both QLogic 10G-SR links after replacing a failed optic:
  - `enp4s0f0` to CRS309 `sfp-sfpplus4`
  - `enp4s0f1` to CRS309 `sfp-sfpplus5`
- Confirmed both QLogic links are `10Gbps`, full-duplex, with clean host and
  CRS309-side error counters.
- Identified and fixed the RouterOS serial automation issue. RouterOS sends an
  `ESC Z` terminal-identification probe after login; raw scripts must answer
  with a VT100/ANSI terminal response before command execution continues.
- Added `scripts/routeros-serial-command.py` and a regression test covering the
  RouterOS terminal answerback behavior.
- Validated the new serial helper live against CRS309 using read-only
  `/system identity print`.

## Current Gates

- CRS309 `bond-hasslehoff-qlogic` is rendered but not imported live yet.
- Hasslehoff does not yet have the persistent QLogic host-side `802.3ad` bond
  and bridge/VLAN plan applied.
- QLogic SR-IOV VFs are not enabled yet; VF count, persistent sysfs handling,
  and Proxmox passthrough mapping remain next.
- Hasslehoff GPU passthrough policy is repo-defined, but final host mutation,
  boot-tool refresh, and reboot remain a maintenance-window action.
- The Stage4 Workstation VM has a QEMU-first NsCDE profile path in the repo, but
  the Hasslehoff GPU/SR-IOV Proxmox deployment is still pending.

## Outstanding Actions

1. Import the CRS309 QLogic LACP intent after a fresh serial-backed backup.
2. Create the Hasslehoff Linux bond for `enp4s0f0` and `enp4s0f1` with
   `802.3ad`, fast LACP, `miimon=100`, and `layer3+4` hashing.
3. Decide whether the QLogic bond is bridge-only, VLAN-aware, or partially
   direct-path with VFs for workstation/test workloads.
4. Enable QLogic SR-IOV only after documenting VF persistence and rollback.
5. Create the Hasslehoff Stage4 Workstation VM with:
   - normal management NIC on the existing 1GbE LACP bridge
   - GPU passthrough for K1200 VGA and audio functions
   - one QLogic VF from each physical port
   - serial console and kernel command line `console=tty0 console=ttyS0`
6. Install and validate workstation profile packages, Xorg/NsCDE, NVIDIA driver,
   and CUDA utility visibility from inside the guest.

## Backout Summary

The QLogic physical links can be backed out by leaving `enp4s0f0/enp4s0f1`
administratively down or removing the CRS309 LACP import before host bond
creation. GPU passthrough backout is to remove `vfio-pci.ids` and driver
blacklist tokens from the Proxmox kernel command line, refresh boot tooling, and
reboot Hasslehoff during a controlled window.

## Next Work Block

Proceed with the Hasslehoff workstation deployment in gated order:

1. Apply CRS309 QLogic LACP.
2. Apply Hasslehoff QLogic bond and bridge/VLAN foundation.
3. Enable and validate SR-IOV VFs.
4. Apply GPU passthrough host policy and reboot if required.
5. Provision the Stage4 Workstation VM and validate serial boot, GPU visibility,
   VF visibility, management reachability, Xorg/NsCDE, NVIDIA driver, and CUDA
   utilities.
