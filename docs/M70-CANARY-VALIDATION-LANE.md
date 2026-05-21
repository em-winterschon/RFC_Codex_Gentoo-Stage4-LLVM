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

- canary device record, hostname, FQDN, site, rack, role, platform, serial
- management IP on the planned i211 management path
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

## Planned Physical Intake

Operator-provided planned canary cabling on 2026-05-21:

| Canary endpoint | Planned connection | Role |
| --- | --- | --- |
| `netboot0` | CSS326 `ge19` | iPXE, rescue, primary management |
| `enp3s0` | CSS326 `ge20` | post-boot management backup |
| `eno1` | CSS326 `ge21` | OVS workload LACP member |
| `eno2` | CSS326 `ge22` | OVS workload LACP member |
| `eno3` | CSS326 `ge23` | OVS workload LACP member |
| `eno4` | CSS326 `ge24` | OVS workload LACP member |
| RS232 console | remaining spare M70 USB-hub RS232 path | BIOS/iPXE console work |
| Power inlet | AP7901 PDU outlet 7 | canary power |

Known canary NIC facts:

- `netboot0`: PCI `0000:02:00.0`, driver `igb`, MAC `00:07:32:58:73:34`.
- `enp3s0`: PCI `0000:03:00.0`, driver `igb`, MAC pending host discovery.
- `eno1` through `eno4`: X553 `ixgbe`, MAC addresses pending host discovery.

Required CSS326 prep:

- Move CRS354 `ether49` management copper from CSS326 `ge24` to CSS326 `ge15`.
- Free CSS326 `ge19` through `ge24` for the canary M70's six Ethernet links.
- Resolve the existing source-of-truth conflict before NetBox apply: the
  current structured inventory and NetBox description still mark CSS326 `ge15`
  as `lap-sun99-chonkers-lom`.

Do not update live NetBox cabling to this target state until the physical moves
are complete or explicitly confirmed. Once the canary boots, discover the
remaining five NIC MAC addresses from the host and reconcile NetBox.

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

## Validation Gates

### 1. Cable And Inventory Gate

Required evidence:

- power is stable
- all six Ethernet links are physically cabled
- RS232 is physically attached
- NetBox has the canary device, interfaces, cabling, IPs, and serial intent
- `/dev/serial/by-id` is stable after the USB hub power swap
- CSS326 `ge15` conflict with Chonkers is resolved before CRS354 management is
  recorded there
- CSS326 `ge19` through `ge24` match the canary physical cabling plan

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
