# NetBox Device and Hetzner DNS Audit - 2026-05-22

Audit run from `admin_sun99_forge_099070` at `2026-05-22T04:02:57Z`.

## Scope

- Audited NetBox DCIM device primary IPv4 coverage.
- Populated missing NetBox IPAM DNS names where the canonical name was unambiguous.
- Bound unassigned management IP objects to explicit DCIM management interfaces.
- Validated Hetzner DNS records from both NetBox IPAM and inventory-intake.
- Created missing Hetzner DNS A records; no deletes were allowed or performed.

## NetBox Updates Applied

Live NetBox mutation summary:

- Interfaces created: 7
- Interfaces updated: 8
- IPAM rows updated: 19
- Device primary IPv4 pointers updated: 9
- Skipped writes: 0
- Errors: 0

Device management IPs bound and/or promoted to primary IPv4:

- `sw-border-sfo200-ein-2005` -> `172.18.20.5/24`
- `sw-ipmi-sfo200-ein-2004` -> `172.18.20.4/24`
- `sw-sfo200-7060cx32s-2010` -> `172.16.40.10/32`
- `gw-sfo200-pri` -> `10.200.99.2/24`
- `gw-sfo200-sec` -> `10.200.99.3/24`
- `gw_rfc99_mkcrs309` -> `172.16.99.1/24`
- `gw_rfc99_att_bgw320` -> `192.168.1.254/24`
- `sw_mgmt_css326` -> `172.16.99.6/24`
- `rtr_mgmt_ccr2004` -> `172.16.99.120/24`

DNS names corrected or populated on existing IPAM rows:

- `10.200.99.18/24` -> `kvm-sfo200-nasa-9918.rfc1918.host`
- `10.200.99.22/24` -> `kvm-sfo200-pri-9922.rfc1918.host`
- `10.200.99.23/24` -> `kvm-sfo200-sec-9923.rfc1918.host`
- `10.200.99.24/24` -> `kvm-sfo200-ter-9924.rfc1918.host`
- `172.16.99.7/24` -> `sw-mgmt-mkcrs354.rfc1918.host`
- `172.16.99.8/24` -> `sw-spine-crs309-rfc99.rfc1918.host`
- `172.16.99.13/24` -> `cls0-rfc99-nanoprime-099013.rfc1918.host`
- `172.16.99.63/24` -> `ipa01.rfc1918.host`
- `172.16.99.96/24` -> `msg-sun99-ntfysys-099096.rfc1918.host`
- `192.168.132.2/32` -> `admin-sun99-forge-099070-tun-fmt2.rfc1918.host`

## Hetzner DNS Updates Applied

The NetBox IPAM DNS plan had 7 missing A records and no conflicts. These records were created:

- `lap-sun99-chonkers.rfc1918.dev` A
- `admin-sun99-forge-099070-tun-fmt2.rfc1918.host` A
- `boot-sun99-netboot-099088.rfc1918.host` A
- `mcp-control-plane.rfc1918.host` A
- `nanoprime-ceph.rfc1918.host` A
- `obs-sun99-esstage-099091.rfc1918.host` A
- `vm-workstation-nscde-gpu01.rfc1918.host` A

Final Hetzner validation:

- NetBox IPAM plan: 46 records, 0 skipped, 46 unchanged, 0 errors.
- Inventory/CNAME plan: 44 records, 10 CNAME records, 44 unchanged, 0 errors.
- Deletes: 0.

## Source Fixes

Repository source-of-truth changes made to keep future applies from regressing the audit:

- Added missing `fqdn`, `management_interface`, and logical `mgmt` interface metadata for FMT2 and SUN99/RFC99 devices.
- Updated NetBox inventory apply logic to default device/service DNS names from inventory slugs when `fqdn` is omitted.
- Updated management-interface matching so `poe-management`, `pdu-management`, and similar purpose strings are treated as management interfaces.
- Prevented service VIP application from overwriting DNS names on IP objects already assigned to device or VM interfaces.
- Updated Hasslehoff reconcile logic so `nanoprime.rfc1918.host` remains a CNAME and the management A record is `cls0-rfc99-nanoprime-099013.rfc1918.host`.

## Remaining Device Primary IPv4 Gaps

NetBox now has primary IPv4 set for 25 of 40 DCIM devices. The remaining 15 are intentionally unresolved or represented elsewhere:

- VM/interface modeled in NetBox virtualization rather than DCIM primary: `obs_sun99_grafana_099066`, `obs_sun99_prometheus_099064`, `obs_sun99_vmetrics_099065`, `sched_sun99_slurmctl_099071`, `slurm_worker_node01`, `svc_container_services_safe_move_01`, `svc_identity_ipa01`, `svc_netbox_stage4`.
- Planned/offline or source intentionally lacks a management IP: `ctbsd_rfc99_jailerprime_099099`, `gw_rfc99_mkccr2004_16g`, `m70_canary`, `qnap_archive_ts435xeu`, `tty-console-sfo200-ein-2011`, `ups_sun99_cyberpower_cp1500`, `vpn_rfc99_fmt2_openvpn_bridge`.

The only remaining intake validation warning is pre-existing and expected: `sw-sfo200-7060cx32s-2010` uses `172.16.40.10`, which is outside declared FMT2 prefixes until that routing/prefix source is confirmed.
