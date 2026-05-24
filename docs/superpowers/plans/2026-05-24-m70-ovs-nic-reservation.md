# M70 OVS NIC Reservation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make M70 interface ownership repeatable by moving persistent management to `bond0 = netboot0 + enp3s0` and reserving `eno1..eno4` for OVS-DPDK/SR-IOV/Slurm.

**Architecture:** Update source-of-truth first, then execute a gated live cutover. NetBox intake, network fabric inventory, and M70 host-vars must agree before any switch or OpenRC network action.

**Tech Stack:** Gentoo OpenRC, Linux bonding, MikroTik SwOS CSS326, RouterOS CCR2004, NetBox inventory intake, Ansible inventory.

---

### Task 1: Source Of Truth

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/host_vars/admin_sun99_forge_099070.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/network_fabric.yml`
- Test: `tests/shell/test_m70_forge_admin_provisioning.sh`
- Test: `tests/shell/test_netbox_inventory_intake.sh`

- [ ] **Step 1: Add assertions for the target split**

Run:

```bash
bash tests/shell/test_m70_forge_admin_provisioning.sh
bash tests/shell/test_netbox_inventory_intake.sh
```

Expected before inventory edits: the new assertions fail because `bond0 = netboot0 + enp3s0` and `eno1..eno4` CCR2004 reservation are not yet encoded.

- [ ] **Step 2: Encode target M70 state**

Set the target fields to:

```yaml
persistent_management_interface: bond0
bond0:
  members:
    - netboot0
    - enp3s0
reserved_ovs_dpdk_sriov_ports:
  - eno1
  - eno2
  - eno3
  - eno4
```

Expected result: source-of-truth distinguishes current live state from approved target state.

- [ ] **Step 3: Run source-of-truth tests**

Run:

```bash
bash tests/shell/test_m70_forge_admin_provisioning.sh
bash tests/shell/test_netbox_inventory_intake.sh
```

Expected: both pass.

### Task 2: Live Cutover Runbook

**Files:**
- Modify: `docs/M70-FORGE-AUTOMATION-ADMIN.md`
- Modify: `docs/wiki/M70-Forge-Automation-Admin.md`
- Modify: `docs/runbooks/m70-automation-admin-install.md`

- [ ] **Step 1: Document preflight commands**

Record:

```bash
ip -br addr
ip route
cat /proc/net/bonding/bond0
ethtool -i netboot0 enp3s0 eno1 eno2 eno3 eno4
```

Expected: operator can prove which NICs and switch ports are involved before changes.

- [ ] **Step 2: Document gated cutover sequence**

Document this sequence:

```bash
cp -a /etc/conf.d/net /root/m70-net-pre-bond0-cutover.conf
rc-service net.bond0 stop || true
rc-service net.netboot0 stop
rc-service net.bond0 start
ip -br addr show bond0
ip route get 172.16.99.1
```

Expected: the runbook makes the network bounce explicit and requires SSH validation before releasing `eno1`.

- [ ] **Step 3: Document backout commands**

Document:

```bash
cp -a /root/m70-net-pre-bond0-cutover.conf /etc/conf.d/net
rc-service net.bond0 stop || true
rc-service net.netboot0 start
ip route get 172.16.99.1
```

Expected: operator has exact commands to restore `netboot0` management.

### Task 3: Live Execution Gate

**Files:**
- No repo files unless execution evidence is committed after the change.

- [ ] **Step 1: Coordinate CSS326 LACP**

Move CSS326 LACP group 2 from `ge17/ge18` to `ge14/ge17`.

Expected: CSS326 shows LACP active on `ge14` and `ge17`.

- [ ] **Step 2: Move persistent M70 management**

Render `/etc/conf.d/net` with `config_bond0="172.16.99.70/24"`, `routes_bond0="default via 172.16.99.1"`, `slaves_bond0="netboot0 enp3s0"`, and no host IP on `eno1..eno4`.

Expected: SSH to `172.16.99.70` returns through `bond0`.

- [ ] **Step 3: Release X553 ports**

After SSH validation, remove `eno1` from CSS326 and move it to CCR2004 `ge3`. Keep `eno2..eno4` unnumbered and ready for vfio-pci/OVS-DPDK/VPP ownership.

Expected: `eno1..eno4` have no host management addresses and are safe for Forge-Root's Slurm/OVS work.
