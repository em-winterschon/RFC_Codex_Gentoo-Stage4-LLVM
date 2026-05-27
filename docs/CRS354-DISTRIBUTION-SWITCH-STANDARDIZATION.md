# CRS354 Distribution Switch Standardization

## Current Evidence

Live CRS354 discovery was captured from serial console and archived outside the
repo:

```text
/root/operator-private/routeros/crs354/20260504T194533Z
```

Observed state:

- identity: `sw-mgmt-mkcrs354`
- model: `CRS354-48G-4S+2Q+`
- serial number: `HJV0AWTYBCD`
- RouterOS package: `7.22.2`
- RouterBOARD firmware: `7.22.2`
- management IP: `172.16.99.7/24`
- management interface: `ether49`
- existing QNAP archive LACP: `bond-qnap` over `sfp-sfpplus3,sfp-sfpplus4`
- stale OPNsense address: `172.16.254.7/24` on `sfp-sfpplus1`, disabled
  during the 2026-05-04 LACP cutover
- stale inactive main-table default route: `172.16.254.1`, disabled during
  the 2026-05-04 LACP cutover

Follow-up serial verification on 2026-05-04 found those stale OPNsense objects
were still present after the initial cutover notes. They were disabled over
serial and revalidated with `bond-crs309` active on both LACP members.

## Media Policy

Unless a link record explicitly says otherwise:

- 10G SFP+ optics are `10G-SR`.
- Fiber is MMF.
- No SMF optics are currently in use.
- Known 10G-SR optic vendors are FS.com and 10Gtek.
- FS.com reference SKU: `SFP-10GSR-85`.
- 10Gtek reference SKU: `AXS85-192-M3`.
- 10G DAC links may be generic-compatible, Arista-compatible,
  Intel-compatible, or Juniper-compatible.

The current CCR2004-to-CRS309 link is validated with FS.com `SFP-10GSR-85`
optics over MMF at 10Gbps. The original Intel SR optic pair produced no link
and asymmetric receive power, so do not use those optics as the reference pair.

## Intended CRS354 Port Map

| CRS354 interface | Target | Media | State |
| --- | --- | --- | --- |
| `ether49` | management network | 100M/1G copper | active management |
| `sfp-sfpplus1` | CRS309 `sfp-sfpplus2` | 10G-SR MMF | active LACP member |
| `sfp-sfpplus2` | CRS309 `sfp-sfpplus3` | 10G-SR MMF | active LACP member |
| `sfp-sfpplus3` | QNAP TS435XEU SFP+ 1 | 10G DAC | existing `bond-qnap` member |
| `sfp-sfpplus4` | QNAP TS435XEU SFP+ 2 | 10G DAC | existing `bond-qnap` member |
| `qsfpplus1` | future RoCE-v2 RDMA fabric | 40G QSFP+ | disconnected |
| `qsfpplus2-1` | Thor AGX `mgbe0_0` | QSFP28 lane at 10G | planned `bond-thor-podman` member |
| `qsfpplus2-2` | Thor AGX `mgbe1_0` | QSFP28 lane at 10G | planned `bond-thor-podman` member |
| `qsfpplus2-3` | Thor AGX `mgbe2_0` | QSFP28 lane at 10G | planned `bond-thor-kata` member |
| `qsfpplus2-4` | Thor AGX `mgbe3_0` | QSFP28 lane at 10G | planned `bond-thor-kata` member |

Thor AGX `qsfpplus2` LACP work is tracked separately in
`docs/THOR-CRS354-LACP-PERF-RUNBOOK.md` because it has a distinct validation
path: `br-kata0 -> CRS354 -> br-podman0`.

The CRS309 side of the distribution LACP is `sfp-sfpplus2` plus
`sfp-sfpplus3`. The CRS354 side is `sfp-sfpplus1` plus `sfp-sfpplus2`.

## 2026-05-04 Live Validation

Post-change evidence was archived outside the repo:

```text
/root/operator-private/routeros/lacp-cutover/20260504T210857Z
```

Validated state:

- CRS309 `bond-crs354` is RouterOS `802.3ad` with active ports
  `sfp-sfpplus2` and `sfp-sfpplus3`.
- CRS354 `bond-crs309` is RouterOS `802.3ad` with active ports
  `sfp-sfpplus1` and `sfp-sfpplus2`.
- CRS309 was upgraded after the LACP cutover to RouterOS package and
  RouterBOARD firmware `7.22.2`; unused optional `container` and `zerotier`
  packages were removed first to recover CRS309 flash space.
- CRS309 bridge membership moved from individual `sfp-sfpplus2/3` ports to
  `bond-crs354` on `br-spine`.
- CRS354 bridge membership moved from individual `sfp-sfpplus2` to
  `bond-crs309` on `bridge0`.
- All four LACP slave links are `link-ok`, `10Gbps`, full duplex, FS.com
  `SFP-10GSR-85`, no RX loss, and no TX fault.
- Management reachability passed with `0%` packet loss to `172.16.99.7` and
  `172.16.99.8`.

## Planned RouterOS Change

Do not import these commands without the Hasslehoff CRS354 serial path attached
and a fresh pre-change export copied off-device.

Current serial source of truth is
`/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3W-if00-port0`; `/dev/ttyUSB1`
is only the observed current tty assignment.

CRS354:

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

CRS309:

```routeros
/export file=pre-crs309-crs354-lacp hide-sensitive
/interface bonding add name=bond-crs354 mode=802.3ad slaves=sfp-sfpplus2,sfp-sfpplus3 lacp-rate=1sec lacp-mode=active transmit-hash-policy=layer-2
/interface bridge port remove [find where interface="sfp-sfpplus2"]
/interface bridge port remove [find where interface="sfp-sfpplus3"]
/interface bridge port add bridge=br-spine interface=bond-crs354 comment="CRS354 distribution LACP"
/interface ethernet set sfp-sfpplus2 auto-negotiation=yes advertise=1G-baseX,10G-baseSR-LR comment="CRS354 LACP member 1, 10G-SR MMF"
/interface ethernet set sfp-sfpplus3 auto-negotiation=yes advertise=1G-baseX,10G-baseSR-LR comment="CRS354 LACP member 2, 10G-SR MMF"
```

## Validation

After cabling and import:

```routeros
/interface bonding monitor bond-crs309 once
/interface ethernet monitor sfp-sfpplus1,sfp-sfpplus2 once
/interface bridge port print terse where interface="bond-crs309"
```

Expected CRS354 state:

- `bond-crs309` is `running`.
- Both slave links show `link-ok`.
- Both links negotiate or force to `10Gbps` full duplex.
- `bond-crs309` is a bridge member on `bridge0`.
- Management remains reachable at `172.16.99.7`.

## Backout

Use CRS354 serial through Hasslehoff
`/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3W-if00-port0`:

```routeros
/interface bridge port remove [find where interface="bond-crs309"]
/interface bonding remove [find where name="bond-crs309"]
/interface bridge port add bridge=bridge0 interface=sfp-sfpplus2 comment="bridge0 uplink to basic switch, untagged only"
/ip address enable [find where interface="sfp-sfpplus1" and address="172.16.254.7/24"]
/ip route enable [find where comment="main-default-opnsense"]
```

If CRS309-side LACP was already imported, use CRS309 serial through Hasslehoff
`/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3X-if00-port0`:

```routeros
/interface bridge port remove [find where interface="bond-crs354"]
/interface bonding remove [find where name="bond-crs354"]
/interface bridge port add bridge=br-spine interface=sfp-sfpplus2 comment="temporary standalone CRS354 member"
/interface bridge port add bridge=br-spine interface=sfp-sfpplus3 comment="temporary standalone CRS354 member"
```
