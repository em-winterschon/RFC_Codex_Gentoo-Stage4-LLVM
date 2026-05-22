# M70 Canary Persistent Gentoo Stage4 Install

**Goal:** Convert `m70_canary` from the old HBSD/FreeBSD state into a persistent
Gentoo Stage4 M70 canary that boots locally, keeps iPXE as rescue/install only,
and carries the approved i211 management plus X553 OVS/LACP workload design.

## Design Commitments

- Installed hostname: `sbsoc-accel-int64-m70n2`
- Management IP: `172.16.99.22/24`
- Netboot MAC: `00:07:32:58:73:34`
- Persistent boot: local EFI ZFSBootMenu
- Install disks: KIOXIA NVMe EUI `8ce38e0403ef1a38` and
  `8ce38e0403ef1adf`
- Excluded disk: SATA-DOM serial `20180915AA9241033080`
- Management network: `bond-mgmt` active-backup over `netboot0` and `enp3s0`
- Workload network: `br-ovs0` plus OVS LACP bond `ovs-workload0` over
  `eno1` through `eno4`
- Recovery: serial console
  `/dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if01-port0`

## Execution Steps

1. Repo source of truth:
   - Add `m70_canary` to local-network install and validation groups.
   - Add persistent host vars for storage, boot, FreeIPA, SLURM, distcc, and
     NetworkManager connection state.
   - Add M70-specific netboot role with approved DNS resolvers only.
   - Extend the NetworkManager template for bond and OVS keyfiles.

2. NetBox source of truth:
   - Add discovered MACs for `enp3s0` and `eno1` through `eno4`.
   - Move the management IP intent to `bond-mgmt`.
   - Add logical `bond-mgmt`, `br-ovs0`, and `ovs-workload0` interfaces.
   - Record the identified canary serial console path.

3. Netboot publish:
   - Validate DNS policy for netboot manifests and role command lines.
   - Publish Path B host script `m70-canary.ipxe`.
   - Confirm `hosts/by-mac.ipxe` dispatches MAC `00:07:32:58:73:34` to the
     M70 canary install role.
   - Current live blocker: 2026-05-22 RS232 firmware work set Network first,
     enabled CSM, enabled Launch PXE ROM, and kept UEFI mode, but a reset still
     returned to Aptio Setup and `tcpdump` saw no DHCP/PXE packets from
     `00:07:32:58:73:34`.

4. Boot canary into Gentoo installer:
   - Reboot only `m70_canary`.
   - Watch RS232 for iPXE/Gentoo installer state.
   - Confirm SSH to `root@172.16.99.22` from the installer environment.
   - Do not continue to destructive install until the firmware exposes a real
     UEFI network boot target for the i211 `netboot0` path or another approved
     installer boot method is attached.

5. Destructive install preflight:
   - Confirm `/dev/disk/by-id/nvme-eui.8ce38e0403ef1a38` exists.
   - Confirm `/dev/disk/by-id/nvme-eui.8ce38e0403ef1adf` exists.
   - Confirm the SATA-DOM is absent from `storage_devices`.
   - Confirm UEFI runtime is present.

6. Persistent install:
   - Run the full default install sequence limited to `m70_canary`.
   - Leave `finalize_reboot_host=false` for an operator-visible reboot gate.
   - Capture control-flow evidence.

7. First local boot:
   - Boot from local ZFSBootMenu, not iPXE.
   - Confirm `bond-mgmt` owns `172.16.99.22/24`.
   - Confirm SSH, hostname, FreeIPA baseline, and serial access.

8. Workload networking:
   - Validate X553 link state from Linux.
   - Configure/validate switch-side LACP before relying on `ovs-workload0`.
   - Confirm OVS LACP state and member failure behavior.

9. Runtime gates:
   - Validate QEMU tap, Podman network, Firecracker tap, Kata, and SLURM worker
     enrollment independently.
   - Reconcile any observed NetBox drift before promotion to additional M70s.
