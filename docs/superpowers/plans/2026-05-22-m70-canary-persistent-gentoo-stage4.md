# M70 Canary Persistent Gentoo Stage4 Install

**Goal:** Convert `m70_canary` from the old HBSD/FreeBSD state into a persistent
Gentoo Stage4 M70 canary that boots locally, keeps iPXE as rescue/install only,
and carries the approved i211 management plus X553 OVS/LACP workload design.

## Design Commitments

- Installed hostname: `sbsoc-accel-int64-m70n2`
- Management IP: `172.16.99.22/24`
- Netboot MAC: `00:07:32:58:73:34`
- Persistent boot: local EFI ZFSBootMenu via removable-path fallback first,
  with NVRAM entry creation deferred until the host is booted in UEFI mode
- Install disks: KIOXIA NVMe EUI `00000000000000008ce38e0403ef1a38` and
  `00000000000000008ce38e0403ef1adf`
- Excluded disk: SATA-DOM serial `20180915AA9241033080`
- Management network: `bond_mgmt` balance-alb over `netboot0` and `enp3s0`
- Workload network: `br_ovs0` plus OVS LACP bond `ovs_workload0` over
  `eno1` through `eno4`
- Network renderer: OpenRC/netifrc plus Open vSwitch; NetworkManager is masked
  for this host.
- Build gate: compile work must use distcc with X12again
  `172.16.99.108/48,lzo,cpp`; seed the distcc client from the local binpkg
  cache before any compile-heavy Portage stage.
- Recovery: serial console
  `/dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if01-port0`

## Execution Steps

1. Repo source of truth:
   - Add `m70_canary` to local-network install and validation groups.
   - Add persistent host vars for storage, boot, FreeIPA, SLURM, distcc, and
     OpenRC/netifrc plus OVS network state.
   - Add M70-specific netboot role with approved DNS resolvers only.
   - Extend the network role for netifrc bond rendering and an OpenRC OVS
     fabric apply service.

2. NetBox source of truth:
   - Add discovered MACs for `enp3s0` and `eno1` through `eno4`.
   - Move the management IP intent to `bond_mgmt`.
   - Add logical `bond_mgmt`, `br_ovs0`, and `ovs_workload0` interfaces.
   - Record the identified canary serial console path.

3. Netboot publish:
   - Validate DNS policy for netboot manifests and role command lines.
   - Publish Path B host script `m70-canary.ipxe`.
   - Confirm `hosts/by-mac.ipxe` dispatches MAC `00:07:32:58:73:34` to the
     M70 canary install role.
   - 2026-05-23 update: UEFI network boot still produced no DHCP/PXE traffic
     from `00:07:32:58:73:34`, but legacy `Network:IBA GE Slot 0200 v1543`
     successfully booted through a temporary iPXE shim.

4. Boot canary into Gentoo installer:
   - Reboot only `m70_canary`.
   - Watch RS232 for iPXE/Gentoo installer state.
   - Confirm SSH to `root@172.16.99.22` from the installer environment.
   - Because the working installer path is legacy PXE, do not require runtime
     efivars or create an EFI NVRAM entry during install. The boot role must
     install the ZFSBootMenu removable fallback at `EFI/BOOT/BOOTX64.EFI`, and
     firmware can be returned to UEFI/local disk boot after the disk image is
     written.
   - Gentoo provides AMD microcode through `sys-kernel/linux-firmware`; keep
     `sys-firmware/intel-microcode` explicit for Intel early microcode and do
     not use the nonexistent `sys-firmware/amd-ucode` atom.
   - The earlier `gentoo-kernel-6.18.18` pin has aged out of the current tree;
     the canary pin is `=sys-kernel/gentoo-kernel-6.18.32_p2` with
     `=sys-fs/zfs-2.3.6` and `=sys-fs/zfs-kmod-2.3.6`.

5. Destructive install preflight:
   - Confirm `/dev/disk/by-id/nvme-eui.00000000000000008ce38e0403ef1a38` exists.
   - Confirm `/dev/disk/by-id/nvme-eui.00000000000000008ce38e0403ef1adf` exists.
   - Confirm the SATA-DOM is absent from `storage_devices`.
   - Confirm `preflight_require_runtime_uefi=false` and
     `boot_create_efi_nvram_entry=false` are set when the installer was booted
     through legacy PXE.

6. Persistent install:
   - Before package installation, configure the local binpkg seed and distcc
     host list, then install `sys-devel/distcc` from binpkg.
   - Defer `dev-util/ccache` until there is a matching binpkg or an explicit
     configure/link-probe policy; it is not part of the canary bootstrap gate.
   - Run the full default install sequence limited to `m70_canary`.
   - Leave `finalize_reboot_host=false` for an operator-visible reboot gate.
   - Capture control-flow evidence.

7. First local boot:
   - Boot from local ZFSBootMenu, not iPXE.
   - Confirm `bond_mgmt` owns `172.16.99.22/24`.
   - Confirm SSH, hostname, FreeIPA baseline, and serial access.

8. Workload networking:
   - Validate X553 link state from Linux.
   - Configure/validate switch-side LACP before relying on `ovs-workload0`.
   - Confirm OVS LACP state and member failure behavior.

9. Runtime gates:
   - Validate QEMU tap, Podman network, Firecracker tap, Kata, and SLURM worker
     enrollment independently.
   - Reconcile any observed NetBox drift before promotion to additional M70s.
