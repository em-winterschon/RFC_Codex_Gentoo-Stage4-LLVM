# M70 Forge Automation Admin

## Purpose

The first M70 node becomes the replacement automation-admin host before
X12AGAIN/Prinzessin is reimaged. Its job is to run Codex/Forge workflows,
Ansible, GitHub CLI, vault tooling, infrastructure validation, and X12AGAIN SoL
access from a stable installed system instead of the long-lived X12AGAIN live
environment.

## Reserved Identity

| Field | Value |
| --- | --- |
| Inventory key | `admin_sun99_forge_099070` |
| FQDN | `admin-sun99-forge-099070.rfc1918.host` |
| Alias | `admin-sun99-forge.rfc1918.host` |
| Address | `172.16.99.70/24` |
| Gateway | `172.16.99.1` |
| Persistent management interface | `bond0` |
| Initramfs/netboot interface | `netboot0` |
| Primary MAC | `00:07:32:78:65:C6` |
| Management bond switch ports | `sw_mgmt_css326 ge14` and `ge17` |
| PDU outlet | `pdu-rfc99-corectrl-099241 outlet 4` |
| PDU outlet label | `admin-sun99-forge` |
| Serial console | Currently unavailable after USB serial hub move; attach separate external OOB before relying on M70 serial recovery |
| Stage5 profile | `metal-forge-automation-admin` |

## Provisioning Plan

The M70 is tracked as a UEFI-only `pxe-to-ipxe` install target. RouterOS desired
state reserves a static DHCP lease for `172.16.99.70` and sends boot file
`m70-forge-ipxe.efi` from the SUN99 netboot publisher at `172.16.99.88`.

The current first-stage binary is the M70-specific
`/opt/gentoo-netboot/path-b/m70-forge-ipxe-172.16.99.88-ipxe.efi` artifact,
published as `m70-forge-ipxe.efi`.

Live validation on 2026-05-13 found that the firmware can put `Network` first
in the fixed UEFI boot order, but did not expose a usable UEFI PXE NIC entry.
The operational workaround is a local SATADOM ESP chainloader: the original
BSDRP `BOOTX64.EFI` was backed up on the ESP, then replaced with the
M70-specific iPXE binary. That path successfully DHCPs, chains
`hosts/admin-sun99-forge-099070.ipxe`, downloads the Gentoo kernel/initramfs and
`rootfs.img`, and reaches SSH at `172.16.99.70`.

The follow-up reboot validation also passed with the corrected dracut interface
name: `bootdev=netboot0`, `ifname=netboot0:00:07:32:78:65:c6`, and static
`ip=...:netboot0:none`. The initramfs boot path still uses `netboot0`; the
approved persistent target is to move `172.16.99.70/24` onto `bond0` after the
root filesystem is online.

On 2026-05-13 a later reachability check found `172.16.99.70` not answering
ARP from X12AGAIN or Hasslehoff while CSS326 `ge14` still reported link up and
the serial console was at a live Linux login prompt. A PDU outlet-4 reboot
restored iPXE chainload and SSH. Post-boot evidence showed `netboot0` up with
`172.16.99.70/24`, default route via `172.16.99.1`, `sshd` running, `dhcpcd`
marked crashed, hostname still `gmktek-k10-stage5`, and `sssd` stopped due to a
missing `/etc/sssd/sssd.conf`. Treat this as a live-rootfs profile durability
defect, not an SSH source filter or switch/VLAN defect.

On 2026-05-14 the live M70 FreeIPA enrollment was repaired and validated.
FreeIPA had created the host object without `krbprincipalname`, which caused
`ipa-getkeytab` to fail with `PrincipalName not found`; adding the canonical
host principal through `ipa host-mod` resolved keytab generation. The live apply
now sets the OpenRC hostname files, forces the active kernel hostname, removes
the stale K10 `/etc/hosts` fallback, starts SSSD, validates NSS/PAM/SSH lookup
for `codex-admin`, and confirms the host keytab exists. The persistent ZFS
install was later re-applied with the same playbook after the admin tool
baseline finished; `/etc/krb5.keytab`, `/etc/sssd/sssd.conf`, NSS/PAM, SSSD
SSH authorized-key lookup, and `codex-admin` non-root SSH now validate on the
persistent root.

## Network Target State

On 2026-05-24 the approved M70 networking target was revised:

| Interface | PCI | Driver | MAC | Target Role | Switch Port |
| --- | --- | --- | --- | --- | --- |
| `netboot0` | `0000:02:00.0` | `igb` | `00:07:32:78:65:C6` | `bond0` member and initramfs netboot | CSS326 `ge14` |
| `enp3s0` | `0000:03:00.0` | `igb` | `00:07:32:78:65:C7` | `bond0` member | CSS326 `ge17` |
| `eno1` | `0000:06:00.0` | `ixgbe` before DPDK bind | `00:07:32:78:65:C8` | OVS-DPDK/VPP/SR-IOV reserved | CCR2004 `ge3` |
| `eno2` | `0000:06:00.1` | `ixgbe` before DPDK bind | `00:07:32:78:65:C9` | OVS-DPDK/VPP/SR-IOV reserved | CCR2004 `ge4` |
| `eno3` | `0000:07:00.0` | `ixgbe` before DPDK bind | `00:07:32:78:65:CA` | OVS-DPDK/VPP/SR-IOV reserved | CCR2004 `ge5` |
| `eno4` | `0000:07:00.1` | `ixgbe` before DPDK bind | `00:07:32:78:65:CB` | OVS-DPDK/VPP/SR-IOV reserved | CCR2004 `ge6` |

Live `bond0` settings after the 2026-05-24 cutover:

```text
config_bond0="172.16.99.70/24"
routes_bond0="default via 172.16.99.1"
dns_servers_bond0="172.16.99.1 9.9.9.9"
slaves_bond0="netboot0 enp3s0"
mode_bond0="active-backup"
miimon_bond0="100"
primary_bond0="netboot0"
config_netboot0="null"
config_enp3s0="null"
config_eno1="null"
config_eno2="null"
config_eno3="null"
config_eno4="null"
```

The live cutover intentionally used `active-backup` instead of `802.3ad` because
CSS326 SwOS LACP mutation is not yet a tested automation path. This preserves
management reachability through `netboot0` while still moving `172.16.99.70/24`
and the default route onto `bond0`. The 802.3ad target remains deferred until
CSS326 LACP group membership can be updated and validated for `ge14 + ge17`.

Validation evidence from 2026-05-24:

- SSH to `172.16.99.70` returned after the cutover and the rollback sentinel was
  written before the 180-second rollback watchdog fired.
- `bond0` owns `172.16.99.70/24`; default route is `172.16.99.1 dev bond0`.
- `bond0` mode is `active-backup`; active slave is `netboot0`; backup slave is
  `enp3s0`; both links are 1G/full.
- `openvpn.fmt2` was restarted after the OpenRC network bounce; FMT2 routes via
  `tun-fmt2` validate again.
- CCR2004 bridge FDB learned `eno1..eno4` as `00:07:32:78:65:C8` on `ge3`,
  `C9` on `ge4`, `CA` on `ge5`, and `CB` on `ge6` after L2 ARP probes.
- `eno2` has no `10.64.64.70/24`; `eno1..eno4` remain unnumbered and reserved
  for OVS-DPDK/VPP/SR-IOV ownership.
- IPv6 is disabled on `eno1..eno4` via `/etc/sysctl.d/91-m70-reserved-x553.conf`
  so the host stack does not assign link-local addresses to reserved DPDK ports.

Do not move the current `active-backup` bond to `802.3ad` until CSS326
`ge14 + ge17` LACP membership has a tested mutation and validation path.

Backout for the current live state is intentionally simple: restore the saved
`/root/m70-net-pre-bond0-cutover.conf.<timestamp>` to `/etc/conf.d/net`, stop
`net.bond0`, start `net.netboot0`, and validate SSH to `172.16.99.70`. CSS326
LACP backout is only required after a future 802.3ad cutover changes switch-side
LACP membership.

On 2026-05-14 the persistent install completed its first boot path. `/dev/sda`
was rebuilt as a clean GPT disk with a single 1 GiB FAT32 ESP labeled
`M70IPXE`; `EFI/BOOT/BOOTX64.EFI` matches the published `m70-forge-ipxe.efi`
hash `239b5526f919e4aa4a833763d6db972675796452df8389efe9cb57fea6bab278`.
The netboot publisher now chains `roles/forge-automation-admin-zfs.ipxe`, which
loads the HTTP kernel/initramfs and imports `zroot/ROOT/gentoo` as `/`.
Repeat reboot validation returned hostname `admin-sun99-forge-099070`,
root source `zroot/ROOT/gentoo`, and `zpool status -x` as healthy.

Observed hardware note: Linux/BSDRP serial validation reported 32 GiB available
memory, while the planned inventory expected 64 GiB. Validate DIMM population
before scheduling memory-heavy workloads on this node.

## USB Serial And UPS Gateway

On 2026-05-17 the generic USB serial hub was moved from Hasslehoff to this M70
so RouterOS serial access and CyberPower USB UPS telemetry are no longer tied to
Hasslehoff. The 1.9 TiB USB NVMe staging disk remains direct-attached to M70,
while the serial adapters and CyberPower UPS are attached through the hub.

Observed stable mappings:

| Device | Stable Device | Current TTY | Notes |
| --- | --- | --- | --- |
| CCR2004 gateway | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0` | `/dev/ttyUSB0` | RouterOS console |
| CRS354 distribution | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3W-if00-port0` | `/dev/ttyUSB1` | RouterOS console |
| CRS309 spine | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3X-if00-port0` | `/dev/ttyUSB4` | RouterOS console |
| CyberPower UPS | USB `0764:0601`, product `CP1500PFCRM2U` | `/dev/hidraw0` | NUT `usbhid-ups` |

Use `/dev/serial/by-id` for automation. The `/dev/ttyUSB*` names are observed
state only and can change after USB re-enumeration.

## Intel QAT

The M70 Atom C3000 platform exposes Intel QuickAssist at PCI `01:00.0`
(`8086:19e2`). Live validation on 2026-05-14 showed kernel driver `c3xxx`,
module `qat_c3xxx`, supporting module `intel_qat`, and in-tree kernel config for
`CONFIG_CRYPTO_DEV_QAT_C3XXX=m` plus `CONFIG_CRYPTO_DEV_QAT_C3XXXVF=m`.

The profile includes the reusable `stage5-metal-intel-platform` package layer
for `sys-firmware/intel-microcode` and `sys-kernel/linux-firmware`, and it loads
`intel_qat` plus `qat_c3xxx`. Application consumers stay gated: OpenSSL,
HAProxy, Nginx, and OpenZFS must each get benchmark evidence and rollback
commands before QAT acceleration is enabled in production. OpenZFS+QAT is
tracked as a separate CI/CD artifact lane because Gentoo does not currently
treat QAT-enabled ZFS as the stock ebuild path.

Live installation on 2026-05-14 completed `sys-firmware/intel-microcode`,
`sys-kernel/linux-firmware`, and `sys-apps/iucode_tool`. The required C3000 QAT
firmware files are present at `/lib/firmware/intel/qat/qat_c3xxx.bin` and
`/lib/firmware/intel/qat/qat_c3xxx_mmp.bin`.

## Local Monitoring

On 2026-05-15 the M70 local monitoring baseline was installed and validated:
`lm_sensors`, `htop`, `btop`, `iotop-c`, `lsof`, `psmisc`, `parallel`,
`numactl`, `numad`, `time`, `anacron`, `daemontools`, `wait_on_pid`, and
`watchpid`.

`sensors-detect --auto` found `coretemp` and the ITE IT8728F Super I/O sensor
driver `it87`; `jc42` also exposes DDR4 DIMM temperature sensors. The default
DIMM and Super I/O thresholds can report bogus alarms, so production alerting
must use a board-specific `sensors.conf` before treating those alarms as SLO
signals.

## Tooling Baseline

The first live admin baseline installed Ansible, `ansible-vault`, `ipmitool`,
`nmap`, `tcpdump`, `tmux`, `jq`, `pciutils`, `usbutils`, `gentoolkit`, `eix`,
Git, and `git-lfs`. `git-lfs` is required because restored Forge working copies
use LFS filters; without it, `git status` fails before the repo can be used for
cutover validation. The local Gentoo repo did not expose `dev-vcs/github-cli`,
so the existing static `/usr/local/bin/gh` 2.88.1 binary from the current
automation host was installed on the M70 with SHA256
`c1be595a7357120e28886922c050fed34ad347c36adf37370ad91d4972a416d5`. `gh auth
status` validates with the restored Forge token.

The automation-admin profile now treats the following operator tools as part of
the baseline, not ad hoc live-host drift: GNU Emacs 30 or newer, `tree`,
`bash-completion`, `xfsprogs`, `xfsdump`, `eza`, Git, `git-lfs`, and `tig`.
`dev-vcs/git-delta` was checked but is not available in the active Gentoo repo;
`dev-vcs/git-extras` is keyword-masked and should stay out of the stable
baseline until the overlay policy explicitly accepts it. The live M70 Emacs USE
shape is captured in the profile with X-enabled Emacs and systemd/GTK/Wayland
disabled.

M70 also carries an eix cache policy file at `/etc/eixrc/00-eixrc`:

```text
OVERLAY_CACHE_METHOD="assign"
```

This keeps overlay cache behavior consistent for automation-admin hosts and
should be rendered by the profile rather than copied manually.

The X12AGAIN BMC wrapper was staged under
`/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin` on the M70 with root-only path
permissions. `ipmitool chassis status` from the M70 reaches the X12AGAIN BMC at
`172.16.199.108` and returns normal chassis power/fault state.

## Forge Continuity Restore

On 2026-05-14 the latest off-host X12AGAIN `/root` backup snapshot
`/home/x12again-root/20260513-191801/root` was restored onto the M70 under
`/srv/restore/x12again-root/20260513-191801/root`. The active merge copied only
the continuity-critical paths into `/root`: `.codex`, `.config/superpowers`,
`.ssh/vault`, `.ssh/codex.d/tokens`, `.ssh/codex.d/ipmi.d`,
`operator-private`, `RFC_Codex_Gentoo-Stage4-LLVM`, and selected shell/git
configuration. The pre-merge M70 state was preserved at
`/root/restore-pre-merge-20260514T050816Z`.

Post-merge validation confirms the M70 has `/root/.codex/config.toml`, the
Ansible vault environment, the Forge GitHub token, the operator backup script,
and a usable restored repo. The restored active repo is
`/root/RFC_Codex_Gentoo-Stage4-LLVM` on branch
`codex/slurm-pilot-control-plane` at commit `d6c04cd`; `git status` works after
installing `dev-vcs/git-lfs`.

The latest off-host `/opt` snapshot is about 227 GiB, while the current M70
pool has about 223 GiB available. Full `/opt` import is therefore deferred until
larger local storage, an NFS-backed restore target, or a selective `/opt`
subtree restore plan is chosen.

## Storage Layout

/dev/sda is the EFI/iPXE boot disk only. The M70 firmware did not expose a
usable NVMe boot path during validation, so the SATADOM/local SATA device stays
as the minimal UEFI chainloader disk unless a later BIOS update changes that
constraint.

/dev/nvme0n1 and /dev/nvme1n1 are the destructive mirrored ZFS targets for
the installed automation-admin root/data pool. The current observed NVMe pair is
small enough to treat as a temporary install target; if larger 2230/2242 NVMe
drives are installed before final provisioning, re-run `lsblk`, `nvme list`, and
SMART/NVMe health checks before starting the wipe.

On 2026-05-14 the SATADOM boot path was backed up before disk prep. The first
64 MiB of `/dev/sda` and the pre-wipe disk inventory were stored outside the
repo under `/root/operator-private/m70/preinstall/`; raw backup artifacts are
not committed. After confirming the live root was the netboot overlay and
neither NVMe disk was mounted, `/dev/sda` was wiped and rebuilt as the clean
M70IPXE ESP, and both NVMe devices were wiped by clearing filesystem signatures
plus the head and tail GPT regions.

The active persistent layout is `zroot`, a mirrored ZFS pool over the two KIOXIA
NVMe devices. `bootfs=zroot/ROOT/gentoo`, `autotrim=on`, and child datasets are
mounted for `/home`, `/opt`, `/srv`, `/tmp`, `/usr/local`, `/var/lib`, and
`/var/log`. The active root is `zroot/ROOT/gentoo` at `/`.

The install workflow may wipe `/dev/sda`, `/dev/nvme0n1`, and `/dev/nvme1n1`,
but it must preserve the design boundary: SATA/SATADOM provides the UEFI iPXE
entry point, while mirrored NVMe provides the durable ZFS system pool. `fwupd`
can be probed after the installed system is online, but this hardware is old
enough that a vendor BIOS update path is more likely than an LVFS-provided NVMe
boot fix.

## Remaining Blockers

- Full `/opt` continuity restore is deferred due the current M70 pool capacity
  being smaller than the latest off-host `/opt` backup.
- Observed memory is still 32 GiB while the planned inventory expected 64 GiB;
  validate DIMM population before scheduling memory-heavy automation workloads.

## Acceptance Gates

The M70 is not ready to replace X12AGAIN as the automation-admin host until it
passes these checks:

- SSH works as the expected administrative account with vault-backed access.
- `ansible --version`, `ansible-vault`, `git`, and `gh` work from the host.
- `/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin` can open X12AGAIN SoL.
- Hasslehoff, CCR2004, NetBox, FreeIPA, local ntfy HTTPS, GitHub, and the
  off-host backup target are reachable.
- Restored continuity paths exist for `/root`, `/opt`, `/var/lib/ansible`,
  `/var/lib/codex`, `/var/lib/forge-memory`, and `/var/lib/git`.
- Forge memory spool writes to `/var/lib/forge-memory/spool`.

## Backout

No X12AGAIN reimage should start until the M70 passes acceptance. If M70
provisioning fails, leave X12AGAIN online, keep using Hasslehoff-hosted service
VMs for infrastructure services, and retry M70 provisioning after correcting
BIOS, DHCP, iPXE, or storage layout issues.
