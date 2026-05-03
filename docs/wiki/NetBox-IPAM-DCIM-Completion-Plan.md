# NetBox IPAM/DCIM Completion Plan

## Goal

Make NetBox the authoritative IPAM/DCIM source for the mixed RFC99, SUN99, FMT2,
and related environments, while keeping live network changes gated by dry-run,
backup, and validation steps.

## Current Repo State

Implemented source-of-truth plumbing:

- structured intake files under
  `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/`
- intake validation:
  `scripts/validate_netbox_inventory_intake.py`
- dry-run/apply path:
  `scripts/netbox_apply_inventory_intake.py`
- Ansible wrappers:
  - `playbooks/netbox-inventory-intake-validate.yml`
  - `playbooks/netbox-inventory-intake-apply.yml`

Live NetBox state:

- VM: `svc-netbox-stage4`
- VMID: `1062`
- URL: `http://172.16.99.62`
- recovery snapshot after structured local intake:
  `codex-netbox-after-intake-apply`

Current mixed-environment intake state:

- `/tmp/rfc99-sun99-host-networking.md` is now present and archived outside the
  repo under `/root/operator-private/network-intake/2026-05-03/`.
- Sanitized NetBox intake files now exist for:
  - `rfc99`
  - `sun99`
  - `yks99`
  - `fmt2`
- Local validation currently covers `5` files, `5` sites, `25` prefixes, `11`
  devices, `5` clusters, and `4` service VIPs.
- Live NetBox apply completed on 2026-05-03 after pre-apply snapshot
  `nb-pre-ms-20260503`.
- Idempotence pass completed with `0` creates and `0` updates.
- Post-apply snapshot `nb-post-ms-20260503` was created after validation.

## Raw Input Handling

The requested source file is intentionally treated as operator-private raw
input:

```text
/tmp/rfc99-sun99-host-networking.md
```

It contains credentials and incomplete or malformed inline records, so it must
not be committed as-is. Repo-safe intake files must exclude plaintext
credentials, normalize ambiguous prefixes, and leave destructive router changes
in `planned` state until validated.

## Data Model

Every environment should be imported as one or more explicit NetBox sites or
logical locations, not as ad hoc prefixes:

| Environment | Initial NetBox Model | Notes |
| --- | --- | --- |
| `RFC99` | `rfc99` site plus existing `local-rfc1918-lab` for current Proxmox services | Provider LAN, CRS309 replacement router, and administrative switches. |
| `SUN99` | `sun99` site | NanoNet and SUN99 general-admin prefixes. |
| `YKS99` | `yks99` site | Yukon Systems cluster prefixes; raw `/16` functional entries are staged as `/24` subnets under `172.28.0.0/16`. |
| `FMT2` | `fmt2` site | Public VPN endpoint and RFC99 OpenVPN tunnel address. |
| additional remote DCs | one site per physical or routed administrative boundary | Do not overload one site with unrelated DCIM. |

Required NetBox object classes:

- tenants or tenant groups for environment ownership when sites share physical
  facilities
- sites and optional locations/racks
- manufacturers and device types
- devices, modules, interfaces, LAGs, bridge interfaces, and management ports
- clusters and VM records
- prefixes, VLANs, VRFs, IP ranges, gateway IPs, and VIP IPs
- power panels/feeds, UPS, ATS, PDU, and power ports
- cables and LLDP-derived connections
- services for SSH, HTTPS/API, SNMP, syslog, RADIUS, LDAP/Kerberos, HAProxy,
  Elasticsearch, Kibana, and container app endpoints

## Import Order

1. Freeze live NetBox with a Proxmox snapshot.
2. Copy raw operator inputs into an ignored operator-private archive.
3. Create sanitized intake files per site/environment.
4. Run the intake validator.
5. Run dry-run apply and review the object plan.
6. Apply foundational objects:
   - tenants
   - sites
   - manufacturers/device types
   - roles
7. Apply IPAM objects:
   - VRFs
   - prefixes
   - VLANs
   - IP ranges
   - gateway IPs
8. Apply DCIM objects:
   - devices
   - interfaces
   - LAGs
   - bridge interfaces
   - power devices and ports
9. Apply virtualization/service objects:
   - Proxmox/QEMU clusters
   - VMs
   - container-services hosts
   - service VIPs and listeners
10. Validate NetBox API and selected object counts.
11. Snapshot NetBox again.
12. Only then execute RouterOS or switch mutations.

## Execution Plan

Safe work that is complete locally:

1. Raw host/networking and CRS309 files archived under operator-private storage.
2. Sanitized per-environment intake files created.
3. Local schema/reference validation passed.
4. Offline dry-run apply plan generated.

Work completed on 2026-05-03:

1. Live NetBox API validation against `http://172.16.99.62`.
2. Proxmox snapshot of VM `1062` before write.
3. Live NetBox apply with token-file authentication.
4. Idempotence apply.
5. Proxmox snapshot of VM `1062` after write.

Remaining gated work:

1. CRS309 management-only bootstrap and router migration.
2. NetBox HTTPS or HAProxy TLS termination.
3. DNS apply path after dry-run plan review.

## Acceptance Criteria

NetBox IPAM/DCIM is considered complete for this phase when:

- every supplied host has a NetBox device or VM record
- every supplied MAC is attached to a modeled interface
- every supplied IP is assigned to a modeled interface or service VIP
- every prefix has an owning site/environment and status
- every gateway IP is assigned to the router or L3 interface that owns it
- every switch/router/firewall/WAP has management protocol and AAA method
  recorded
- every power/OOB device is modeled with management IP and role
- overlapping prefixes are either resolved or explicitly documented with a
  migration exception
- NetBox dry-run after apply is idempotent

## Risks

- Applying the CRS309 draft before NetBox/IPAM reconciliation could replace the
  current default gateway and strand management access.
- The CRS309 draft contains overlapping `172.16.228.0/22` declarations.
- Broad SNMP v2c and enabled cleartext management services should be temporary
  migration aids only.
- The raw host/networking source contains credentials and malformed inline data;
  only sanitized intake files should enter the repo.
- Hetzner DNS writes must remain dry-run only until explicit apply/delete gates
  are implemented and reviewed.
