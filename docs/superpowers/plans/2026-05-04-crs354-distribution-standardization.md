# CRS354 Distribution Standardization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize CRS354 as a RouterOS distribution leaf with documented NetBox hardware inventory, CRS309 LACP uplink intent, QNAP archive LACP intent, and future QSFP RoCE-v2 reservation.

**Architecture:** Treat NetBox intake and `network_fabric.yml` as the durable source of truth, and treat live RouterOS imports as gated change steps with serial fallback. CRS354 management remains on `ether49` so SFP+ normalization can be staged without losing the management console.

**Tech Stack:** RouterOS 7.22.2, Ansible inventory, NetBox intake YAML, repo wiki docs, shell validation tests.

---

### Task 1: Preserve Live CRS354 Evidence

**Files:**
- Archive: `/root/operator-private/routeros/crs354/20260504T194533Z/*`
- Modify: `docs/CRS354-DISTRIBUTION-SWITCH-STANDARDIZATION.md`

- [ ] **Step 1: Confirm evidence archive exists**

Run:

```bash
test -f /root/operator-private/routeros/crs354/20260504T194533Z/manifest.json
test -f /root/operator-private/routeros/crs354/20260504T194533Z/export-hide-sensitive.rsc
```

Expected: both commands exit `0`.

- [ ] **Step 2: Record observed CRS354 facts**

Record these facts in the CRS354 standardization document:

```text
identity: sw-mgmt-mkcrs354
model: CRS354-48G-4S+2Q+
serial: HJV0AWTYBCD
RouterOS package: 7.22.2
RouterBOARD firmware: 7.22.2
management IP: 172.16.99.7/24
management interface: ether49
existing QNAP LACP: bond-qnap over sfp-sfpplus3,sfp-sfpplus4
stale OPNsense address: 172.16.254.7/24 on sfp-sfpplus1
```

### Task 2: Normalize Repo Inventory

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/network_fabric.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml`

- [ ] **Step 1: Add optics default policy**

Add this policy to `network_fabric.yml`:

```yaml
network_fabric_media_defaults:
  sfp_plus_10g_default:
    media: 10G-SR
    fiber: MMF
    single_mode_fiber_in_use: false
    optic_vendors:
      - FS.com
      - 10Gtek
    reference_skus:
      fs_com_10g_sr: SFP-10GSR-85
      ten_gtek_10g_sr: AXS85-192-M3
```

- [ ] **Step 2: Add CRS309 and QNAP devices**

Add `sw_spine_crs309_rfc99` and `qnap_archive_ts435xeu` to both fabric inventory and NetBox intake.

- [ ] **Step 3: Correct CRS354 management interface**

Change CRS354 management from the stale `ether1` assumption to live `ether49`.

### Task 3: Stage RouterOS LACP Intent

**Files:**
- Modify: `docs/CRS354-DISTRIBUTION-SWITCH-STANDARDIZATION.md`

- [ ] **Step 1: Render planned CRS354 commands**

Use these commands only after backup/export and serial fallback are confirmed:

```routeros
/export file=pre-crs354-distribution-standardization hide-sensitive
/ip address disable [find where interface="sfp-sfpplus1" and address="172.16.254.7/24"]
/ip route disable [find where comment="main-default-opnsense"]
/interface bonding add name=bond-crs309 mode=802.3ad slaves=sfp-sfpplus1,sfp-sfpplus2 lacp-rate=1sec lacp-mode=active transmit-hash-policy=layer-2
/interface bridge port remove [find where interface="sfp-sfpplus2"]
/interface bridge port add bridge=bridge0 interface=bond-crs309 comment="CRS309 spine LACP"
/interface ethernet set sfp-sfpplus1 auto-negotiation=yes advertise=1G-baseX,10G-baseSR-LR comment="CRS309 LACP member 1, 10G-SR MMF"
/interface ethernet set sfp-sfpplus2 auto-negotiation=yes advertise=1G-baseX,10G-baseSR-LR comment="CRS309 LACP member 2, 10G-SR MMF"
```

- [ ] **Step 2: Render planned CRS309 commands**

Use these commands only after CRS354 command review:

```routeros
/export file=pre-crs309-crs354-lacp hide-sensitive
/interface bonding add name=bond-crs354 mode=802.3ad slaves=sfp-sfpplus2,sfp-sfpplus3 lacp-rate=1sec lacp-mode=active transmit-hash-policy=layer-2
/interface bridge port remove [find where interface="sfp-sfpplus2"]
/interface bridge port remove [find where interface="sfp-sfpplus3"]
/interface bridge port add bridge=br-spine interface=bond-crs354 comment="CRS354 distribution LACP"
/interface ethernet set sfp-sfpplus2 auto-negotiation=yes advertise=1G-baseX,10G-baseSR-LR comment="CRS354 LACP member 1, 10G-SR MMF"
/interface ethernet set sfp-sfpplus3 auto-negotiation=yes advertise=1G-baseX,10G-baseSR-LR comment="CRS354 LACP member 2, 10G-SR MMF"
```

### Task 4: Validate

**Files:**
- Modify: `tests/shell/test_local_network_inventory.sh`
- Modify: `tests/shell/test_network_planning_docs.sh`
- Modify: `tests/shell/test_netbox_inventory_intake.sh`

- [ ] **Step 1: Validate docs and inventory tests**

Run:

```bash
bash tests/shell/test_local_network_inventory.sh
bash tests/shell/test_network_planning_docs.sh
bash tests/shell/test_netbox_inventory_intake.sh
```

Expected: all three tests print `PASS`.

- [ ] **Step 2: Validate intake schema**

Run:

```bash
python3 scripts/validate_netbox_inventory_intake.py gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml --format json
```

Expected: `"ok": true`.

### Task 5: Backout

**Files:**
- Modify: `docs/CRS354-DISTRIBUTION-SWITCH-STANDARDIZATION.md`

- [ ] **Step 1: Back out CRS354 LACP if needed**

Use serial `/dev/ttyUSB1` and run:

```routeros
/interface bridge port remove [find where interface="bond-crs309"]
/interface bonding remove [find where name="bond-crs309"]
/interface bridge port add bridge=bridge0 interface=sfp-sfpplus2 comment="bridge0 uplink to basic switch, untagged only"
/ip address enable [find where interface="sfp-sfpplus1" and address="172.16.254.7/24"]
/ip route enable [find where comment="main-default-opnsense"]
```

Expected: CRS354 returns to its pre-standardization SFP+ topology while management remains reachable through `ether49`.
