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

## Missing Input

The requested source file was not present at review time:

```text
/tmp/rfc99-sun99-host-networking.md
```

That file is required before claiming IPAM/DCIM completion for the mixed
environment set because it reportedly contains the host, IP, MAC, and NetBox
completion instructions.

## Data Model

Every environment should be imported as one or more explicit NetBox sites or
logical locations, not as ad hoc prefixes:

| Environment | Initial NetBox Model | Notes |
| --- | --- | --- |
| `RFC99` | existing `local-rfc1918-lab` site unless the source file defines a cleaner split | Current management and Proxmox/Stage4 services live here. |
| `SUN99` | new site or tenant-backed logical site | CRS309 draft uses `gw-sun99-mkcrs309.rfc1918.host`. |
| `FMT2` | new site or tenant-backed logical site | Wait for host/networking source file. |
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

## Overnight Execution Plan

Safe overnight work that does not require the missing host file:

1. Validate and commit documentation and plans.
2. Keep live network unchanged.
3. Prepare a sanitized CRS309 execution plan.
4. Prepare NetBox object model and import order.
5. Confirm existing local structured intake still validates.
6. Confirm NetBox API token-file validation still passes.

Work blocked until `/tmp/rfc99-sun99-host-networking.md` exists:

1. Generate per-environment intake files for RFC99, SUN99, FMT2, and other
   listed environments.
2. Normalize host/IP/MAC records into NetBox devices, interfaces, MAC
   addresses, and IP address assignments.
3. Reconcile overlapping or duplicate prefixes.
4. Dry-run the full mixed-environment NetBox import.
5. Apply the import.
6. Snapshot NetBox after apply.

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
- The missing source file likely contains the only complete host/IP/MAC truth
  for SUN99/FMT2 and cannot be inferred safely from the CRS309 RouterOS script.
