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

An offline NetBox dry-run apply plan generated `94` planned object operations.
No live NetBox writes were attempted.

## Live Reachability

Management reachability from this host is still degraded:

- `eno1` is up with `172.16.99.108/24`
- route lookup for `172.16.99.62` uses `eno1`
- ARP neighbor lookup for `172.16.99.62` is failed
- ping to `172.16.99.62` fails
- TCP checks to `172.16.99.62:80`, `172.16.99.9:22`, and
  `172.16.99.63:1812` time out

This blocks live NetBox API validation, Proxmox snapshots through SSH, and live
NetBox apply. It does not prove the NetBox or FreeIPA guests are down.

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
2. Validate live NetBox API at `http://172.16.99.62`.
3. Snapshot NetBox VM `1062` on Hasslehoff.
4. Review the offline intake dry-run plan and apply with token-file
   authentication.
5. Re-run the apply path for idempotence and snapshot NetBox again.
6. Recover CRS309 admin access through serial/reset.
7. Execute only the CRS309 management-only bootstrap first.
