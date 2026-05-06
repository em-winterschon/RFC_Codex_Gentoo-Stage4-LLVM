# Hasslehoff QLogic To CRS309 LACP

## Cabling

Use the CRS309 ports previously reserved for the removed CCR2004-PCIe card:

| Hasslehoff Port | QLogic Function | CRS309 Port | Purpose |
| --- | --- | --- | --- |
| `enp4s0f0` | `0000:04:00.0` | `sfp-sfpplus4` | LACP member 1 |
| `enp4s0f1` | `0000:04:00.1` | `sfp-sfpplus5` | LACP member 2 |

The CRS309 render-only role now names this bundle
`bond-hasslehoff-qlogic`.

## Linux Bond Recommendation

Initial host-side bond settings:

```text
mode 802.3ad
lacp_rate fast
miimon 100
xmit_hash_policy layer3+4
```

Use `layer3+4` because this link is primarily VM/container transit and should
spread multiple flows better than a pure L2 hash. Do not expect one TCP flow to
exceed one physical member.

## MTU

Keep MTU `1500` for first link-up and LACP validation. Move to `9000` only
after confirming CRS309, CRS354/CSS326 path, Linux bridge, VM NICs, and any
firewall/VIP path agree on jumbo frames.

## QLogic `qede` Tuning

The live Proxmox kernel exposes only the `qede debug` module parameter, so
there is no useful `/etc/modprobe.d/qede.conf` tuning to apply.

Useful post-link checks:

```bash
ethtool -l enp4s0f0
ethtool -g enp4s0f0
ethtool -k enp4s0f0
ethtool -c enp4s0f0
```

Suggested first-pass runtime tuning after the link is stable:

```bash
ethtool -L enp4s0f0 combined 4
ethtool -L enp4s0f1 combined 4
ethtool -G enp4s0f0 rx 4096 tx 8191
ethtool -G enp4s0f1 rx 4096 tx 8191
```

Rationale:

- Hasslehoff is a small-core Proxmox host, so `combined 4` is a better first
  test than maxing to `64`.
- TX rings are already at max on the observed driver; RX is `1023`, so RX ring
  expansion is the first practical test.
- Leave checksum, TSO, GSO, GRO, VLAN offloads, ntuple filters, and
  `hw-tc-offload` enabled unless a specific bridge/VLAN bug appears.

## SR-IOV

Do not combine host LACP and VM SR-IOV VFs as the default VM connectivity
model. For general VM networking, use the host bond and Linux bridge. Use SR-IOV
only for specific high-throughput VMs on explicit VLANs or direct paths because
VFs bypass much of the host bridge/bond behavior and complicate live migration,
firewalling, and observability.

## CRS309 RouterOS Intent

The render-only RouterOS role sets:

```text
bond-hasslehoff-qlogic
mode=802.3ad
slaves=sfp-sfpplus4,sfp-sfpplus5
lacp-rate=1sec
lacp-mode=active
transmit-hash-policy=layer-3-and-4
```

The rendered RSC should be reviewed before serial-gated import.
