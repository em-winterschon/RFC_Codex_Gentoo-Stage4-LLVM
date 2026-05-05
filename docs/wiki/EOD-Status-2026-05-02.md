# EOD Status 2026-05-02

## Executive State

NetBox and FreeIPA are now stable enough to serve as the control-plane base for
the next infrastructure automation pass. Today added structured NetBox intake
validation/apply tooling, applied the local lab baseline into live NetBox, and
created a post-apply NetBox recovery snapshot.

Late EOD review found the CRS309 RouterOS replacement-router draft at:

```text
/tmp/crs309-router-mode-idc.wip.rsc
```

The requested host/networking source file was not present at:

```text
/tmp/rfc99-sun99-host-networking.md
```

Because that missing file reportedly contains the mixed RFC99, SUN99, FMT2 host
inventory, IPs, MACs, and NetBox completion instructions, full NetBox IPAM/DCIM
population is blocked on that file. The available CRS309 file was reviewed and
documented as a controlled replacement-router plan, but no live RouterOS
mutation was executed.

## Completed Today

- Added structured NetBox inventory intake validation and dry-run/apply tooling.
- Applied the local structured intake to NetBox VM `1062`.
- Validated the second NetBox apply pass as idempotent with `0` creates and
  `0` updates.
- Updated NetBox API validation to support token-file authentication.
- Created Proxmox snapshot `codex-netbox-after-intake-apply` for NetBox VM
  `1062`.
- Added and pushed commit `66a4bc6` for the structured NetBox intake workflow.
- Reviewed `/tmp/crs309-router-mode-idc.wip.rsc` and extracted the replacement
  router design, prefix list, execution gates, and blockers into repo docs.
- Archived the raw CRS309 WIP input outside the repo at
  `/root/operator-private/network-intake/2026-05-02/crs309-router-mode-idc.wip.rsc`.

## CRS309 Router Replacement Assessment

The CRS309 script is destructive by design. It removes current bridges, IP
addresses, DHCP clients, firewall rules, NAT rules, RIP, and WireGuard before
rebuilding the device.

Do not execute it directly as an overnight unattended import.

Safe overnight action is limited to:

1. Documentation and plan commit.
2. NetBox intake dry-run validation.
3. Existing NetBox API validation.
4. Existing local-network inventory refresh if needed.

RouterOS mutation requires:

1. serial console attached
2. current config backup copied off-device
3. management-only bootstrap first
4. WAN validation
5. one LAN member/prefix group at a time
6. NetBox reconciliation after each major stage

## NetBox IPAM/DCIM Completion Plan

The plan is documented in:

```text
docs/NETBOX-IPAM-DCIM-COMPLETION-PLAN.md
docs/CRS309-ROUTEROS-REPLACEMENT-PLAN.md
docs/superpowers/plans/2026-05-02-netbox-dcim-ipam-and-crs309-router-replacement.md
```

The next NetBox intake wave should proceed only after the missing host/network
source exists. The exact flow is:

1. archive raw input under `/root/operator-private/network-intake/`
2. create sanitized per-environment intake files
3. validate intake
4. dry-run NetBox apply
5. snapshot NetBox before write
6. apply NetBox writes
7. run idempotence apply
8. snapshot NetBox after write
9. execute RouterOS or switch changes only after NetBox matches intended state

## Known Blockers

| ID | Blocker | Impact | Required Action |
| --- | --- | --- | --- |
| `EOD-20260502-001` | `/tmp/rfc99-sun99-host-networking.md` is missing | Cannot populate RFC99/SUN99/FMT2 host/IP/MAC truth into NetBox | Provide the file or corrected path |
| `EOD-20260502-002` | CRS309 draft contains overlapping `172.16.228.0/22` gateway declarations | NetBox and RouterOS route ownership would be ambiguous | Normalize NPi cluster prefix model before import |
| `EOD-20260502-003` | CRS309 draft enables broad SNMP v2c community access | Not suitable as permanent posture | Replace with vaulted SNMPv3 or tightly scoped v2c |
| `EOD-20260502-004` | CRS309 draft contains duplicate certificate-generation blocks | Re-run behavior is ambiguous | Consolidate TLS section before execution |
| `EOD-20260502-005` | CRS309 draft leaves HTTP/API enabled | Management security posture unclear | Decide temporary recovery versus permanent policy |
| `EOD-20260502-006` | `172.16.99.0/24` management reachability is degraded from this host | Live NetBox and FreeIPA API validation cannot run now | Restore Hasslehoff/CSS326/management L2 path before live applies |

Observed reachability at EOD:

- local `eno1` has `172.16.99.108/24` and physical link is up at `1000Mb/s`
- route lookup for `172.16.99.62` uses `eno1`
- ARP neighbor entries for `172.16.99.9`, `172.16.99.62`, and `172.16.99.63`
  are failed
- ping to `172.16.99.9`, `172.16.99.62`, and `172.16.99.63` fails
- SSH to `hasslehoff` times out

This is a management-network reachability blocker, not evidence that the NetBox
or FreeIPA guest services are down.

## Overnight Plan

Non-destructive overnight tasks:

1. Commit and push the EOD documentation and wiki source mirrors.
2. Publish the wiki mirror if repo verification passes.
3. Re-run local NetBox intake validation.
4. Re-run NetBox API token-file validation after management reachability is
   restored.
5. Leave live RouterOS and switch state unchanged.

Destructive work explicitly deferred:

1. CRS309 RouterOS import.
2. CRS309 firewall/NAT replacement.
3. gateway migration from OPNsense or QEMU RouterOS.
4. full RFC99/SUN99/FMT2 NetBox apply without the missing host inventory file.

## Resumption Notes

The next useful action is to provide or recreate:

```text
/tmp/rfc99-sun99-host-networking.md
```

Once that file exists, convert it into structured NetBox intake files and run
the documented dry-run/apply/snapshot sequence. Do not run the CRS309 WIP import
until the NetBox model, serial fallback, and backup exports are in place.
