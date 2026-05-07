# GMKtek K10 Stage5 Validation

## Purpose

Use the GMKtek NucBox K10 as the low-blast-radius bare-metal validation target
before reimaging X12AGAIN with the LOX Stage4 plus Stage5 workstation profile.

## Hardware Facts

- Model: GMKtek NucBox K10
- CPU: Intel Core i9-13900HK
- Cores/threads: 14 cores / 20 threads
- GPU: Intel Iris Xe
- Memory: DDR5 SO-DIMM, operator-installed size to be observed
- Network: 2.5GbE RJ45
- iPXE NIC slot: `04:00:00`
- iPXE NIC MAC: `84:47:09:5F:21:64`
- Firmware target: UEFI iPXE
- Optional console: rear DB9 RS232, pending validation for pre/post-bootloader
  redirection

## Intake State

The local Ansible inventory carries a placeholder host:

- `gmktek_nucbox_k10_stage5_candidate`
- role: `ipxe-stage5-validation-host`
- status: `pending-ipxe-validation`

Current physical discovery state:

- Connected test port: CSS326 `ge16`
- Expected boot path: UEFI PXE/iPXE
- Observed status: DHCP requests from `84:47:09:5F:21:64` reached `eno1`, and
  `172.16.99.1` sent DHCP replies during the 2026-05-07 reboot window
- Blocker: no confirmed lease IP or successful iPXE asset fetch has been
  observed yet
- Exclusion: `172.16.99.160` is not accepted as K10 evidence because it showed
  conflicting ARP/MAC data and an existing OpenSSH/rpcbind host

Once the host requests DHCP, record:

- DHCP lease IP
- firmware boot mode
- serial console behavior

## Validation Gates

1. Confirm DHCP lease IP for MAC `84:47:09:5F:21:64`.
2. Create NetBox device, interface, MAC, IPAM, and DNS records.
3. Add a RouterOS DHCP reservation for the iPXE validation address.
4. Boot iPXE and confirm kernel/initramfs delivery.
5. Install LOX Stage4 plus Stage5 workstation profile using binpkgs where
   possible.
6. Validate Xorg-only policy: no Wayland/Xwayland path should be required.
7. Validate Intel GPU stack: Mesa, Vulkan loader/tools, Level Zero, OpenCL, and
   `clinfo` where supported.
8. Validate SSH, rsyslog, telemetry, and optional SSSD client enrollment.
9. Snapshot/capture final package and Portage state before considering X12AGAIN.

## Backout

Do not modify X12AGAIN until the K10 has completed the install and workstation
GPU validation path. If K10 provisioning fails, leave X12AGAIN untouched and use
the VM workstation path for package policy refinement.
