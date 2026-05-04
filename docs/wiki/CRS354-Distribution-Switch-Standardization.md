# CRS354 Distribution Switch Standardization

Live CRS354 discovery was captured from serial console `/dev/ttyUSB1` and
archived outside the repo:

```text
/root/operator-private/routeros/crs354/20260504T194533Z
```

Observed state:

- identity: `sw-mgmt-mkcrs354`
- model: `CRS354-48G-4S+2Q+`
- serial number: `HJV0AWTYBCD`
- RouterOS package and RouterBOARD firmware: `7.22.2`
- management IP/interface: `172.16.99.7/24` on `ether49`
- existing QNAP archive LACP: `bond-qnap` over `sfp-sfpplus3,sfp-sfpplus4`
- stale OPNsense address: `172.16.254.7/24` on `sfp-sfpplus1`, disabled
  during the 2026-05-04 LACP cutover

## Media Policy

Unless a link record explicitly says otherwise, 10G SFP+ optics are `10G-SR`
over MMF. No SMF optics are currently in use. Known 10G-SR optic SKUs are
FS.com `SFP-10GSR-85` and 10Gtek `AXS85-192-M3`. DAC links may be generic,
Arista-compatible, Intel-compatible, or Juniper-compatible.

## Intended Port Map

| CRS354 interface | Target | Media | State |
| --- | --- | --- | --- |
| `ether49` | management network | copper | active management |
| `sfp-sfpplus1` | CRS309 `sfp-sfpplus2` | 10G-SR MMF | active LACP member |
| `sfp-sfpplus2` | CRS309 `sfp-sfpplus3` | 10G-SR MMF | active LACP member |
| `sfp-sfpplus3` | QNAP TS435XEU SFP+ 1 | 10G DAC | existing `bond-qnap` member |
| `sfp-sfpplus4` | QNAP TS435XEU SFP+ 2 | 10G DAC | existing `bond-qnap` member |
| `qsfpplus1` | future RoCE-v2 RDMA fabric | 40G QSFP+ | disconnected |
| `qsfpplus2` | future RoCE-v2 RDMA fabric | 40G QSFP+ | disconnected |

Full change, validation, and backout commands live in:

```text
docs/CRS354-DISTRIBUTION-SWITCH-STANDARDIZATION.md
```

## 2026-05-04 Live Validation

Evidence archive:

```text
/root/operator-private/routeros/lacp-cutover/20260504T210857Z
```

CRS309 `bond-crs354` and CRS354 `bond-crs309` are both RouterOS `802.3ad`
with both member links active at `10Gbps` full duplex. All four optics are
FS.com `SFP-10GSR-85`; no RX loss or TX fault is present. Management ping
validation passed to both `172.16.99.7` and `172.16.99.8`.
