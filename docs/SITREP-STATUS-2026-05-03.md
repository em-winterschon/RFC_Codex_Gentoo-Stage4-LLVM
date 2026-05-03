# SITREP Status 2026-05-03

## Executive State

The missing mixed-environment source file is now present at:

```text
/tmp/rfc99-sun99-host-networking.md
```

The raw host/networking file and CRS309 RouterOS WIP script were archived
outside the repo under:

```text
/root/operator-private/network-intake/2026-05-03/
```

Repo-safe structured NetBox intake files have been generated for `rfc99`,
`sun99`, `yks99`, and `fmt2`. The raw source contains plaintext credentials,
malformed inline data, unset CRS309 MAC values, and ambiguous subnet intent, so
only sanitized facts were committed to intake files.

## Current Validation

Local intake validation passes across all structured site files:

| Object Class | Count |
| --- | ---: |
| files | 5 |
| datacenters | 5 |
| prefixes | 25 |
| devices | 11 |
| clusters | 5 |
| service VIPs | 4 |

The live multisite NetBox intake apply completed after taking a pre-apply
snapshot. The first pass created `21` objects and updated `78`; the second pass
confirmed idempotence with `0` creates and `0` updates. A post-apply snapshot
was created after validation.

Post-apply NetBox object counts:

| Object Class | Count |
| --- | ---: |
| sites | 5 |
| devices | 12 |
| manufacturers | 14 |
| device types | 1935 |
| device roles | 11 |
| prefixes | 24 |
| IP addresses | 12 |
| VLANs | 5 |
| clusters | 5 |
| cluster types | 5 |

The Hetzner DNS dry-run planner generated `7` RRsets from NetBox `dns_name`
fields and skipped `5` management IPs that do not yet have DNS names.

The read-only Hetzner provider inventory report validated all configured zones
through the API:

- zones_readable: `8/8`
- records_total: `221`
- connectivity_hosts: `99`
- errors: `0`

## Live Reachability

Management reachability from this host recovered:

- `eno1` is up with `172.16.99.108/24`
- `172.16.99.9` Hasslehoff is reachable over SSH and Proxmox API
- `172.16.99.62` NetBox is reachable over SSH, HTTP, and authenticated API
- `172.16.99.63` FreeIPA is reachable over SSH, HTTP/HTTPS, LDAP, and LDAPS

NetBox HTTPS on `443` is not enabled yet.

## CRS309 Router Status

CRS309 replacement work remains gated. The WIP RouterOS script is destructive
and must not be imported unattended. Current blockers:

- CRS309 admin login/reset path must be recovered.
- Serial fallback on `/dev/ttyUSB2` must remain attached during changes.
- Current CRS309 backup/export must be copied off-device before mutation.
- `WAN_NET_MAC` and `LAN_NET_MAC` are unset in the source plan.
- RouterOS import must be split into management-only, WAN, one-LAN-port, prefix
  groups, firewall/NAT, and overlay phases.
- NetBox should be staged and snapshot-protected before router mutation.

## Next Steps

1. Restore `172.16.99.0/24` management L2 reachability from the Codex host.
2. Enable TLS for NetBox or front it through the HAProxy TLS termination path.
3. Add DNS names for remaining management devices where appropriate.
4. Compare `/tmp/hetzner-dns-inventory-report.json` against NetBox managed
   objects and identify unmanaged DNS hosts.
5. Review `/tmp/hetzner-dns-plan-from-netbox.json`.
6. Implement Hetzner DNS apply path with explicit apply/delete gates.
7. Recover CRS309 admin access through serial/reset.
8. Execute only the CRS309 management-only bootstrap first.
