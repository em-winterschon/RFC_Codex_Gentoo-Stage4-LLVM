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
- Desired DHCP next-server after netboot offload: `172.16.99.88`
- Desired publisher: `boot-sun99-netboot-099088.rfc1918.host`
- Last fully observed historical path: TFTP `k10-ipxe.efi` from X12AGAIN
  `172.16.99.108`
- Optional console: rear DB9 RS232, pending validation for pre/post-bootloader
  redirection

## Firmware Policy

Use UEFI/EFI netboot paths only for x86/amd64 hosts. Do not add legacy BIOS
PXE support for K10, X12AGAIN, Hasslehoff, workstation, or server-class hosts.
U-Boot embedded systems are a separate future class and are not part of the
default network-boot design.

## Firmware Thermal Policy

The K10 is treated as a sustained-build host, not a bursty desktop. Firmware
tuning therefore prefers deterministic non-turbo behavior and stable thermals
without allowing the chassis fan to become louder than the larger X12-class
hosts.

Observed firmware identity on 2026-05-19:

- BIOS: Aptio Setup AMI `2.22.1289`
- BIOS version string: `NucBox K10`
- BIOS build date/time: `02/12/2025 13:51:57`
- EC firmware: `01.10`
- CPU: `13th Gen Intel Core i9-13900HK`
- Main page power preset observed before initial tuning: `Power Limit Select
  [Performance]`

Initial PiKVM OTG-HID thermal-recovery change on 2026-05-19:

- `Advanced -> Hardware Monitor -> Smart Fan -> PWM Control Fan Speed` changed
  from `OFF` to `100%`.
- `Advanced -> Power & Performance -> CPU - Power Management Control -> Turbo
  Mode` changed from `Enabled` to `Disabled`.
- This proved the host could hold base-clock package builds without thermal
  throttling, but the fixed fan speed was not acceptable as a sustained
  acoustic profile.

Balanced acoustic revision on 2026-05-19:

- `Main -> Power Limit Select` changed from `Performance` to `Balance`.
- `Advanced -> Hardware Monitor -> Smart Fan` changed to `Disabled`. The BIOS
  help text is counter-intuitive but explicit: `Enable` means manual fan speed
  setting, while `Disable` means automatic fan speed.
- `Advanced -> Power & Performance -> CPU - Power Management Control -> Turbo
  Mode` remained `Disabled`.
- CPU policy remained `Max Non-Turbo Performance` with platform PL1 `45000`,
  platform PL2 `54000`, and PL1 time window `28`.
- `Security -> Secure Boot` was verified `Disabled` and `Not Active`.
- `Chipset -> System Agent -> PCI Express Root Port 1/2/3 -> ASPM` was verified
  `Disabled`; `Chipset -> PCH-IO -> PCI Express Configuration -> DMI Link ASPM
  Control` was also verified `Disabled`.
- `Advanced -> AC Power Lost Policy` remained `Power on`.
- BIOS Hardware Monitor reported valid fan telemetry after the balanced
  revision: `CPU Fan Speed 3789 RPM` at about `36 C` to `37 C`.

Post-save validation from the live/netboot root after the balanced revision:

- Linux reports `/sys/devices/system/cpu/intel_pstate/no_turbo=1`.
- `lscpu` reports CPU max MHz capped at `2600.0000`.
- The netboot path remained intact and the host accepted SSH as `root` on
  `172.16.99.156`.
- A 180 second 20-process synthetic CPU load held the package temperature from
  `41 C` at start to a plateau of `68 C` to `69 C`, with max observed frequency
  around `2600007 kHz` and average observed frequency around `2320000 kHz`.
- No thermal throttling or machine-check events were observed in `dmesg` after
  the load test.
- Cooldown after load dropped package temperature from `53 C` to `45 C` over
  two minutes.

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
  network `next-server=172.16.99.88`
- TFTP handoff: Hasslehoff VM `1088`
  `boot-sun99-netboot-099088.rfc1918.host` serves
  `/var/lib/netboot/path-b` on `172.16.99.88:69` through the repo-managed
  OpenRC `netboot-tftp` service
- iPXE handoff: K10 fetched `hosts/gmktek-k10-stage5.ipxe`,
  generated `roles/workstation-validation.ipxe`, `g/vmlinuz`, and
  `g/initramfs-gz.img`
- Kernel handoff: K10 requires iPXE UEFI Linux boot with
  `initrd=initrd.magic` while the initramfs image is loaded under the normal
  `initramfs-gz.img` name. Generated roles must run `imgfree` before loading
  kernel/initramfs images; without it, iPXE can fetch kernel/initramfs but
  Linux never requests `rootfs.img`.
- HTTPBoot note: native UEFI HTTPBoot accepted DHCP only after option 60
  `HTTPClient`, but then failed to issue ARP/TCP toward `172.16.99.108`;
  PXE IPv4 is the active fallback because it did ARP and attempt TFTP
- Current status: on 2026-05-19, AP7901 outlet 6 PDU reboot validated the
  repo-generated `workstation-validation.ipxe` path from `172.16.99.88`: K10
  loads the patched initramfs, loads `rtl_nic/rtl8125b-2.fw`, fetches
  `g/rootfs.img`, mounts `LiveOS_rootfs`, switches root, and accepts SSH as
  `root` on `172.16.99.156`. The active publisher rootfs checksum is
  `23bfe6bb89aa4fae56345f995648ae2321956ba0e3d5e3b235b57159ea402a32`.
  OpenRC `net.enp4s0`, `netmount`, `sshd`, and `local` were started after
  boot. The pre-patch rollback rootfs is preserved on the publisher at
  `/var/lib/netboot/path-b/artifacts/gentoo-installer/rollback-20260519T143743Z/rootfs.img`.
- FreeIPA/SSSD status: K10 was transiently enrolled on the live Gentoo image as
  `gmktek-k10-stage5.rfc1918.host` on 2026-05-09. On 2026-05-11 the promoted
  Path B rootfs rebooted with SSSD, Samba, Kerberos, OpenLDAP, and
  `/usr/lib64/sssd/libsss_ipa.so` present. A post-boot
  `ipa-client-live-apply.yml` run then passed `sssctl config-check`, NSS lookup,
  FreeIPA SSH-key lookup, PAM account checks, and floating SSH login as
  `codex-admin`. On 2026-05-19, SSSD remained stopped after the stateless live
  root reboot; durable AAA remains gated on secure firstboot or installed-disk
  enrollment because public netboot artifacts must not embed host keytabs.
- Installed-disk boot status: on 2026-05-18, K10 completed the netboot installer
  and created a ZFSBootMenu UEFI entry for the mirrored `rpool`. The first
  installed-disk boot reached dracut but failed before networking with repeated
  `ZFS: Unable to import pool rpool` and `No sysroot.mount exists` messages on
  the PiKVM capture. Root cause was boot-role command-line handling: the
  ZFSBootMenu dataset property lost the required `root=ZFS=rpool/ROOT/gentoo`
  token, so dracut's ZFS generator had no root target. The repo fix preserves
  `root=ZFS=...` and writes the ZFSBootMenu property through argv-safe
  `zfs set`. On 2026-05-19, while booted through live rescue, the installed
  pool was imported and both `rpool/ROOT` and `rpool/ROOT/gentoo` were corrected
  to `root=ZFS=rpool/ROOT/gentoo ro console=tty0 console=ttyS0,115200
  spl_hostid=075156b1`.
- Installed-disk boot caveat: after saving firmware changes on 2026-05-19, the
  machine still preferred the iPXE/live netboot path. A local-disk boot through
  ZFSBootMenu remains the next gate to prove the corrected dataset command line.
- AAA durability caveat: the netboot rootfs is fetched over unauthenticated HTTP
  and must not embed `/etc/krb5.keytab`. The current safe model is package
  durability in the rootfs plus post-boot secure enrollment. Fully unattended
  reboot-durable enrollment requires disk install or
  `stage5-firstboot-enroll` consuming an age-encrypted FreeIPA host OTP bundle
  so `/etc/krb5.keytab` is generated on the target.
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
- Rebuild invocation: the Path B artifact builder now consumes profile
  definitions directly. For the K10 AAA-capable rootfs, run with the
  whitespace-separated shell list
  `PATHB_PROFILE_DEFINITION_FILES="profile-definitions/aaa-domain-client.yml profile-definitions/secure-firstboot-enrollment.yml"`
  plus `PATHB_REUSE_INITRAMFS_NETWORK=0`,
  `PATHB_STATIC_INTERFACE=enp4s0`,
  `PATHB_STATIC_ADDRESS_CIDR=172.16.99.156/24`,
  `PATHB_STATIC_GATEWAY=172.16.99.1`, and
  `PATHB_STATIC_DNS="172.16.99.63 172.16.99.1 9.9.9.9"`
  so `sys-auth/sssd`, `net-fs/samba`, the SSSD/Samba package USE policy,
  `app-crypt/age`, `curl`, `jq`, the `sssd` OpenRC service, and the opt-in
  secure first-boot enrollment scaffold are carried into the generated rootfs
  instead of applied only as live mutations. The static OpenRC networking
  variables are required because the live root must not depend on dracut
  preserving the initramfs-assigned address after switchroot. Do not embed host
  keytabs in the public netboot artifact set.
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
   `k10-ipxe.efi` and `next-server=172.16.99.88`.
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
11. Validate SSH, rsyslog, telemetry, and SSSD client enrollment. The K10
    Path B rootfs now includes the `aaa-domain-client` package layer and passes
    post-boot FreeIPA/SSSD apply, but unattended enrollment durability still
    requires disk install or secure first-boot age-encrypted FreeIPA OTP bundle
    delivery plus hostname, offline cache, sudo policy, and break-glass
    behavior validation.
12. Snapshot/capture final package and Portage state before considering X12AGAIN.

## E2ET Rebuild Timing Sequence

Use this timing model when K10 is rebuilt as the bare-metal E2ET candidate:

1. Pre-change capture: confirm RouterOS static lease, AP7901 outlet mapping,
   NetBox device/interface/IPAM data, and current publisher artifact checksums.
2. Image build: run the Path B artifact builder with
   `PATHB_PROFILE_DEFINITION_FILES="profile-definitions/aaa-domain-client.yml profile-definitions/secure-firstboot-enrollment.yml"`
   and the static OpenRC network builder variables from the rebuild source of
   truth above.
   Expected duration depends on binpkg cache state; record start, finish, and
   elapsed wall time in the E2ET log.
3. Publish: sync kernel, initramfs, rootfs, iPXE host script, and generated role
   script to `boot-sun99-netboot-099088.rfc1918.host:/var/lib/netboot/path-b`.
4. Power cycle: use AP7901 outlet 6 only after the publisher has the complete
   artifact set and RouterOS still advertises `next-server=172.16.99.88`.
5. Firmware and iPXE gates: validate DHCP, TFTP `k10-ipxe.efi`, host iPXE
   script fetch, kernel fetch, initramfs fetch, Realtek firmware load, and
   rootfs fetch in order. Stop on the first missing handoff.
6. Rootfs smoke: validate SSH as root, hostname intent, OpenRC state, network
   route, DNS, NTP/chrony readiness, rsyslog readiness, and exporter readiness.
7. AAA smoke: validate package presence, SSSD config, NSS lookup, PAM account,
   FreeIPA SSH-key lookup, and floating SSH for `codex-admin`.
8. Durable enrollment gate: netboot-only evidence is insufficient. Mark the
   durable E2ET gate complete only after disk install or another persistent
   identity path proves `/etc/krb5.keytab`, SSSD cache, hostname, sudo policy,
   and break-glass behavior survive a power-cycle.
9. Installed-disk boot gate: confirm the ZFSBootMenu-selected kernel command
   line includes `root=ZFS=rpool/ROOT/gentoo`, `ro`, `console=tty0`,
   `console=ttyS0,115200`, and `spl_hostid=<target-hostid>`. A dracut boot that
   reaches `No sysroot.mount exists` is a hard fail for this gate.
10. Conformance report: write pass/fail, timings, artifact IDs, package profile
   IDs, and observed deviations before any X12AGAIN reimage action.

## Backout

Do not modify X12AGAIN until the K10 has completed the install and workstation
GPU validation path. If K10 provisioning fails, leave X12AGAIN untouched and use
the VM workstation path for package policy refinement.
