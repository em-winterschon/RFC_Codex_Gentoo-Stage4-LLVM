# CRS309 Spine Aggregation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the CRS309 as a RouterOS 10GbE spine/aggregation switch between the CCR2004 gateway, CRS354/CSS326 leaf switches, and Hasslehoff high-speed links.

**Architecture:** Keep the CCR2004-16G-2S+PC as the active routed/firewall edge and use the CRS309 as a VLAN-aware L2 spine first. Introduce CRS309 L3 interfaces or hardware-offloaded routing only after the L2 fabric, LACP, NetBox model, and service health checks are stable.

**Tech Stack:** RouterOS `7.22.2`, CRS309-1G-8S+IN, bridge VLAN filtering, 802.3ad LACP, RSTP, LLDP/MNDP, Ansible render/apply roles, NetBox DCIM/IPAM.

---

## Physical Port Map

The requested map has one conflict: CRS309 `sfp-sfpplus3` cannot be both the CRS354 LACP member and a Hasslehoff CCR2004-1G-2XS-PCIe DAC member.

Recommended normalized map:

| CRS309 Port | Role | Peer |
| --- | --- | --- |
| `sfp-sfpplus1` | router uplink trunk | CCR2004-16G `sfp-sfpplus2` |
| `sfp-sfpplus2` | LACP member `bond-crs354` | CRS354 `sfp-sfpplus1` |
| `sfp-sfpplus3` | LACP member `bond-crs354` | CRS354 `sfp-sfpplus2` |
| `sfp-sfpplus4` | LACP member `bond-hasslehoff-ccr25g` | Hasslehoff CCR2004-1G-2XS-PCIe `sfp-sfpplus1`, forced to 10G |
| `sfp-sfpplus5` | LACP member `bond-hasslehoff-ccr25g` | Hasslehoff CCR2004-1G-2XS-PCIe `sfp-sfpplus2`, forced to 10G |
| `sfp-sfpplus6` | reserved | unassigned |
| `sfp-sfpplus7` | reserved | unassigned |
| `sfp-sfpplus8` | CSS326 uplink trunk | CSS326 `sfp1` |
| `ether1` | out-of-band temporary management | disconnected after stable in-band management |

If `sfp-sfpplus5` must remain unassigned, use only `sfp-sfpplus4` for Hasslehoff initially and defer the second DAC until the CRS354 bundle is moved or an additional aggregation switch exists.

## Fabric Policy

- Native management VLAN remains `172.16.99.0/24` during transition.
- CCR2004 remains default gateway at `172.16.99.1` and retains routed gateway addresses.
- CRS309 gets only a management IP during the first phase, preferably `172.16.99.x/24` allocated in NetBox before live apply.
- CRS309 bridge is the RSTP root for the local 10G aggregation domain.
- CRS354 and CSS326 operate as leaf switches with uplinks toward CRS309.
- LACP mode is active/passive with CRS309 active.
- No DHCP server runs on CRS309.
- Bandwidth-server, telnet, FTP, plaintext API, and WinBox are disabled on CRS309 by default.
- HTTP is disabled after HTTPS/API-SSL and SSH are confirmed.
- SNMP remains disabled until vaulted SNMPv3 or a scoped v2c collector policy is defined.
- Remote syslog targets the live rsyslog collector at `172.16.99.89` until the `172.16.99.80` HAProxy VIP exists.

## Task 1: NetBox Staging

**Files:**
- Modify: `inventory-intake/sites/rfc99.yml`
- Modify: `docs/CRS309-ROUTEROS-REPLACEMENT-PLAN.md`

- [ ] **Step 1: Allocate CRS309 management identity**

Choose a NetBox device name such as `sw-spine-crs309-rfc99` and reserve one unused management IP in `172.16.99.0/24`.

Run:

```bash
ping -c 2 -W 1 172.16.99.X || true
```

Expected: no replies before assignment.

- [ ] **Step 2: Add CRS309 device and interface records**

Add device, interface, LAG, and cable intent for:

```text
ether1
sfp-sfpplus1
sfp-sfpplus2
sfp-sfpplus3
sfp-sfpplus4
sfp-sfpplus5
sfp-sfpplus6
sfp-sfpplus7
sfp-sfpplus8
bond-crs354
bond-hasslehoff-ccr25g
br-spine
```

- [ ] **Step 3: Validate NetBox intake**

Run:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACKS_ENABLED=control_flow \
  ansible-playbook playbooks/netbox-inventory-intake-validate.yml
```

Expected: validation passes with the CRS309 device and port map present.

## Task 2: CRS309 Reset And RouterOS Baseline

**Files:**
- Create: `roles/routeros_spine_aggregation/defaults/main.yml`
- Create: `roles/routeros_spine_aggregation/templates/routeros-spine-aggregation.rsc.j2`
- Create: `playbooks/routeros-spine-aggregation.yml`
- Test: `tests/shell/test_routeros_spine_aggregation_role.sh`

- [ ] **Step 1: Preserve pre-reset CRS309 state**

From CRS309 serial or SSH:

```routeros
/system resource print
/system routerboard print
/system package update print
/export file=pre-reset-crs309-YYYYMMDD-HHMM
/system backup save name=pre-reset-crs309-YYYYMMDD-HHMM
/file print terse where name~"pre-reset-crs309"
```

Expected: text export and binary backup exist before reset.

- [ ] **Step 2: Reset CRS309 only after backup exists**

Use RouterOS safe-mode or serial access. Do not reset until the CCR2004 gateway remains validated and CRS309 is not required for rollback.

```routeros
/system reset-configuration no-defaults=yes skip-backup=yes
```

Expected: CRS309 returns on serial with no production L2 dependency.

- [ ] **Step 3: Upgrade CRS309 to stable RouterOS**

```routeros
/system package update set channel=stable
/system package update check-for-updates
/system package update install
```

Expected: installed version is `7.22.2` or newer stable.

- [ ] **Step 4: Upgrade RouterBOARD firmware**

```routeros
/system routerboard print
/system routerboard upgrade
/system reboot
/system routerboard print
```

Expected: `current-firmware` equals `upgrade-firmware`.

## Task 3: Render Spine Configuration

**Files:**
- Create: `roles/routeros_spine_aggregation/defaults/main.yml`
- Create: `roles/routeros_spine_aggregation/templates/routeros-spine-aggregation.rsc.j2`
- Create: `roles/routeros_spine_aggregation/templates/routeros-spine-aggregation-manifest.json.j2`
- Create: `playbooks/routeros-spine-aggregation.yml`
- Test: `tests/shell/test_routeros_spine_aggregation_role.sh`

- [ ] **Step 1: Write the shell render test**

The test must assert that the rendered RSC includes:

```text
/interface bridge add name=br-spine protocol-mode=rstp vlan-filtering=yes
/interface bonding add name=bond-crs354 mode=802.3ad slaves=sfp-sfpplus2,sfp-sfpplus3
/interface bonding add name=bond-hasslehoff-ccr25g mode=802.3ad slaves=sfp-sfpplus4,sfp-sfpplus5
/interface bridge port add bridge=br-spine interface=sfp-sfpplus1
/interface bridge port add bridge=br-spine interface=bond-crs354
/interface bridge port add bridge=br-spine interface=bond-hasslehoff-ccr25g
/interface bridge port add bridge=br-spine interface=sfp-sfpplus8
/tool bandwidth-server set enabled=no
:if ([:len [/ip service find where name="reverse-proxy"]] > 0) do={ /ip service set reverse-proxy disabled=yes }
/snmp set enabled=no
```

- [ ] **Step 2: Render dry-run config**

Run:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACKS_ENABLED=control_flow \
  ansible-playbook -i inventories/local-network/hosts.yml \
  playbooks/routeros-spine-aggregation.yml \
  -l sw_spine_crs309_rfc99 \
  -e routeros_spine_aggregation_render_root=/tmp/routeros-spine-aggregation
```

Expected: RSC and manifest render without applying live changes.

## Task 4: Staged Cabling And Validation

**Files:**
- Modify: `docs/CRS309-ROUTEROS-REPLACEMENT-PLAN.md`

- [ ] **Step 1: Cable only CCR2004 to CRS309 first**

Connect:

```text
CCR2004 sfp-sfpplus2 -> CRS309 sfp-sfpplus1
```

Validation:

```bash
ping -c 3 172.16.99.1
ping -c 3 9.9.9.9
curl -kfsS https://172.16.99.1/ >/dev/null
```

Expected: gateway and internet remain reachable.

- [ ] **Step 2: Cable CRS354 LACP**

Connect:

```text
CRS309 sfp-sfpplus2 -> CRS354 sfp-sfpplus1
CRS309 sfp-sfpplus3 -> CRS354 sfp-sfpplus2
```

Validation:

```bash
ping -c 3 172.16.99.7
nmap -Pn -p 22,80,443,8291 172.16.99.7
```

Expected: CRS354 management remains reachable through the LACP bundle.

- [ ] **Step 3: Cable CSS326 uplink**

Connect:

```text
CRS309 sfp-sfpplus8 -> CSS326 sfp1
```

Validation:

```bash
ping -c 3 172.16.99.6
curl -fsS http://172.16.99.6/ >/dev/null || curl -kfsS https://172.16.99.6/ >/dev/null
```

Expected: CSS326 management remains reachable.

- [ ] **Step 4: Cable Hasslehoff CCR2004-1G-2XS-PCIe DACs**

Connect normalized map:

```text
CRS309 sfp-sfpplus4 -> Hasslehoff CCR2004-1G-2XS-PCIe sfp-sfpplus1 at 10G
CRS309 sfp-sfpplus5 -> Hasslehoff CCR2004-1G-2XS-PCIe sfp-sfpplus2 at 10G
```

Validation:

```bash
ping -c 3 172.16.99.120
sshpass -p '<vaulted-password>' ssh admin@172.16.99.120 '/system resource print'
```

Expected: both DAC links report link-ok at 10G and management remains reachable.

## Task 5: Post-Change Evidence

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/ROADMAP-AND-TODO.md`

- [ ] **Step 1: Capture post-change exports**

```routeros
/export file=post-spine-crs309-YYYYMMDD-HHMM
/system backup save name=post-spine-crs309-YYYYMMDD-HHMM
/interface bridge port print
/interface bonding monitor bond-crs354 once
/interface bonding monitor bond-hasslehoff-ccr25g once
/interface ethernet monitor sfp-sfpplus1 once
/interface ethernet monitor sfp-sfpplus8 once
```

Expected: exports exist and each intended uplink is active.

- [ ] **Step 2: Validate service continuity**

Run:

```bash
ping -c 3 172.16.99.1
ping -c 3 172.16.99.6
ping -c 3 172.16.99.7
ping -c 3 172.16.99.9
ping -c 3 172.16.99.62
ping -c 3 172.16.99.89
ping -c 3 9.9.9.9
curl -kfsS https://172.16.99.1/ >/dev/null
curl -kfsS https://172.16.99.9:8006/ >/dev/null
curl -fsS http://172.16.99.62/ >/dev/null
curl -fsS http://172.16.99.89/ >/dev/null
```

Expected: all checks pass before the CRS309 is considered production spine.

## Backout

1. Disconnect CRS309 from CCR2004 `sfp-sfpplus2`.
2. Reconnect CCR2004 `sfp-sfpplus2` to the current known-good LAN switch uplink.
3. Restore CRS309 `pre-reset-crs309-*` backup only if the CRS309 must be returned to its prior role.
4. Leave CCR2004 gateway config untouched unless gateway validation fails independently.
5. Keep USB emergency WAN path on the Codex host until the spine path has passed repeated validation.
