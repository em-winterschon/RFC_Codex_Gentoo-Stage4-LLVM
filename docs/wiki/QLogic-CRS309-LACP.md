# Hasslehoff QLogic To CRS309 LACP

## Cabling

Use the CRS309 ports previously reserved for the removed CCR2004-PCIe card:

| Hasslehoff Port | QLogic Function | CRS309 Port | Purpose |
| --- | --- | --- | --- |
| `enp4s0f0` | `0000:04:00.0` | `sfp-sfpplus4` | LACP member 1 |
| `enp4s0f1` | `0000:04:00.1` | `sfp-sfpplus5` | LACP member 2 |

The CRS309 render-only role now names this bundle
`bond-hasslehoff-qlogic`.

## Physical Validation

Both physical members validated on 2026-05-05 after replacing a failed optic:

| Host Port | CRS309 Port | Host State | CRS309 State | Notes |
| --- | --- | --- | --- | --- |
| `enp4s0f0` | `sfp-sfpplus4` | `10Gbps`, full, `LOWER_UP` | `link-ok`, `10Gbps`, full | Clean error counters |
| `enp4s0f1` | `sfp-sfpplus5` | `10Gbps`, full, `LOWER_UP` | `link-ok`, `10Gbps`, full | Clean error counters after optic replacement |

Validated optical receive levels:

- Host `enp4s0f0`: approximately `-0.82 dBm`
- Host `enp4s0f1`: approximately `-2.15 dBm`
- CRS309 `sfp-sfpplus4`: approximately `-3.416 dBm`
- CRS309 `sfp-sfpplus5`: approximately `-1.589 dBm`

The failed optic symptom was asymmetric: one side saw usable light while CRS309
received only marginal light around `-10.4 dBm`, preventing link-up.

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

Do not assume SR-IOV is available on the installed QLogic QL41232HOCU. The
current Hasslehoff presentation exposes no SR-IOV capability:

```text
/sys/bus/pci/devices/0000:04:00.0/sriov_totalvfs: absent
/sys/bus/pci/devices/0000:04:00.1/sriov_totalvfs: absent
lspci SR-IOV capability: absent
```

That makes the requested "one VF from each physical port" workstation design
impossible on the current card/firmware/kernel exposure.

The live fallback is:

```text
enp4s0f0 + enp4s0f1 -> bond-qlogic0 -> vmbr-qlogic0
bond mode: 802.3ad
bond hash: layer3+4
bridge: VLAN-aware, bridge-vids 2-4094
```

VMs attach normal virtio NICs to `vmbr-qlogic0` with explicit VLAN tags. The
first workstation GPU VM uses VLAN tags `1098` and `1099` for two high-speed
test NICs while retaining `net0` on the management bridge.

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

Live validation on 2026-05-06 showed both CRS309 members active in
`bond-hasslehoff-qlogic`, with the Linux partner system ID visible from
RouterOS and the Linux bridge `vmbr-qlogic0` up on Hasslehoff.
