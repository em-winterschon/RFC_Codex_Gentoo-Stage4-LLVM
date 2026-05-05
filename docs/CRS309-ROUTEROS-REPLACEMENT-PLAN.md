# CRS309 RouterOS Replacement And Spine Aggregation Plan

## 2026-05-04 Current State

The `CCR2004-16G-2S+PC` has replaced the CRS309 as the active RFC99 gateway.
It is running RouterOS package and RouterBOARD firmware `7.22.2`; WAN DHCP,
LAN routing, DNS, NAT, HTTPS, API-SSL, and remote syslog have passed
post-upgrade validation.

The CRS309 should no longer be treated as the primary gateway target. Its next
role is a RouterOS 10GbE L2/L3 aggregation spine between:

- CCR2004 `sfp-sfpplus2` and CRS309 `sfp-sfpplus1`
- CRS354 LACP uplink and CRS309 `sfp-sfpplus2` plus `sfp-sfpplus3`
- CSS326 `sfp1` and CRS309 `sfp-sfpplus8`
- Hasslehoff CCR2004-1G-2XS-PCIe DAC links and CRS309 high-speed ports

There is one requested port-map conflict: CRS309 `sfp-sfpplus3` was assigned to
both the CRS354 LACP bundle and the Hasslehoff CCR2004-1G-2XS-PCIe DAC pair.
The normalized plan keeps CRS354 on `sfp-sfpplus2` plus `sfp-sfpplus3`, moves
Hasslehoff to `sfp-sfpplus4` plus `sfp-sfpplus5`, and leaves `sfp-sfpplus6`
plus `sfp-sfpplus7` reserved.

Detailed implementation plan:

```text
docs/superpowers/plans/2026-05-04-crs309-spine-aggregation.md
```

## Source Inputs

Reviewed operator files:

```text
/tmp/crs309-router-mode-idc.wip.rsc
/tmp/rfc99-sun99-host-networking.md
```

No live RouterOS changes should be made from the WIP script until admin access,
serial fallback, backups, management-only bootstrap, and NetBox staging are all
confirmed.

Update: a rackable MikroTik `CCR2004-16G-2S+PC` is now the active
replacement-router target. Keep the old CRS309 router script only as historical
source material; future CRS309 work should target the spine aggregation plan.

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

For the CCR2004 replacement path, translate the CRS309 assumptions after serial
inventory. The initial expected hardware identity is:

- manufacturer: `MikroTik`
- model class: `CCR2004-16G-2S+PC`
- credential source: Ansible Vault variables
  `vault_rfc99_ccr2004_16g_admin_user` and
  `vault_rfc99_ccr2004_16g_admin_password`

## CCR2004 Serial Discovery

Serial console is available at `/dev/ttyUSB2` with `115200` baud. The first
serial discovery snapshot is archived outside the repository under:

```text
/root/operator-private/routeros/ccr2004-16g/20260504T013200Z/
```

Observed facts:

- RouterOS version: `7.19.6`
- architecture: `arm64`
- board-name/model reported by RouterOS: `CCR2004-16G-2S+`
- CPU count: `4`
- memory: `4096 MiB`
- factory default IP: `192.168.88.1/24` on `ether15`
- physical ports: `ether1` through `ether16`, `sfp-sfpplus1`, `sfp-sfpplus2`
- default services currently enabled broadly: SSH, telnet, FTP, HTTP, WinBox,
  API, and API-SSL; HTTPS is disabled

Do not attach this router to production L2 until a management-only bootstrap
restricts services, sets the intended identity, moves management onto the
confirmed management interface/IP, and exports a fresh post-bootstrap config.

## CCR2004 Rendered Configuration Role

The physical replacement path now has a render-only Ansible role:

```text
roles/routeros_rfc99_gateway
playbooks/routeros-rfc99-gateway.yml
docs/workflows/stage4-routeros-rfc99-gateway-deployment.json
```

The role translates the CRS309 WIP intent to the CCR2004 hardware map:

- `sfp-sfpplus1` is WAN uplink.
- `sfp-sfpplus2` is the LAN switch uplink and VLAN trunk.
- `ether1` through `ether16` are renamed to `ge1` through `ge16`.
- SSH, HTTPS, and API-SSL are enabled and restricted to management CIDRs.
- telnet, FTP, HTTP, plaintext API, and WinBox are disabled by default.
- The self-signed RouterOS certificate is used until internal-CA automation is
  wired into RouterOS imports.
- The overlapping CRS309 `172.16.228.0/22` declarations are normalized to only
  `172.16.228.1/22`.

The role does not apply live changes. Review the generated `.rsc` and JSON
manifest first, then add a separately gated serial or SSH import only after
backup/export and rollback paths are confirmed.

Render the local target:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACKS_ENABLED=control_flow \
  ../../scripts/with-ansible-vault-env.sh ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/routeros-rfc99-gateway.yml \
  -l gw_rfc99_mkccr2004_16g \
  -e routeros_rfc99_gateway_render_root=/tmp/routeros-rfc99-gateway
```

The original CRS309 gateway draft intended:

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

Do not apply this original gateway draft to the CRS309. The active routed edge
is now the CCR2004; CRS309 should be rebuilt as a spine/aggregation switch with
only management IP and optional future L3 offload after L2 validation.

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

1. Keep `gw_rfc99_mkcrs309` staged as a planned RouterOS device with manufacturer
   `MikroTik` and device type `CRS309-1G-8S+IN`.
2. Keep `gw_rfc99_mkccr2004_16g` staged as the preferred replacement RouterOS
   device with manufacturer `MikroTik` and device type `CCR2004-16G-2S+PC`.
3. Model physical interfaces:
   - `ether1`
   - `sfp-sfpplus1`
   - `sfp-sfpplus2` through `sfp-sfpplus8`
   - `br-lan`
   - `wg-srv`
   - optional `zt-idc`
4. For the CCR2004 path, replace the CRS309 physical interface list with the
   serial-discovered CCR2004 interface list before live NetBox apply.
5. Import prefixes in planned state first.
6. Attach gateway IPs to the selected replacement device only after the serial
   bootstrap and management-only phase are validated.
7. Record overlapping or duplicate prefix conditions as blockers.
8. Record firewall zones:
   - `WAN`
   - `LAN`
   - `MGMT`
   - `VPN`
9. Add service records for HTTPS/API management, SNMP, WireGuard, and optional
   ZeroTier.
10. Run NetBox dry-run apply.
11. Apply only after the dry-run has no duplicate-prefix or missing-site
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

- CRS309 has been superseded by a planned CCR2004-16G-2S+PC replacement target;
  serial discovery is required before rendering device-specific port mappings.
- CRS309 admin login is not currently usable; reset or serial recovery is still
  required if the CRS309 is used as a fallback target.
- CRS309 `WAN_NET_MAC` and `LAN_NET_MAC` values are unset in the source plan.
- Overlapping `172.16.228.0/22` gateway declarations must be normalized.
- The CRS309 draft enables broad SNMP v2c access with community `public`; this
  should be replaced with vaulted SNMPv3 or limited tightly before permanent
  operation.
- The script contains duplicate certificate-generation sections; consolidate
  before execution.
- The script leaves HTTP and API enabled; decide whether that is temporary
  recovery posture or intentional management policy.
