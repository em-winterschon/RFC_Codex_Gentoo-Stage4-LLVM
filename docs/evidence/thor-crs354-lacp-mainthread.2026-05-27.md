# Thor CRS354 LACP Main-Thread Evidence - 2026-05-27

## Scope

This record captures the main-thread continuation after the side-thread CRS354
handoff. The goal was to restore CRS354 management, apply Thor AGX peer LACP on
`qsfpplus2`, validate Thor OVS LACP state, and determine whether the planned
same-host cross-bridge iperf path is a valid performance test.

## Handoff Reference

FCP handoff:

```text
/home/forge1/src/agentic-forge-control-plane/reports/handoffs/2026-05-27-side-thread-crs354-qnap-standards-handoff.md
```

FCP memory event:

```text
f81df74d-3dd2-4a81-a86d-b95b0ac7c216
```

## CRS354 Management Fix

CRS354 had the expected management IP on `ether49`:

```text
172.16.99.7/24 interface=ether49
```

Root cause for failed M70 management reachability was a routing rule:

```text
/routing rule add action=lookup-only-in-table src-address=172.16.99.7/32 table=mgmt comment=mgmt-source-rule
```

The `mgmt` table had a default route but no connected `172.16.99.0/24` route,
so same-subnet replies sourced from `172.16.99.7` were routed to the gateway
instead of directly to the M70 source MAC. The rule was disabled:

```routeros
/routing rule disable [find where comment="mgmt-source-rule"]
```

Validation from M70:

```text
ping 172.16.99.7: 3/3 packets received
TCP 22: reachable
TCP 80: reachable
TCP 443: reachable
TCP 8291: reachable
```

## CRS354 Thor LACP

Applied RouterOS `802.3ad` bonds:

```text
bond-thor-podman: qsfpplus2-1,qsfpplus2-2, lacp-rate=1sec, lacp-mode=active
bond-thor-kata:   qsfpplus2-3,qsfpplus2-4, lacp-rate=1sec, lacp-mode=active
```

Final restored switch state:

```text
bridge0 fast-forward: yes
bridge allow-fast-path: yes
bridge DHCP snooping: yes
bridge option82 insertion: yes
bond-thor-podman bridge port: hw=yes
bond-thor-kata bridge port: hw=yes
bond transmit-hash-policy: layer-2
l3-hw-offloading: yes
qos-hw-offloading: yes
mgmt-source-rule: disabled
```

## Thor OVS State

Thor OVS bonds were restored to `balance-tcp` after diagnostics:

```text
bond-podman0: lacp_status=negotiated, mgbe0_0 enabled, mgbe1_0 enabled
bond-kata0:   lacp_status=negotiated, mgbe2_0 enabled, mgbe3_0 enabled
```

Temporary test ports and namespaces were removed after validation:

```text
br-podman0 ports: bond-podman0
br-kata0 ports: bond-kata0
ip netns list: empty
```

## Same-Host Hairpin Validation

The harness ping pre-check passed across the intended path:

```text
br-kata0 namespace -> CRS354 -> br-podman0 namespace
10 packets transmitted, 10 received, 0% packet loss
rtt min/avg/max/mdev = 0.586/1.566/2.108/0.471 ms
```

TCP iperf3 did not produce a valid throughput result in the same-host hairpin
topology. The updated harness exits under its own bounded timeout; the live
short run exited with status `124`, iperf3 stderr emitted its pthread failure
path, and iperf3 JSON reported:

```text
"error": "interrupt - the client has terminated"
```

Earlier packet tracing showed SYNs leaving the Kata-side namespace and MGBE
member, reaching/returning on a Podman-side physical MGBE member, but not being
delivered into the Podman-side namespace. OVS FDB state showed remote endpoint
MACs learned on the bond port in both bridges. Temporary static OpenFlow output
rules did not make TCP reliable.

Operational decision:

- keep the CRS354 LACP and Thor OVS bond configuration;
- do not treat the same-host OVS bridge hairpin as an acceptance throughput
  test;
- use two distinct endpoints, or a routed/VLAN split, for the next performance
  validation.

## Package Actions

`tcpdump` was installed on Thor for packet-path localization.
