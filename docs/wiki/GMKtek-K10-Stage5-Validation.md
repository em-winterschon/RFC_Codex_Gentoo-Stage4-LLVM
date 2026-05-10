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
- iPXE/PXE NIC slot: `04:00:00`
- iPXE NIC MAC: `84:47:09:5F:21:64`
- Firmware target: UEFI PXE to iPXE EFI
- DHCP lease: static RouterOS lease `172.16.99.156`
- Dracut network: static `172.16.99.156/24` via `172.16.99.1` during the
  live-root fetch phase
- DHCP client class: `PXEClient:Arch:00007:UNDI:003016`
- HTTPBoot class observed: `HTTPClient:Arch:00016:UNDI:003016`
- DHCP next-server: `172.16.99.108`
- EFI handoff: TFTP `k10-ipxe.efi` from `172.16.99.108`
- Optional console: rear DB9 RS232, pending validation for pre/post-bootloader
  redirection

## Firmware Policy

Use UEFI/EFI netboot paths only for x86/amd64 hosts. Do not add legacy BIOS
PXE support for K10, X12AGAIN, Hasslehoff, workstation, or server-class hosts.
U-Boot embedded systems are a separate future class and are not part of the
default network-boot design.

## Intake State

The local Ansible inventory carries a placeholder host:

- `gmktek_nucbox_k10_stage5_candidate`
- role: `ipxe-stage5-validation-host`
- status: `pending-ipxe-validation`

Current physical discovery state:

- Connected test port: CSS326 `ge16`
- Expected boot path: UEFI PXE/TFTP to iPXE
- Observed status: DHCP requests from `84:47:09:5F:21:64` reached `eno1`, and
  `172.16.99.1` offered `172.16.99.156` during the 2026-05-07 reboot window
- DHCP handoff: RouterOS static lease now scopes option 67 `k10-ipxe.efi` and
  network `next-server=172.16.99.108`
- TFTP handoff: on-host listener serves `/var/lib/netboot/path-b` on
  `172.16.99.108:69`; local TFTP fetch of `k10-ipxe.efi` has been validated
- iPXE handoff: K10 fetched `hosts/gmktek-k10-stage5.ipxe`,
  `roles/installer-k10.ipxe`, `g/vmlinuz`, and `g/initramfs-gz.img`
- Kernel handoff: K10 requires iPXE UEFI Linux boot with
  `initrd=initrd.magic`; direct `boot vmlinuz` or a non-magic initrd argument
  causes the kernel to miss dracut and panic on `root=live:http://...`.
- HTTPBoot note: native UEFI HTTPBoot accepted DHCP only after option 60
  `HTTPClient`, but then failed to issue ARP/TCP toward `172.16.99.108`;
  PXE IPv4 is the active fallback because it did ARP and attempt TFTP
- Current status: K10 loads the patched initramfs, loads
  `rtl_nic/rtl8125b-2.fw`, fetches `g/rootfs.img` from
  `http://172.16.99.108:8080`, mounts `LiveOS_rootfs`, switches root, and
  reaches the Gentoo login prompt on the PiKVM video console.
- FreeIPA/SSSD status: K10 was transiently enrolled on the live Gentoo image as
  `gmktek-k10-stage5.rfc1918.host` on 2026-05-09. The live validation gates
  passed for the IPA backend module, `sssctl config-check`, NSS lookup,
  FreeIPA SSH-key lookup, PAM account checks, and floating SSH login as
  `codex-admin` before reboot. A later AP7901 outlet 6 PDU reboot proved this
  is not yet reboot-durable because the original netboot rootfs returned
  without SSSD or `/usr/lib64/sssd/libsss_ipa.so`.
- SSSD package policy: the active Gentoo client requires `sys-auth/sssd samba`
  and `net-fs/samba winbind`; without those flags, the IPA provider module
  `/usr/lib64/sssd/libsss_ipa.so` is missing.
- Live-image caveat: the booted live root still reports `hostname -f` as
  `gentoo-pathb`, and system D-Bus is not running by default. The live
  validation therefore treats `sssctl domain-status` as advisory if the failure
  is exactly `Unable to connect to system bus` and the stronger NSS, SSH, PAM,
  backend-module, and config-check gates pass.
- Rebuild source of truth:
  `gentoo-liveiso-ansible/netboot-image-manifests/k10-stage5-workstation.yml`
  records the kernel, initramfs, rootfs, dracut firmware requirements, static
  command line, and Jenkins rebuild inputs for this K10 boot image.
- Dracut DHCP note: in-initramfs DHCP repeatedly failed despite RouterOS
  working for firmware/iPXE. The active K10 installer role uses the reserved
  static initramfs address instead.
- PDU control: AP7901 outlet 6 is mapped to `host_gmktec_k10`; SNMPv3
  credentials are staged in the Ansible vault from
  `/root/.ssh/codex.d/tokens/PDU_RFC99_CORECTRL` and must not be committed in
  plaintext.
- Exclusion: `172.16.99.160` is not accepted as K10 evidence because it showed
  conflicting ARP/MAC data and an existing OpenSSH/rpcbind host

Once the host requests DHCP, record:

- DHCP lease IP
- firmware boot mode
- serial console behavior

## Validation Gates

1. Reboot K10 with UEFI PXE IPv4 and confirm DHCP offer includes option 67
   `k10-ipxe.efi` and `next-server=172.16.99.108`.
2. Confirm firmware fetches `k10-ipxe.efi` over TFTP.
3. Confirm embedded iPXE fetches `hosts/gmktek-k10-stage5.ipxe`.
4. Confirm EFI/iPXE attaches and executes `g/initramfs-gz.img`.
5. Confirm patched initramfs loads Realtek 8125 firmware and fetches the rootfs
   using the static dracut IP assignment.
6. Create NetBox device, interface, MAC, IPAM, and DNS records.
7. Boot iPXE and confirm kernel/initramfs/rootfs delivery.
8. Install LOX Stage4 plus Stage5 workstation profile using binpkgs where
   possible.
9. Validate Xorg-only policy: no Wayland/Xwayland path should be required.
10. Validate Intel display stack: Mesa, libdrm, libva, Vulkan loader/tools, and
    Xorg driver behavior.
11. Validate SSH, rsyslog, telemetry, and SSSD client enrollment. The transient
    live FreeIPA/SSSD enrollment gate passed on 2026-05-09, but reboot-durable
    Stage5 still must include `aaa-domain-client` in the rootfs or disk install
    and persist hostname, offline cache, sudo policy, and break-glass behavior.
12. Snapshot/capture final package and Portage state before considering X12AGAIN.

## Backout

Do not modify X12AGAIN until the K10 has completed the install and workstation
GPU validation path. If K10 provisioning fails, leave X12AGAIN untouched and use
the VM workstation path for package policy refinement.
