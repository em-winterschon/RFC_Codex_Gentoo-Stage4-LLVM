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
| `ge14` | M70 Forge admin `netboot0` management | linked, SNMP FDB MAC `00:07:32:78:65:C6` |
| `ge17` | M70 Forge admin `bond0` member `enp3s0` | active LACP group 2, unnumbered, partner `8a:87:45:85:5d:5a` |
| `ge18` | M70 Forge admin `bond0` member `eno1` | active LACP group 2, unnumbered, partner `8a:87:45:85:5d:5a` |
| `ge24` | CRS354 `ether49` management copper | linked |
| `sfp1` | planned CRS309 `sfp-sfpplus8` access/aggregation uplink | 10G-SR optic present |
| `sfp2` | legacy CRS354 uplink / temporary access path | 10G-SR optic present |

The M70 `ge17`/`ge18` pair is active as an unnumbered 802.3ad LACP bond. Do not
configure a host bridge or IP address on `bond0` until a staging VLAN or VM
bridge change is explicitly approved.

The current SFP modules are Intel `FTLX8571D3BCV-IT` 10G-SR MMF optics. The
fabric default remains FS.com `SFP-10GSR-85` or 10Gtek `AXS85-192-M3` for new
10G-SR links unless a device record explicitly states otherwise.

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
