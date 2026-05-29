# Thor CRS354 LACP TRex MIG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Thor AGX data-plane links online through CRS354 LACP, validate cross-bridge performance, then gate TRex DPDK and MIG/vGPU work behind hardware support checks.

**Architecture:** CRS354 owns the switch-side `802.3ad` LACP groups, while Thor owns OVS userspace bonds and temporary validation namespaces. TRex DPDK and MIG-backed vGPU are separate follow-up lanes because each can disrupt live networking or GPU workloads if prerequisites are not proven first.

**Tech Stack:** RouterOS `802.3ad`, Open vSwitch netdev datapath, iperf3, Podman/OCI, Kata/QEMU, NVIDIA MIG/vGPU, deepeval.

---

### Task 1: Repair CRS354 Access Gate

**Files:**
- Modify: `docs/THOR-CRS354-LACP-PERF-RUNBOOK.md`

- [ ] **Step 1: Verify CRS354 management path from M70**

Run:

```bash
ssh forge1@172.16.99.70 'nc -vz -w3 172.16.99.7 22; nc -vz -w3 172.16.99.7 8728; nc -vz -w3 172.16.99.7 8729'
```

Expected before credential repair: TCP timeout on all three ports.

- [ ] **Step 2: Verify serial login after vault correction**

Run:

```bash
ssh forge1@172.16.99.70 'cd ~/src/RFC_Codex_Gentoo-Stage4-LLVM && source ~/.ssh/vault/ANSIBLE_VARS.ENV && PASS=$(ansible-inventory -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml --host sw_mgmt_mkcrs354 | python3 -c "import json,sys; print(json.load(sys.stdin).get(\"vault_crs354_admin_password\",\"\"))") && sudo -n env ROUTEROS_PASSWORD="$PASS" scripts/routeros-serial-command.py --port /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3W-if00-port0 --username admin --password-env ROUTEROS_PASSWORD --command "/system identity print"'
```

Expected after credential repair: RouterOS identity output for `sw-mgmt-mkcrs354`.

- [ ] **Step 3: Commit the access status update**

Run:

```bash
git add docs/THOR-CRS354-LACP-PERF-RUNBOOK.md
git commit -m "docs: update crs354 access gate for thor lacp"
```

### Task 2: Apply CRS354 LACP

**Files:**
- Modify: `docs/THOR-CRS354-LACP-PERF-RUNBOOK.md`

- [ ] **Step 1: Capture RouterOS backup and export**

Run over verified RouterOS session:

```routeros
/system backup save name=pre-thor-lacp-20260527
/export file=pre-thor-lacp-20260527 hide-sensitive
```

Expected: backup and export files exist on CRS354.

- [ ] **Step 2: Apply Thor LACP bonds**

Run over verified RouterOS session:

```routeros
/interface ethernet set [find where name="qsfpplus2-1"] comment="Thor AGX bond-podman0 LACP member 1"
/interface ethernet set [find where name="qsfpplus2-2"] comment="Thor AGX bond-podman0 LACP member 2"
/interface ethernet set [find where name="qsfpplus2-3"] comment="Thor AGX bond-kata0 LACP member 1"
/interface ethernet set [find where name="qsfpplus2-4"] comment="Thor AGX bond-kata0 LACP member 2"
/interface bridge port remove [find where interface="qsfpplus2-1"]
/interface bridge port remove [find where interface="qsfpplus2-2"]
/interface bridge port remove [find where interface="qsfpplus2-3"]
/interface bridge port remove [find where interface="qsfpplus2-4"]
/interface bonding add name=bond-thor-podman mode=802.3ad slaves=qsfpplus2-1,qsfpplus2-2 lacp-rate=1sec lacp-mode=active link-monitoring=mii comment="Thor AGX br-podman0 LACP"
/interface bonding add name=bond-thor-kata mode=802.3ad slaves=qsfpplus2-3,qsfpplus2-4 lacp-rate=1sec lacp-mode=active link-monitoring=mii comment="Thor AGX br-kata0 LACP"
/interface bridge port add bridge=bridge0 interface=bond-thor-podman comment="Thor AGX Podman data plane"
/interface bridge port add bridge=bridge0 interface=bond-thor-kata comment="Thor AGX QEMU/Kata data plane"
```

Expected: both bonds are created and attached to `bridge0`.

- [ ] **Step 3: Validate RouterOS LACP state**

Run:

```routeros
/interface bonding monitor bond-thor-podman once
/interface bonding monitor bond-thor-kata once
/interface bonding monitor-slaves bond-thor-podman once
/interface bonding monitor-slaves bond-thor-kata once
```

Expected: all four members are synchronized, collecting, and distributing.

### Task 3: Validate Thor Cross-Bridge Performance

**Files:**
- Create: `scripts/thor-ovs-cross-bridge-iperf.sh`
- Modify: `docs/THOR-CRS354-LACP-PERF-RUNBOOK.md`
- Test: `tests/shell/test_thor_crs354_lacp_perf_runbook.sh`

- [ ] **Step 1: Install the Thor validation harness**

Run:

```bash
scp scripts/thor-ovs-cross-bridge-iperf.sh forge1@172.16.99.70:/tmp/thor-ovs-cross-bridge-iperf.sh
ssh forge1@172.16.99.70 'scp /tmp/thor-ovs-cross-bridge-iperf.sh root@172.16.99.34:/root/thor-ovs-cross-bridge-iperf.sh && ssh root@172.16.99.34 "chmod 0755 /root/thor-ovs-cross-bridge-iperf.sh"'
```

Expected: executable script exists at `/root/thor-ovs-cross-bridge-iperf.sh`.

- [ ] **Step 2: Run single-stream validation**

Run:

```bash
ssh forge1@172.16.99.70 'ssh root@172.16.99.34 "/root/thor-ovs-cross-bridge-iperf.sh --parallel 1 --duration 30 --json-out /root/thor-cross-bridge-iperf-p1.json"'
```

Expected: ping succeeds and JSON result exists.

- [ ] **Step 3: Run multi-stream validation**

Run:

```bash
ssh forge1@172.16.99.70 'ssh root@172.16.99.34 "/root/thor-ovs-cross-bridge-iperf.sh --parallel 8 --duration 60 --json-out /root/thor-cross-bridge-iperf-p8.json"'
```

Expected: ping succeeds and JSON result exists.

- [ ] **Step 4: Commit validation artifacts**

Run:

```bash
git add scripts/thor-ovs-cross-bridge-iperf.sh docs/THOR-CRS354-LACP-PERF-RUNBOOK.md tests/shell/test_thor_crs354_lacp_perf_runbook.sh docs/superpowers/plans/2026-05-26-thor-crs354-lacp-trex-mig.md
git commit -m "docs: add thor crs354 lacp performance runbook"
```

### Task 4: Gate TRex DPDK And MIG/vGPU

**Files:**
- Modify: `docs/THOR-CRS354-LACP-PERF-RUNBOOK.md`

- [ ] **Step 1: Prove dedicated NIC ownership for TRex**

Run on Thor:

```bash
find /sys/class/net -maxdepth 1 -type l -printf '%f\n' | sort
```

Expected: a dedicated NIC or VF exists that is not `mgbe0_0`, `mgbe1_0`, `mgbe2_0`, or `mgbe3_0`.

- [ ] **Step 2: Prove vGPU host capability before enabling MIG**

Run on Thor:

```bash
nvidia-smi -q | grep -Ei -A8 -B3 'MIG|vGPU|Virtualization|SR-IOV|Multi Instance'
find /sys/class/mdev_bus /sys/bus/pci/devices -maxdepth 3 \( -name mdev_supported_types -o -name sriov_totalvfs -o -name sriov_numvfs \) -print 2>/dev/null
```

Expected before vGPU stack installation: no usable vGPU mdev/SR-IOV controls.

- [ ] **Step 3: Defer disruptive changes until prerequisites pass**

Do not run `nvidia-smi -mig 1`, bind `mgbe*` to DPDK, or move live services to the new bridges until Tasks 1 through 3 pass.
