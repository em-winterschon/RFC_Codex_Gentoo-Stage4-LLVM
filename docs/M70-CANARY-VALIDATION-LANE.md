# M70 Canary Validation Lane

This runbook defines the second M70 as the blast-test node for risky boot,
network, package, OVS, VM, microVM, container, and SLURM changes before those
changes touch the primary Forge M70.

Primary Forge M70:

- `admin-sun99-forge-099070.rfc1918.host`
- Keep stable for Forge memory, ntfy/FCP, NetBox automation, operator workflows,
  and ongoing SUN99/FMT2 work.

Canary M70:

- Same baseline machine profile as the primary M70.
- Different hostname, management IPs, MACs, NetBox device record, serial path,
  local runtime state, and workload identity.
- May be rebooted, reimaged, package-tested, and network-tested without
  disrupting the primary Forge M70.

## Approved Network Topology

Use the two Intel i211 NICs for management and rescue:

| Interface | Driver | Role |
| --- | --- | --- |
| `netboot0` | `igb` | Primary management, iPXE, rescue, first boot |
| `enp3s0` | `igb` | Post-boot management backup |
| `bond-mgmt` | bonding | Active-backup management bond after boot |

Use the four Intel X553 NICs for workload networking:

| Interface | Driver | Role |
| --- | --- | --- |
| `eno1` | `ixgbe` | OVS workload LACP member |
| `eno2` | `ixgbe` | OVS workload LACP member |
| `eno3` | `ixgbe` | OVS workload LACP member |
| `eno4` | `ixgbe` | OVS workload LACP member |
| `br-ovs0` | openvswitch | Workload bridge/trunk for VM/container networks |

Management stays outside Open vSwitch. Workload bridges, VLANs, tap devices,
Kata, Firecracker, QEMU, LXC, and Podman networking belong on the X553/OVS
side.

Recommended host intent:

```text
i211:
  netboot0  -> iPXE/rescue/primary management
  enp3s0    -> post-boot management backup
  bond-mgmt -> active-backup, outside OVS

X553:
  eno1-eno4 -> OVS bond, lacp=active, bond_mode=balance-tcp
  br-ovs0   -> workload trunk for VM/container networks
```

## NetBox Intake Checklist

Create or validate these NetBox records before applying live network state:

- canary device record, site, role, and device type
- hostname, FQDN, management IP, rack placement, and serial after discovery
- six physical Ethernet interfaces with MAC addresses where known
- switch-port cabling for all six Ethernet links
- `bond-mgmt` or equivalent LAG intent for the two i211 ports
- X553 workload LAG/OVS intent for `eno1` through `eno4`
- `br-ovs0` as the workload bridge intent if modeled as a virtual interface
- prefixes and VLANs for any OVS workload networks
- RS232 console path after the USB hub power swap and canary cable install
- service records only after the canary actually runs those services

NetBox is authoritative. Host-local observations are evidence used to update
NetBox, not a replacement for NetBox.

## Confirmed Physical Intake

Operator-provided canary cabling on 2026-05-21, confirmed active by operator
report and SwOS snapshot `20260521T232928Z`:

| Canary endpoint | Connection | Role |
| --- | --- | --- |
| `netboot0` | CSS326 `ge19` | iPXE, rescue, primary management |
| `enp3s0` | CSS326 `ge20` | post-boot management backup |
| `eno1` | CSS326 `ge21` | OVS workload LACP member |
| `eno2` | CSS326 `ge22` | OVS workload LACP member |
| `eno3` | CSS326 `ge23` | OVS workload LACP member |
| `eno4` | CSS326 `ge24` | OVS workload LACP member |
| RS232 console | `/dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if01-port0` | BIOS/iPXE console work |
| Power inlet | AP7901 PDU outlet 7 | canary power |

Known canary NIC facts:

- `netboot0`: PCI `0000:02:00.0`, driver `igb`, MAC `00:07:32:58:73:34`.
- `enp3s0`: PCI `0000:03:00.0`, driver `igb`, MAC `00:07:32:58:73:35`.
- `eno1` through `eno4`: X553 `ixgbe`, MACs `00:07:32:58:73:36`
  through `00:07:32:58:73:39`.

Required CSS326 prep:

- CRS354 `ether49` management copper was moved from CSS326 `ge24` to CSS326
  `ge15` on 2026-05-21.
- NetBox cable `4` records CSS326 `ge15` to CRS354 `ether49` as connected.
- NetBox device `m70_canary` records the active M70 canary.
- NetBox cables `5` through `10` record CSS326 `ge19` through `ge24` to the
  canary's six Ethernet interfaces.
- NetBox cable `11` records AP7901 outlet 7 to the canary power input.
- The structured inventory records Chonkers' former CSS326 `ge15` connection as
  historical.

Once the canary boots, reconcile host-observed state back to NetBox. The
remaining five NIC MAC addresses were discovered from the old HBSD/FreeBSD
shell on 2026-05-22 and have been staged into inventory intake. Do not add
service ownership until the canary actually runs those services.

## Persistent Gentoo Install Target

The canary must not depend on iPXE after installation. iPXE remains only the
installer and rescue path.

Persistent target state:

- hostname: `sbsoc-accel-int64-m70n2`
- FQDN: `sbsoc-accel-int64-m70n2.rfc1918.host`
- aliases: `m70n2.rfc1918.host`, `m70-canary.rfc1918.host`
- management IP: `172.16.99.22/24`
- boot strategy: ZFSBootMenu local EFI boot
- storage layout: ZFS mirror across the two KIOXIA NVMe devices
- management network: `bond-mgmt` active-backup over `netboot0` and `enp3s0`
- workload network: Open vSwitch `br-ovs0` with `ovs-workload0` active LACP
  over `eno1` through `eno4`

Discovered storage on 2026-05-22 from the canary RS232 console:

| OS view | Model | Serial / EUI | Install use |
| --- | --- | --- | --- |
| FreeBSD `ada0` | SATADOM-SH 3ME3 | `20180915AA9241033080` | excluded |
| FreeBSD `nda0` | KBG50ZNS256G NVMe KIOXIA 256GB | `82HPG1DLQEKK`, EUI `8ce38e0403ef1a38` | Gentoo ZFS mirror |
| FreeBSD `nda1` | KBG50ZNS256G NVMe KIOXIA 256GB | `82HPG1I8QEKK`, EUI `8ce38e0403ef1adf` | Gentoo ZFS mirror |

Expected Linux target paths:

```text
/dev/disk/by-id/nvme-eui.8ce38e0403ef1a38
/dev/disk/by-id/nvme-eui.8ce38e0403ef1adf
```

Before destructive install execution, confirm both paths exist in the Gentoo
installer environment and confirm the SATA-DOM path is not present in
`storage_devices`.

## Current Remediation State

Status captured on 2026-05-24 after the persistent Gentoo target was repaired
from the netbooted installer environment:

- Live and target host identity now resolve to `sbsoc-accel-int64-m70n2`.
- The stale `gmktek-k10-stage5` live `/etc/hosts` entry was removed.
- A scan of live `/etc`, target `/mnt/gentoo/etc`, and target
  `/mnt/gentoo/boot` found zero remaining `gmktek` or `k10-stage5`
  references.
- Target `/etc/hosts` contains:

  ```text
  127.0.0.1 localhost
  ::1 localhost
  127.0.1.1 sbsoc-accel-int64-m70n2.rfc1918.host sbsoc-accel-int64-m70n2
  ```

- Target `/etc/cmdline` and `/etc/kernel/cmdline` both carry:

  ```text
  root=ZFS=rpool/ROOT/gentoo ro console=tty0 console=ttyS0,115200 intel_iommu=on iommu=pt
  ```

- `chroot_base` now writes the target hosts file plus both kernel command-line
  locations so later install passes do not regress into host-specific stale
  identity.
- `kernel_config` is now a standalone role that runs before package and kernel
  builds. It renders profile-provided fragments into
  `/etc/kernel/config.d`.
- The canary target has
  `/mnt/gentoo/etc/kernel/config.d/90-intel-qat-c3000.config` with Intel C3000
  QAT, SR-IOV, UIO, VFIO PCI, and QAT VFIO policy.
- Live QAT validation shows `qat_c3xxx` and `intel_qat` loaded, with QAT
  heartbeat status `0`.
- Stock Gentoo package checks still did not find a ready `qatlib`,
  `qatengine`, OpenSSL QAT provider, or OpenZFS QAT package path. Kernel and
  firmware enablement is complete; userspace QAT acceleration remains a
  separate package/overlay decision.

ZFSBootMenu and initramfs state after the 2026-05-24 repair:

- `rpool/ROOT` and `rpool/ROOT/gentoo` both have
  `org.zfsbootmenu:commandline` set to:

  ```text
  ro console=tty0 console=ttyS0,115200 intel_iommu=on iommu=pt spl_hostid=1709fd12
  ```

- `rpool` has `cachefile=/mnt/gentoo/etc/zfs/zpool.cache`.
- Target dracut configs now include:
  - `90-zfs-hostid.conf`
  - `90-zfs-root.conf`
  - `95-universal-netboot-microcode.conf`
- The rebuilt initramfs at
  `/mnt/gentoo/boot/initramfs-6.18.32-p2-gentoo-dist-hardened.img` was written
  at `2026-05-24 17:36:30 UTC` and is `99570714` bytes.
- `lsinitrd` evidence shows the rebuilt initramfs includes:
  - `kernel/x86/microcode/AuthenticAMD.bin`
  - `kernel/x86/microcode/GenuineIntel.bin`
  - `/etc/hostid`
  - `/etc/zfs/zpool.cache`
  - `usr/lib/modules/6.18.32-p2-gentoo-dist-hardened/extra/zfs.ko`
  - Intel QAT firmware and `qat_c3xxx`, `qat_c3xxxvf`, `intel_qat` modules
  - `network-legacy`, `dhclient`, and `dhclient-script`

No reboot or PDU power action was performed as part of this remediation. The
next destructive or rebooting action is a planned canary-only local
ZFSBootMenu boot validation.

## Firmware Boot State

Live RS232 firmware work on 2026-05-22 changed the canary boot settings from
the inherited disk-first profile toward netboot:

- Boot Option #1: `Network`
- CSM Support: `Enabled`
- Launch PXE ROM: `Enabled`
- Boot mode select: `UEFI`

The node still returned to Aptio Setup after reset. A concurrent `tcpdump` on
the primary M70 `netboot0` interface captured zero DHCP/TFTP/PXE packets from
canary MAC `00:07:32:58:73:34`, so the current blocker is firmware/device PXE
launch rather than the Path B host script itself. Before another install
attempt, find the concrete UEFI network boot target or per-NIC PXE enablement
for the i211 `netboot0` controller.

After the persistent ZFSBootMenu install is staged, the managed canary netboot
role is `localdisk`. If firmware still attempts PXE first, the Path B
dispatcher should match canary MAC `00:07:32:58:73:34` and chain the existing
`localdisk` iPXE role instead of falling through to the installer menu.

## Serial-Hub Handling

During USB hub power changes, all attached serial paths are considered
temporarily unavailable. Do not run serial probes or RouterOS console helpers
while the hub is being moved.

After power is stable:

```bash
ls -l /dev/serial/by-id/
udevadm info --query=property --name=/dev/ttyUSB0
```

Repeat for each present `/dev/ttyUSB*` device as needed. Update
[`M70-SERIAL-CONSOLE-MAP.md`](M70-SERIAL-CONSOLE-MAP.md) and NetBox only after
stable by-id paths are confirmed.

Current canary serial path:

```text
/dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if01-port0
```

Passive capture and newline validation on 2026-05-22 reached the old
HBSD/FreeBSD root shell prompt:

```text
root@pkg-cip-hbsd-int64-m70n2:~ #
```

## Validation Gates

### 1. Cable And Inventory Gate

Required evidence:

- power is stable
- all six Ethernet links are physically cabled
- RS232 is physically attached
- NetBox has the canary device, interfaces, Ethernet cabling, and power cabling
- `/dev/serial/by-id` is stable after the USB hub power swap
- CSS326 `ge15` is recorded as CRS354 management, not Chonkers LOM
- CSS326 `ge19` through `ge24` match the canary physical cabling plan
- management IP, hostname/FQDN, and serial intent are added after discovery

Do not continue to OVS testing until this passes.

### 2. Boot Gate

Required evidence:

- canary boots from `netboot0`
- canary reaches the expected hostname/FQDN
- serial console is reachable
- primary Forge M70 remains reachable while the canary is rebooted or broken

Microcode/IOMMU tests should run here first because they require boot-path
changes.

### 3. Management Network Gate

Required evidence:

- management uses the approved i211 design
- `netboot0` remains a rescue path
- `enp3s0` participates only in management backup after boot
- management traffic is not dependent on OVS
- failover is tested by dropping one management member at a time

Preferred management mode is `active-backup`. Do not use `balance-alb` on the
primary profile unless it is intentionally tested as a canary-only experiment.

### 4. X553 OVS/LACP Gate

Required evidence:

- `eno1`, `eno2`, `eno3`, and `eno4` all link up
- switch side reports one healthy 802.3ad LAG
- OVS side reports active LACP and the expected member state
- `br-ovs0` remains reachable for workload networks after one member is dropped
  and restored
- management remains reachable if `br-ovs0` is misconfigured

The X553/OVS side is the blast zone. The i211 side is the recovery path.

### 5. Runtime Network Gate

Validate each workload path independently:

| Runtime | Required check |
| --- | --- |
| QEMU | VM tap reaches the expected test VLAN or bridge network |
| Firecracker | microVM tap works after package source is selected |
| Kata | Kata network path works after package source is selected |
| Podman | container network works without stealing management reachability |
| LXC/namespace | selected namespace path works if included in the M70 profile |

Do not collapse these into one generic "network works" result. Each runtime has
different failure modes.

### 6. Promotion Gate

Before promoting a canary-tested change:

- capture evidence in a repo doc, issue, PR, or append-only Forge memory event
- verify NetBox has no known drift for the canary
- write the rollback path
- confirm primary Forge M70 is still clean
- promote in rings: canary, primary Forge M70 if appropriate, then additional
  M70 workers

## Initial Canary Test Queue

1. Intel+AMD early microcode boot artifact order.
2. `intel_iommu=on iommu=pt` boot posture.
3. M70 runtime package policy for Podman, QEMU, SLURM, MUNGE, and support
   tooling.
4. Firecracker package source decision and smoke test.
5. Kata package source decision and smoke test.
6. X553 OVS four-port LACP with workload VLAN trunk.
7. Runtime-specific tap/network validation.
8. SLURM worker enrollment after canary runtime/network gates pass.

## Non-Goals

- Do not move primary Forge control-plane duties to the canary.
- Do not make OVS part of the management recovery path.
- Do not apply workload VLANs before NetBox has the intended prefixes and
  cabling.
- Do not treat canary host-local state as authoritative inventory.
