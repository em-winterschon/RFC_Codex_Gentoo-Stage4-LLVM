# CSS326 SwOS Access Switch

## Current Evidence

Live CSS326 SwOS state was collected over HTTP Digest from `172.16.99.6` and
archived outside the repo:

```text
/root/operator-private/swos/css326/
```

Observed state from the 2026-05-04 snapshot:

- identity: `sw-mgmt-mkcss326`
- model: `CSS326-24G-2S+`
- serial number: `HHD0AERY8JN`
- SwOS version: `2.18.1751448030`
- latest SwOS version reported by MikroTik update endpoint: `2.18.1751448030`
- management IP: `172.16.99.6`
- address acquisition: static
- MAC address: `f4:1e:57:89:af:be`
- SNMP: enabled
- SNMP contact: `toor@rfc1918.host`
- SNMP location: `RFC99-25U-WHT`

The repo helper for repeatable snapshots is:

```bash
SWOS_PASSWORD='...' scripts/collect-mikrotik-swos-state.py \
  --host 172.16.99.6 \
  --username admin \
  --output-dir /root/operator-private/swos/css326/$(date -u +%Y%m%dT%H%M%SZ)
```

Use the vaulted `vault_css326_admin_password` value in automation. Do not put
the password on the command line in persistent shell history.

The Ansible wrapper is:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
../../scripts/with-ansible-vault-env.sh ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/swos-state-snapshot.yml
```

## Normalized Role

The CSS326 is the RFC99 management/access switch for copper access and temporary
10G access uplinks while CRS309 becomes the spine switch.

Expected normalized state:

- static management IP `172.16.99.6`
- identity `sw-mgmt-mkcss326`
- HTTP Digest management with vaulted admin credential
- SNMP enabled for polling
- no syslog requirement on SwOS because the observed CSS326 SwOS `2.18` UI/API
  does not expose syslog destination controls
- periodic HTTP backup snapshots stored outside the repo under
  `/root/operator-private/swos/css326`

## Current Port Map

| CSS326 port | Purpose | Current State |
| --- | --- | --- |
| `ge4` | CCR2004-1G-2XS-PCIe management copper | linked |
| `ge5` | Hasslehoff `bond0` LACP member | active LACP group 1 |
| `ge6` | Hasslehoff `bond0` LACP member | active LACP group 1 |
| `ge15` | CRS354 `ether49` management copper | moved from `ge24` on 2026-05-21 |
| `ge24` | planned M70 canary `eno4` workload member | reserved; was CRS354 management |
| `sfp1` | planned CRS309 `sfp-sfpplus8` access/aggregation uplink | 10G-SR optic present |
| `sfp2` | legacy CRS354 uplink / temporary access path | 10G-SR optic present |

The current SFP modules are Intel `FTLX8571D3BCV-IT` 10G-SR MMF optics. The
fabric default remains FS.com `SFP-10GSR-85` or 10Gtek `AXS85-192-M3` for new
10G-SR links unless a device record explicitly states otherwise.

## Planned M70 Canary Recable

Operator-provided physical plan on 2026-05-21:

| CSS326 port | Planned endpoint | Purpose |
| --- | --- | --- |
| `ge15` | CRS354 `ether49` | move CRS354 management here from `ge24` |
| `ge19` | M70 canary `netboot0`, MAC `00:07:32:58:73:34` | iPXE, rescue, primary management |
| `ge20` | M70 canary `enp3s0` | post-boot management backup |
| `ge21` | M70 canary `eno1` | OVS workload LACP member |
| `ge22` | M70 canary `eno2` | OVS workload LACP member |
| `ge23` | M70 canary `eno3` | OVS workload LACP member |
| `ge24` | M70 canary `eno4` | OVS workload LACP member |

Source-of-truth update: NetBox now records CSS326 `ge15` as
`crs354-management`, CSS326 `ge24` as `m70-canary-eno4-planned`, and cable `4`
as the connected cable between CSS326 `ge15` and CRS354 `ether49`. The
structured inventory now marks Chonkers' former CSS326 `ge15` connection as
historical.

## Automation Boundary

SwOS is not RouterOS. It does not provide SSH, RouterOS CLI, or RouterOS
exports. For this switch, automation should use:

- HTTP Digest read-only endpoint collection for state and backup snapshots
- `playbooks/swos-state-snapshot.yml` for repeatable snapshot collection
- SNMP polling for monitoring
- NetBox as the durable source of truth for port map and cabling
- explicit operator-reviewed HTTP POST changes only when unavoidable

Do not build fake RouterOS-style playbooks for CSS326. The correct automation
unit is a SwOS snapshot/backup collector plus an intentionally narrow config
writer after we have fixture-backed tests for SwOS object encoding.

## Validation

Post-normalization validation:

```bash
ping -c 3 172.16.99.6
SWOS_PASSWORD='...' scripts/collect-mikrotik-swos-state.py \
  --host 172.16.99.6 \
  --username admin \
  --output-dir /root/operator-private/swos/css326/$(date -u +%Y%m%dT%H%M%SZ)
```

Expected:

- ping reaches `172.16.99.6`
- `summary.json` reports identity `sw-mgmt-mkcss326`
- `summary.json` reports SwOS `2.18.1751448030`
- `summary.json` reports SNMP enabled
- `summary.json` reports LACP group `1` on `ge5` and `ge6`
- `backup.swb` is captured in the snapshot directory

## Backout

CSS326 changes should be avoided until a tested writer exists. If a SwOS
configuration change breaks management, use the local web UI from the management
subnet or the physical reset process, then restore from the latest
operator-private `backup.swb`.
