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

## Structured Intake Files

Repo-safe inventory intake files live under:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/
```

Validate them locally before using them for NetBox writes:

```bash
python3 scripts/validate_netbox_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites
```

Validate the same contract through Ansible:

```bash
ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-inventory-intake-validate.yml
```

Build a NetBox apply plan without touching the API:

```bash
python3 scripts/netbox_apply_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites \
  --api-url http://172.16.99.62
```

Run the same dry-run through Ansible:

```bash
ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-inventory-intake-apply.yml
```

Apply writes only after reviewing the dry-run plan:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-inventory-intake-apply.yml \
  -e netbox_inventory_apply=true \
  -e netbox_inventory_update_existing=true \
  -e netbox_seed_token_file=/root/operator-private/netbox/svc-netbox-stage4-admin-token
```

The first supported object groups are `datacenters`, `prefixes`, `devices`,
`clusters`, and `service_vips`. Keep credentials, device passwords, API tokens,
and sensitive serial-console values out of these files; store secrets in
Ansible Vault or operator-private paths.

## Current Local Baseline

The `local-rfc1918-lab` site has already been seeded from:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/network_fabric.yml
```

Use `playbooks/netbox-local-fabric-seed.yml` for repeatable dry-run and apply
operations as the local fabric evolves.

The structured baseline equivalent is:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml
```

The 2026-05-03 mixed-environment intake wave adds:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/rfc99.yml
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/sun99.yml
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/yks99.yml
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/fmt2.yml
```

Those files are sanitized from `/tmp/rfc99-sun99-host-networking.md`; raw
credentials and destructive RouterOS import content are intentionally excluded
from the repo.

The 2026-05-03 live apply sequence completed with:

- pre-apply snapshot: `nb-pre-ms-20260503`
- first apply: `21` creates and `78` updates
- idempotence apply: `0` creates and `0` updates
- post-apply snapshot: `nb-post-ms-20260503`
