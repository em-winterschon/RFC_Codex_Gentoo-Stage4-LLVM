# Proxmox NetBox RouterOS Action Plan

## Goal

Move the routing and source-of-truth work out of the temporary Path B lab VM
stack and onto the Proxmox management environment that already hosts NetBox and
the CCR2004 RouterOS PCIe card.

The current QEMU RouterOS Path B gateway remains the rollback path until the
CCR2004 path is validated.

## Required Inputs

Collect these before changing live networking:

- Proxmox management IP or DNS name
- Proxmox SSH user and sudo policy
- NetBox URL
- NetBox API token
- NetBox VM SSH target
- CCR2004 RouterOS management IP or MAC-neighbor access method
- RouterOS admin user or dedicated automation user
- exact management subnet prefix
- desired VLAN IDs, if any, for lab, management, OOB, and builder networks

## Initial IPAM Model

Treat this as a draft until the management subnet is confirmed.

| Purpose | Prefix Or Address | Source |
| --- | --- | --- |
| Path B lab | `10.9.8.0/24` | current working lab |
| RouterOS upstream WAN | `192.168.1.0/24` | upstream router is `192.168.1.254` |
| Previous CHR WAN static | `192.168.1.222/24` | current Path B CHR design |
| Container-services VM | `10.9.8.89/32` | current VM |
| Binpkg repository VM | `10.9.8.90/32` | current VM |
| Elasticsearch test VM | `10.9.8.91/32` | reserved/test |
| Elasticsearch test VIP | `10.9.8.92/32` | HAProxy VIP |
| Container management segment | `10.77.0.0/24` | proposed |
| Container application segment | `10.77.1.0/24` | proposed |
| OOB segment | TBD | BlackBox OOB plus UPS/PDU/ATS management |
| Builder farm segment | TBD | six Atom C3758 build nodes plus controller |
| ZeroTier overlay | TBD | wait for network ID |

## NetBox Objects

Create or reconcile:

- site for the local lab
- devices:
  - Proxmox host
  - CCR2004 RouterOS PCIe card
  - NetBox VM
  - current Path B RouterOS CHR VM
  - container-services VM
  - binpkg repository VM
  - Elasticsearch test VM
- device roles:
  - `hypervisor`
  - `router`
  - `ipam`
  - `container-host`
  - `binpkg-repository`
  - `service-vm`
  - `oob`
- prefixes:
  - management
  - Path B lab
  - upstream WAN
  - container management
  - container apps
  - OOB
  - builder farm
- IP addresses and VIPs:
  - gateways
  - VM addresses
  - HAProxy VIPs
  - infrastructure service endpoints

The repo now includes a read-only planning profile for this seed data:

- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/netbox-pathb-lab-ipam-plan.yml`

That profile renders planned prefixes, IP addresses, and devices into the
NetBox connector manifest. It does not write NetBox objects by itself.

## SSH Bootstrap

1. Generate or reuse the Codex ed25519 public key from this host.
2. Install the key on Proxmox with passwordless sudo only where needed.
3. Install the key on the NetBox VM for file/API helper work.
4. Create a RouterOS automation user for SSH/API access.
5. Verify noninteractive SSH before committing inventory entries.

Current status:

- Proxmox SSH to `hasslehoff` is validated through the `local-network`
  inventory.
- Proxmox API token values are encrypted in the local-network Ansible vault.
- CRS354 bootstrap credentials are encrypted in the local-network Ansible vault.
- Hasslehoff repo-safe host facts and observed VM state are tracked in
  `inventories/local-network/host_vars/hasslehoff.yml`.
- Private live snapshots are written under `/root/operator-private/`.

Refresh Hasslehoff inventory with:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/local-network-inventory.yml
```

## RouterOS Migration Sequence

1. Export the current QEMU RouterOS Path B config and store it in repo docs or
   an ignored operator archive path.
2. Keep QEMU RouterOS running as rollback.
3. Apply only CCR2004 management access first.
4. Add interface names, comments, and safe firewall input rules.
5. Add lab gateway and DNS forwarding.
6. Add DHCP only if the lab still needs dynamic VM addressing.
7. Add NAT/masquerade toward the upstream network.
8. Move one test VM or route at a time.
9. Validate DNS, internet egress, binpkg repo access, and HAProxy VIP ingress.
10. Retire the QEMU RouterOS gateway only after repeat validation.

## Ansible Work Items

- Add Proxmox inventory skeleton. Completed for `hasslehoff`.
- Add NetBox inventory source or connector variables.
- Add RouterOS CCR2004 host variables separate from the QEMU CHR role.
  Scaffolded as `rtr_mgmt_ccr2004`; live credentials still need operator input.
- Add a read-only NetBox API validation task before write tasks.
- Add prefix/address creation tasks guarded by explicit operator variables.
- Add a RouterOS config export backup task before mutations.
- Add service readiness checks using `scripts/service_validator.py`.

## Safety Rules

- Do not infer the management prefix from partial information.
- Do not replace the QEMU RouterOS Path B gateway until CCR2004 validation
  passes.
- Do not write NetBox prefixes until the proposed plan is confirmed against the
  live management network.
- Keep RouterOS automation changes incremental and export configs before each
  major step.
