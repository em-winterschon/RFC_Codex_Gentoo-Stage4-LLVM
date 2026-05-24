# M70 Bond Cutover Closeout - 2026-05-24

## Result

M70 management was moved from standalone `netboot0` to `bond0` with
`172.16.99.70/24` and the default route on `bond0`. The live bond mode is
`active-backup`, not `802.3ad`, because CSS326 SwOS LACP write automation is not
yet validated. `netboot0` is the active primary slave; `enp3s0` is the backup
slave.

## Validation

- SSH to `172.16.99.70` returned after the cutover, and the rollback sentinel
  was written before the 180-second watchdog restored the old config.
- `ping -c 2 172.16.99.1` from M70 returned 0% packet loss.
- `ping -c 2 192.168.132.1` from M70 returned 0% packet loss after
  `openvpn.fmt2` was restarted.
- `bond0` reports `active-backup`, active slave `netboot0`, backup slave
  `enp3s0`, both 1G/full.
- `net.netboot0` was removed from the default runlevel after cutover; it was not
  stopped live because `netboot0` is the active bond slave.
- `eno2` has no `10.64.64.70/24` address.

## X553 To CCR2004 Mapping

After `arping` L2 probes from the unnumbered X553 ports, CCR2004 `br-lan` FDB
learned the following mapping:

| M70 NIC | MAC | CCR2004 Port |
| --- | --- | --- |
| `eno1` | `00:07:32:78:65:C8` | `ge3` |
| `eno2` | `00:07:32:78:65:C9` | `ge4` |
| `eno3` | `00:07:32:78:65:CA` | `ge5` |
| `eno4` | `00:07:32:78:65:CB` | `ge6` |

All four CCR2004 ports reported `link-ok`, 1Gbps, full duplex, with flow control
off.

## Follow-Up

The remaining throughput target is to switch `bond0` from `active-backup` to
`802.3ad` after CSS326 LACP group membership can be safely changed from the old
`ge17/ge18` assumption to `ge14/ge17`. Until then, keep `active-backup` as the
safe management state.
