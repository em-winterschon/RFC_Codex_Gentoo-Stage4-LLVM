# Hetzner DNS Automation

## Purpose

Use Hetzner Cloud DNS as the external authoritative DNS provider while keeping
NetBox as the internal source of truth for service names, IPAM objects, and
future DNS CRUD intent.

The credential boundary is:

- raw token import files stay outside the repo
- Ansible Vault stores token names, API tokens, and zone lists
- repo-safe inventory references only `vault_hetzner_dns_*` variables
- DNS changes default to dry-run and deletion-disabled posture

## Current Inputs

Operator-provided token source:

```text
/tmp/rfc-vernetzen-yukon.dns-api-info.cfg
```

Imported vault variable groups:

```text
vault_hetzner_dns_rfc1918_zones
vault_hetzner_dns_rfc1918_token_name
vault_hetzner_dns_rfc1918_api_token
vault_hetzner_dns_vernetzen_zones
vault_hetzner_dns_vernetzen_token_name
vault_hetzner_dns_vernetzen_api_token
vault_hetzner_dns_yukon_zones
vault_hetzner_dns_yukon_token_name
vault_hetzner_dns_yukon_api_token
```

Repo-safe policy file:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/dns_hetzner_cloud.yml
```

## Import Workflow

Import or rotate token groups:

```bash
scripts/import-hetzner-dns-vault.sh /tmp/rfc-vernetzen-yukon.dns-api-info.cfg
```

Validate the encrypted vault:

```bash
scripts/validate-ansible-vaults.sh \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/group_vars/all/vault.yml
```

Validate Hetzner Cloud DNS API token access without printing tokens:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/hetzner-dns-api-validate.yml
```

Build a read-only live provider inventory report. This validates each configured
zone can be read through the API, counts records by zone and type, and emits a
deduplicated connectivity target map for hostname/IP healthchecks and future
nmap service validation:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/hetzner-dns-inventory-report.yml
```

The generated provider inventory report is written to:

```text
/tmp/hetzner-dns-inventory-report.json
```

Current live provider inventory result:

- zones_readable: `8/8`
- records_total: `221`
- records_by_type: `A=99`, `CNAME=23`, `MX=26`, `NS=15`, `SOA=5`,
  `SRV=48`, `TXT=5`
- connectivity_hosts: `99`
- errors: `0`

Generate a dry-run DNS plan from NetBox IP address `dns_name` fields:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/hetzner-dns-plan-from-netbox.yml
```

The generated plan is written to:

```text
/tmp/hetzner-dns-plan-from-netbox.json
```

Current live dry-run result:

- records: `7`
- skipped: `5`
- apply: `false`
- allow_delete: `false`

The first records are for `rfc1918.host` service VIPs and `rfc1918.io`
switch/gateway management names.

## Automation Contract

The first supported contract is token validation and safe policy staging. Future
DNS CRUD should consume NetBox DNS names/IPAM objects and generate desired RRset
operations from that source of truth. The first dry-run planner is:

```text
scripts/plan-hetzner-dns-from-netbox.py
```

The provider-side inventory reporter is:

```text
scripts/report-hetzner-dns-inventory.py
```

It never writes DNS records and never serializes API tokens. The reporter reads
Hetzner's RRset-based record API and normalizes address-bearing RRsets into
host validation targets. Its output includes:

- per-zone readability status
- per-zone `records_total`
- per-zone and global `records_by_type`
- `connectivity_targets.hosts_by_zone`
- `connectivity_targets.flat_hosts`
- skipped non-address or invalid address records

Default safety posture:

- `source_of_truth: netbox`
- `apply: false`
- `allow_delete: false`
- `default_ttl: 300`

Deletion must stay disabled until NetBox ownership tags, reverse zones, and
stale-record detection are modeled explicitly.

## References

- Hetzner Cloud DNS migration and API behavior:
  <https://docs.hetzner.com/networking/dns/migration-to-hetzner-console/features-and-differences/>
- Hetzner Ansible DNS guidance:
  <https://docs.hetzner.com/networking/dns/migration-to-hetzner-console/ansible/>
