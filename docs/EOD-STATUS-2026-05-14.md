# EOD Status 2026-05-14

## Completed

- Validated the M70 Forge admin host cabling against CSS326 using host link
  state, SwOS snapshots, and SNMP bridge FDB evidence:
  - `netboot0` / `00:07:32:78:65:C6` -> CSS326 `ge14`
  - `enp3s0` / `00:07:32:78:65:C7` -> CSS326 `ge17`
  - `eno1` / `00:07:32:78:65:C8` -> CSS326 `ge18`
- Enabled CSS326 LACP group 2 on `ge17/ge18` and brought up M70 `bond0` as
  an unnumbered `802.3ad` bond with `lacp_rate=fast`, `miimon=100`, and
  `xmit_hash_policy=layer3+4`.
- Validated M70 `bond0`: both members are in one active aggregator, partner MAC
  is CSS326 `f4:1e:57:89:af:be`, partner key is `2`, and management routing
  remains on `netboot0` via `172.16.99.1`.
- Made the M70 bond persistent through `/etc/conf.d/net` and enabled
  `net.bond0` for the default OpenRC runlevel. The live bond remains manually
  created until the next planned reboot validates service-managed startup.
- Captured and encrypted the post-change CSS326 SwOS backup:
  `/root/operator-private/swos/sw_mgmt_css326/20260515T030821Z`.
- Fixed Codex command-output noise from `.bash_profile`: `intelli-shell init`
  now only runs for interactive TTY shells, stopping non-interactive `bind -x`
  warnings while preserving interactive shell hotkeys.
- Applied the approved BigNetwork SDWAN_NET changes:
  - Edge Lite `ab4af90f44` static overlay IP assignment `172.17.170.200`
  - Route `172.17.17.0/24 via 172.17.170.200`
  - Route `172.18.20.0/24 via 172.17.170.200`
- Validated BigNetwork route propagation on M70: both new routes appeared via
  `bnlj6dscrj` with static metric `5000`.

## Current Gates

- BigNetwork is not yet end-to-end reachable. M70 sends traffic over
  `bnlj6dscrj`, Edge Lite ARPs back for `172.17.170.214`, but no ICMP/TCP
  replies were observed from `172.17.170.200`, `172.17.17.1`,
  `172.17.17.2`, `172.18.20.4`, or `172.18.20.5`.
- The Edge Lite applied config only models local `OOB_NET` as
  `172.17.17.0/24`; forwarding to `172.18.20.0/24` still needs FMT2-side
  route/firewall validation or an Edge Lite config update.
- M70 `bond0` is intentionally unnumbered. Do not attach VM bridges or assign
  service IPs until we pick a staging VLAN/IP plan.
- X12AGAIN must remain online until Forge continuity, backup coverage, and
  replacement automation-admin capacity are validated.

## Technical Assessment

- The M70 `igb` ports are best treated as stable management and simple L2/L3
  access. They are low-risk, low-power, and adequate for control-plane traffic.
- The X553 `ixgbe` ports are useful for lab SR-IOV and queue lifecycle work.
  They expose VFs and enough queue capability to validate automation patterns,
  but they should not be treated as high-performance data-plane NICs.
- After Forge moves to the X11SCL-iF, the best M70 role is a low-power
  infrastructure edge node: SD-WAN client, small VM/container evacuation target,
  HAProxy/Nginx TLS/QAT experiments, firewall/packet-inspection tests, SLURM
  helper node, and SR-IOV validation host.

## Outstanding Actions

1. Decide the VLAN/IP plan for M70 `bond0` before hosting VMs or containers on
   it.
2. Validate M70 `net.bond0` service-managed startup at a planned reboot gate.
3. Debug the BigNetwork Edge Lite forwarding path with FMT2-side visibility:
   route back to `172.17.170.0/24`, local firewall behavior, and whether
   `172.18.20.0/24` is reachable from the Edge Lite LAN.
4. Continue Forge continuity migration planning from X12AGAIN to M70, then to
   the X11SCL-iF once the heatsink and chassis work are complete.
5. Prepare Hasslehoff scheduled backup design and implementation work.

## Backout Summary

- M70 management is independent of the new LACP bond and still uses
  `netboot0` on CSS326 `ge14`. If `bond0` causes issues, remove `net.bond0`
  from the default runlevel and clear the Forge block in `/etc/conf.d/net`.
- CSS326 LACP backout is to set `ge17/ge18` LAG mode back to passive and group
  back to `0`; latest encrypted backup is staged from snapshot
  `20260515T030821Z`.
- BigNetwork route backout is to remove `172.17.17.0/24` and `172.18.20.0/24`
  from SDWAN_NET routes and remove the Edge Lite static assignment
  `172.17.170.200`.
