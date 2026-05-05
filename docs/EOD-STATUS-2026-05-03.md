# EOD Status 2026-05-03

## Completed

- Added the render-only CCR2004 RouterOS RFC99 gateway role and pushed it.
- Rendered the real CCR2004 target config to `/tmp/routeros-rfc99-gateway/`.
- Added the CCR2004 swap plan with ITIL-style validation and backout gates.
- Added Hasslehoff backup tooling for Proxmox host configuration capture.
- Added Stage5 Nexus Repository OSS VM scaffolding pinned to local installer
  `3.90.1-01`.
- Added app version-lock tracking for Stage5 service applications and explicit
  `package_pins` metadata coverage.
- Completed a live Hasslehoff backup:
  `/root/operator-private/hasslehoff/backups/20260504T040948Z/`.

## Current Gates

- No live RouterOS config has been applied to the CCR2004.
- Nexus API repository creation remains deferred until admin credentials and TLS
  are vaulted.
- Exact version locks for Portage-resolved Jenkins, Grafana, and Prometheus
  should be written back after built VM/binpkg state is available.

## Tomorrow First Steps: 2026-05-04

1. Prepare the Emergency Gateway Ethernet WAN Link from the Codex host to the
   AT&T gateway L2.
2. Open `/dev/ttyUSB2` serial console and keep it attached.
3. Confirm the latest Hasslehoff backup SHA256 or run a fresh backup if config
   changed overnight.
4. Export current CCR2004 RouterOS config and binary backup.
5. Review `/tmp/routeros-rfc99-gateway/gw_rfc99_mkccr2004_16g-rfc99-gateway.rsc`.
6. Apply management-first CCR2004 config.
7. Validate SSH, HTTPS, API-SSL, WAN DHCP, DNS, SNAT, VLAN gateways, and remote
   syslog.
8. Remove CRS309 only after CCR2004 validates and emergency path is no longer
   needed.

## Backout Summary

Back out if the network primary gateway is offline too long or Codex loses
usable management reachability. Keep local serial access through `/dev/ttyUSB2`,
restore the pre-change RouterOS backup, and use the emergency direct Ethernet
WAN link to the AT&T gateway for temporary operator connectivity.
