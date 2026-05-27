# Thor CRS354 LACP And Performance Runbook

Status timestamp: `2026-05-27T07:56:08-07:00`

## Goal

Bring Thor AGX `mgbe0_0` through `mgbe3_0` online through CRS354 `qsfpplus2`
as two separate LACP pairs, then validate bridge-to-bridge behavior before
placing Podman, QEMU, or Kata workloads on those bridges.

The target path is:

```text
Thor br-kata0 -> CRS354 qsfpplus2 lanes -> Thor br-podman0
```

## Live Status

CRS354 management and Thor peer LACP are repaired and applied. The remaining
gate is cross-host or revised-topology performance validation; the same-host
OVS bridge hairpin path is not accepted as a throughput validation path.

Observed from M70 `forge1`:

```text
CRS354 serial console: reachable
CRS354 SSH/HTTP/HTTPS/Winbox TCP from M70: reachable
CRS354 management IP: 172.16.99.7/24 on ether49
disabled broken rule: /routing rule comment=mgmt-source-rule src-address=172.16.99.7/32
```

Root cause for the management outage was `mgmt-source-rule`: replies sourced
from `172.16.99.7/32` were forced into routing table `mgmt`, which had only a
default route and no connected `172.16.99.0/24` route. Same-subnet management
replies were therefore routed to the gateway instead of ARP-resolved directly.
The rule remains disabled.

Thor host-side OVS bridges and CRS354 peer bonds are now negotiated:

```text
bond-podman0: lacp_status negotiated; mgbe0_0 and mgbe1_0 enabled
bond-kata0:   lacp_status negotiated; mgbe2_0 and mgbe3_0 enabled
CRS354 bond-thor-podman: running, qsfpplus2-1 and qsfpplus2-2
CRS354 bond-thor-kata:   running, qsfpplus2-3 and qsfpplus2-4
```

## Design Notes

MikroTik documents RouterOS bonding as link aggregation and failover, not as a
single larger per-flow link. For `802.3ad` LACP, all aggregate members must use
the same speed and duplex, traffic is distributed by hash, and MII link
monitoring is the recommended monitoring mode for LACP. RouterOS hardware
offload on relevant switch chips is limited to `802.3ad`, `balance-xor`, and
`active-backup`; use `802.3ad` here so both Thor and CRS354 negotiate the same
standard LAG behavior.

The practical validation requirement is therefore:

- a single TCP flow may stay near one 10G member;
- parallel flows should exercise both members when hashes distribute;
- validation must record both single-stream and multi-stream results;
- bridge behavior must be tested through CRS354, not only inside one OVS bridge.

## CRS354 Change

Use serial or a verified management session. Capture both backup and export
before mutation:

```routeros
/system backup save name=pre-thor-lacp-20260527
/export file=pre-thor-lacp-20260527 hide-sensitive
```

Apply the peer LACP config:

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

Applied on 2026-05-27 with an additional post-fix backup and export captured on
CRS354:

```text
post-mgmt-rule-fix-20260527.backup
post-mgmt-rule-fix-20260527.rsc
pre-thor-lacp-20260527-mainthread.backup
pre-thor-lacp-20260527-mainthread.rsc
```

Validate switch-side state:

```routeros
/interface bonding monitor bond-thor-podman once
/interface bonding monitor bond-thor-kata once
/interface bonding monitor-slaves bond-thor-podman once
/interface bonding monitor-slaves bond-thor-kata once
/interface ethernet monitor qsfpplus2-1,qsfpplus2-2,qsfpplus2-3,qsfpplus2-4 once
/interface bridge port print terse where interface~"bond-thor"
```

Expected:

- both bonds are running;
- all four members are active/partner/synchronized/collecting/distributing;
- all four physical links negotiate the same speed and full duplex;
- `bond-thor-podman` and `bond-thor-kata` are bridge members on `bridge0`;
- CRS354 management remains reachable.

## CRS354 Backout

Use serial if management is not reachable:

```routeros
/interface bridge port remove [find where interface="bond-thor-podman"]
/interface bridge port remove [find where interface="bond-thor-kata"]
/interface bonding remove [find where name="bond-thor-podman"]
/interface bonding remove [find where name="bond-thor-kata"]
/interface bridge port add bridge=bridge0 interface=qsfpplus2-1 comment="rollback Thor lane 1"
/interface bridge port add bridge=bridge0 interface=qsfpplus2-2 comment="rollback Thor lane 2"
/interface bridge port add bridge=bridge0 interface=qsfpplus2-3 comment="rollback Thor lane 3"
/interface bridge port add bridge=bridge0 interface=qsfpplus2-4 comment="rollback Thor lane 4"
```

## Thor iperf3 Validation

Copy `scripts/thor-ovs-cross-bridge-iperf.sh` to Thor and run it as root after
CRS354 LACP is up:

```bash
./thor-ovs-cross-bridge-iperf.sh --parallel 1 --duration 30 \
  --json-out /root/thor-cross-bridge-iperf-p1.json

./thor-ovs-cross-bridge-iperf.sh --parallel 8 --duration 60 \
  --json-out /root/thor-cross-bridge-iperf-p8.json
```

The script creates temporary namespaces and veth ports:

```text
thor_kata_test 172.31.254.2/24 -> br-kata0
thor_pod_test  172.31.254.3/24 -> br-podman0
```

It refuses to run by default if either OVS bond still reports disabled LACP
members. Use `--allow-lacp-down` only for negative-path diagnostics.
The default iperf3 test port is `55201` so validation does not collide with a
host-level iperf3 daemon on TCP/5201. The client is wrapped with a bounded
timeout of test duration plus 20 seconds so OVS hairpin failures do not leave a
hung validation run.

The test attempts to reduce one class of false-negative TCP failures caused by
MAC-learning pollution by pinning temporary endpoint MAC addresses to the
correct local OVS veth ports with high-priority OpenFlow rules. If ICMP passes
but TCP still fails, treat the result as an OVS same-host hairpin diagnostic,
not as a switch throughput result.

Record:

- ping min/avg/max/mdev from the script pre-check;
- iperf3 JSON errors, if any;
- single-stream iperf3 throughput;
- eight-stream aggregate throughput;
- OVS `bond/show` output for both bonds before and after;
- OVS datapath/FDB anomalies if ICMP passes but TCP fails;
- CRS354 `monitor` and `monitor-slaves` output for both bonds.

### 2026-05-27 Same-Host Hairpin Result

Restored topology state:

```text
CRS354 bridge fast path: enabled
CRS354 Thor bridge ports: hardware offload enabled
CRS354 Thor bond hash: layer-2
Thor OVS bond mode: balance-tcp
Thor OVS LACP: negotiated on both bonds
```

The harness ping pre-check passed across
`br-kata0 -> CRS354 -> br-podman0`:

```text
10 packets transmitted, 10 received, 0% packet loss
rtt min/avg/max/mdev = 0.586/1.566/2.108/0.471 ms
```

TCP iperf3 did not produce a valid performance result in the same-host hairpin
topology. The bounded client run exited with status `124` and iperf3 JSON
reported `"interrupt - the client has terminated"`. Packet tracing showed SYNs
leaving the Kata-side namespace and physical MGBE member, reaching/returning
from CRS354 on a Podman-side physical member, but not being delivered to the
Podman-side namespace. OVS FDB state also showed remote endpoint MACs learned on
the bond port in both bridges. Temporary static OpenFlow output rules did not
make TCP reliable.

Operational decision:

- keep the CRS354 LACP and Thor OVS bond configuration in place;
- do not use the same Thor host as both traffic endpoints for acceptance
  throughput testing;
- validate throughput with two distinct endpoints, or with a routed/VLAN split
  that avoids the same-host two-bridge L2 hairpin.

## TRex And Kata Gate

Do not bind Thor `mgbe*` ports to DPDK while those ports are carrying OVS bridge
traffic. The referenced TRex DPDK container path requires UIO or VFIO devices
and the helper explicitly removes a NIC from the host network stack when binding
it to DPDK. That is incompatible with testing `br-kata0 -> CRS354 ->
br-podman0` on the same physical ports.

Acceptable TRex paths:

- use a dedicated passthrough NIC or SR-IOV VF that is not part of the OVS
  bridge topology;
- use a non-DPDK/kernel-stack traffic generator first for bridge validation;
- defer TRex DPDK until Kata runtime, hugepages, IOMMU grouping, and dedicated
  NIC ownership are proven.
- run the first load test across two distinct endpoints instead of the
  same-host Thor bridge hairpin.

Docker is not an acceptable implementation detail for this fleet. If the TRex
container artifact is reused, run it through an OCI-compatible non-Docker
runtime and preserve the VFIO/UIO device requirements explicitly.

## MIG And vGPU Gate

Current Thor GPU state:

```text
GPU: NVIDIA Thor
driver: 580.00
MIG mode: Disabled
GPU virtualization mode: None
Host vGPU mode: N/A
```

Do not enable MIG during live Ollama/Open WebUI service use. Enabling MIG can
change GPU partitioning and may interrupt active CUDA workloads.

Before creating a Rocky 10 QEMU/Kata guest with vGPU slices, validate all of the
following:

- NVIDIA vGPU Manager support exists for the Thor host stack;
- the host exposes mediated-device or SR-IOV vGPU interfaces;
- guest NVIDIA driver and licensing requirements are understood;
- `nvidia-smi -q` reports a vGPU-capable host mode;
- rollback restores full-GPU Ollama/Open WebUI service.

Current Thor evidence does not expose `/sys/class/mdev_bus`,
`mdev_supported_types`, or SR-IOV VF controls for the GPU, so vGPU assignment is
blocked until the NVIDIA vGPU host stack is installed and validated.

## LLM Performance Follow-Up

After vGPU is proven, run the standardized LLM test suite from:

```text
https://github.com/yukon-systems/AiOps_LLM-Perf__deepeval/
```

Capture:

- guest OS and kernel;
- assigned vGPU/MIG profile;
- NVIDIA driver and CUDA runtime;
- model name and quantization;
- tokens/sec, latency percentiles, and GPU utilization;
- deepeval result artifact path.
