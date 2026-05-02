# Infrastructure Inventory Intake

This page defines the data we need before importing additional clusters,
datacenters, and service domains into NetBox IPAM/DCIM.

## Required Intake Data

### Datacenter

- Site name, short slug, and physical location.
- Facility/provider name when applicable.
- Management access path, including VPN, bastion, or out-of-band route.
- Power domains, UPS/ATS/PDU devices, and any known circuit constraints.
- Default timezone and operational owner.

### Cluster

- Cluster name and role, such as Proxmox, QEMU, Kubernetes, storage, GPU, CI,
  or network-services.
- Member nodes, management addresses, hardware model, serial number if known,
  CPU, memory, boot disk, and data disk layout.
- Hypervisor/API endpoint and authentication method.
- Storage pools, network bridges, VLAN trunks, and high-availability policy.
- Existing VM/container inventory if the cluster is already populated.

### Network

- Device name, vendor, model, serial number, management IP, access method, and
  software version.
- Interface map for uplinks, LAGs, access ports, trunks, RoCE, OOB, and unused
  ports.
- LLDP/CDP neighbors when available.
- VLAN IDs, names, tagged/untagged membership, and associated prefixes.
- Routing domains, gateways, VIPs, NAT boundaries, firewall zones, and DNS
  resolvers.

### IPAM

- Prefixes with status: active, reserved, deprecated, container-only,
  provider-assigned, or planned.
- Gateway IPs, DHCP ranges, static reservations, VIPs, and service ownership.
- DNS zones and record ownership.
- Any split-horizon DNS or alternate-access overlays such as ZeroTier.

### Identity And Access

- Local break-glass accounts that must remain outside central auth.
- Non-root user groups and expected RBAC roles.
- Network device AAA method: RADIUS now, TACACS+ later if required.
- SSH key sources and smartcard or VPN requirements.

### Observability

- Syslog destinations and transport requirements.
- Metrics collectors required by device class: node, SNMP, IPMI, Redfish,
  power, container, service-specific, and blackbox probes.
- Alert ownership and escalation boundaries.

## Import Order

1. Create or confirm the NetBox site.
2. Import manufacturers and device types through the essential device library.
3. Import prefixes, VLANs, and VRF/routing-domain boundaries.
4. Import devices, cluster nodes, VM/container service records, and management
   IPs.
5. Attach interfaces, LAGs, cables, tagged VLANs, and OOB links.
6. Enable validation playbooks and service readiness tests.

## Current Local Baseline

The `local-rfc1918-lab` site has already been seeded from:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/network_fabric.yml
```

Use `playbooks/netbox-local-fabric-seed.yml` for repeatable dry-run and apply
operations as the local fabric evolves.
