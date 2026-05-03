# CRS309 RouterOS Replacement Plan

## Source Inputs

Reviewed available operator file:

```text
/tmp/crs309-router-mode-idc.wip.rsc
```

The referenced host/networking inventory file was not present at:

```text
/tmp/rfc99-sun99-host-networking.md
```

No live RouterOS changes should be made from the WIP script until the missing
host/networking file is available or the intended device, ports, prefixes, and
rollback path are confirmed another way.

## Immediate Assessment

The CRS309 script is a destructive replacement-router import. It starts by
backing up and exporting the current configuration, then removes bridge ports,
bridges, IP addresses, DHCP clients, firewall filters, NAT rules, RIP, and the
existing WireGuard server before rebuilding the router.

The target hardware check expects:

- model class: `CRS309-1G-8S+IN`
- required ports:
  - `ether1`
  - `sfp-sfpplus1` through `sfp-sfpplus8`

The intended high-level design is:

- `sfp-sfpplus1` as WAN uplink
- `ether1` as dedicated management
- `sfp-sfpplus2` through `sfp-sfpplus8` as LAN bridge members
- `br-lan` as routed LAN bridge with many gateway addresses
- DHCP client on WAN
- source NAT/masquerade out WAN
- baseline firewall input/forward rules
- SNMP enabled for broad RFC1918 management ranges
- WireGuard server scaffold
- optional ZeroTier controller/interface scaffold when package and device-mode
  support exist
- RIP instance redistributing connected/static routes on `br-lan`

## Prefixes Declared By The CRS309 Draft

| Purpose | Gateway/Prefix | Interface |
| --- | --- | --- |
| Management primary | `10.128.128.1/24` | `ether1` |
| REDNET-WAN | `10.192.254.1/24` | `br-lan` |
| NPi-Cluster CephNet | `10.232.232.1/24` | `br-lan` |
| TestNet | `172.16.0.1/24` | `br-lan` |
| VMM route | `172.16.17.1/24` | `br-lan` |
| DHCP traffic | `172.16.20.1/24` | `br-lan` |
| DHCP Admin traffic | `172.16.22.1/24` | `br-lan` |
| SFO200 legacy remote admin | `172.16.40.1/24` | `br-lan` |
| Sensor network route | `172.16.66.1/24` | `br-lan` |
| LAN gateway primary | `172.16.88.1/24` | `br-lan` |
| LAN gateway alternate | `172.16.99.1/24` | `br-lan` |
| IPMI traffic | `172.16.199.1/24` | `br-lan` |
| NPi-Cluster traffic | `172.16.228.1/22` | `br-lan` |
| NPi-Cluster traffic | `172.16.229.1/22` | `br-lan` |
| NPi-Cluster traffic | `172.16.230.1/22` | `br-lan` |
| iSCSI traffic | `172.16.254.1/24` | `br-lan` |
| Yukon L2 network core | `172.28.0.1/16` | `br-lan` |
| Yukon L3 metal hosts | `172.28.10.1/24` | `br-lan` |
| Yukon app front-end | `172.28.20.1/24` | `br-lan` |
| Yukon app front-end pods | `172.28.25.1/24` | `br-lan` |
| Yukon app back-end | `172.28.30.1/24` | `br-lan` |
| Yukon app back-end pods | `172.28.35.1/24` | `br-lan` |
| Yukon GPU nodes | `172.28.40.1/24` | `br-lan` |
| WireGuard server subnet | `172.31.255.1/24` | `wg-srv` |

The `172.16.228.1/22`, `172.16.229.1/22`, and `172.16.230.1/22` gateway entries
overlap the same `172.16.228.0/22` prefix. Treat that as a design issue to
resolve before NetBox import or RouterOS execution.

## Required Preflight

1. Confirm physical device identity by serial console or management interface.
2. Export the current CRS309 configuration with hidden sensitive values.
3. Save a binary backup and a text export outside the repo under an
   operator-private path.
4. Confirm cabling:
   - WAN on `sfp-sfpplus1`
   - management on `ether1`
   - LAN members on `sfp-sfpplus2` through `sfp-sfpplus8`
5. Confirm whether the WAN uplink is DHCP or static.
6. Confirm whether `172.16.99.1/24` can replace or coexist with the current
   management gateway.
7. Decide whether temporary HTTP and API cleartext services remain enabled
   during recovery or are disabled immediately after TLS validation.
8. Decide whether SNMP v2c community `public` is acceptable during migration or
   must be replaced by vaulted SNMPv3 credentials before rollout.
9. Decide whether RIP is still required, or whether static routes or OSPF/BGP
   should replace it for the wider fabric.

## NetBox Staging Sequence

1. Create a `sun99` or equivalent site record only after the missing
   `/tmp/rfc99-sun99-host-networking.md` source is available.
2. Add `gw-sun99-mkcrs309` as a planned RouterOS device with manufacturer
   `MikroTik` and device type `CRS309-1G-8S+IN`.
3. Model physical interfaces:
   - `ether1`
   - `sfp-sfpplus1`
   - `sfp-sfpplus2` through `sfp-sfpplus8`
   - `br-lan`
   - `wg-srv`
   - optional `zt-idc`
4. Import prefixes in planned state first.
5. Attach gateway IPs to `gw-sun99-mkcrs309`.
6. Record overlapping or duplicate prefix conditions as blockers.
7. Record firewall zones:
   - `WAN`
   - `LAN`
   - `MGMT`
   - `VPN`
8. Add service records for HTTPS/API management, SNMP, WireGuard, and optional
   ZeroTier.
9. Run NetBox dry-run apply.
10. Apply only after the dry-run has no duplicate-prefix or missing-site
    findings.

## RouterOS Execution Sequence

1. Connect serial console and keep it attached for the entire change.
2. Validate the WIP script against the device model check without applying
   destructive sections.
3. Save pre-change backup and export:
   - `/system backup save name=pre-crs309`
   - `/export file=pre-crs309 hide-sensitive`
4. Copy backups off-device.
5. Apply a management-only bootstrap first:
   - set identity
   - configure `ether1` management IP
   - enable SSH
   - restrict management firewall input
   - verify API/HTTPS if required
6. Apply WAN DHCP and confirm default route.
7. Add `br-lan` and only one non-critical LAN member first.
8. Add one gateway prefix at a time.
9. Validate host reachability for each prefix before adding the next group.
10. Add NAT and firewall forward rules.
11. Add WireGuard scaffold only after LAN/WAN validation passes.
12. Add ZeroTier only if the package, device-mode support, and controller
    requirements are validated on the physical CRS309.
13. Add RIP only after route redistribution scope is confirmed.
14. Disable cleartext management services when TLS and SSH access are verified.

## Validation Gates

Required pass/fail checks:

- serial console still reachable
- SSH reachable from management subnet
- WebFig/API reachable only from intended management source
- WAN DHCP has lease, gateway, and DNS behavior
- default route installed
- gateway IPs pingable from same-segment hosts
- LAN-to-WAN NAT works
- WAN-to-router direct input is dropped except intentional VPN/control traffic
- NetBox prefixes and gateway IPs match RouterOS export
- RouterOS export after change is archived under operator-private storage

## Rollback

The rollback path is:

1. Keep console access open.
2. Restore the pre-change binary backup if management is lost.
3. Reboot RouterOS.
4. If backup restore fails, use serial recovery or Netinstall workflow.
5. Keep the current QEMU RouterOS or upstream gateway path available until
   CRS309 LAN/WAN validation passes.

## Blockers

- `/tmp/rfc99-sun99-host-networking.md` is missing on-host at review time.
- Overlapping `172.16.228.0/22` gateway declarations must be normalized.
- The CRS309 draft enables broad SNMP v2c access with community `public`; this
  should be replaced with vaulted SNMPv3 or limited tightly before permanent
  operation.
- The script contains duplicate certificate-generation sections; consolidate
  before execution.
- The script leaves HTTP and API enabled; decide whether that is temporary
  recovery posture or intentional management policy.
