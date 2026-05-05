# inventory-intake

This directory stores repo-safe NetBox IPAM/DCIM intake definitions before they
are imported into the live NetBox API.

The files are deliberately declarative:

- `sites/*.yml` describes datacenters/sites, prefixes, clusters, devices, and
  service VIPs.
- `scripts/validate_netbox_inventory_intake.py` validates schema and references
  before any API write path consumes the data.
- `scripts/netbox_apply_inventory_intake.py` produces an offline dry-run plan by
  default and only writes to NetBox when passed `--apply`.
- `playbooks/netbox-inventory-intake-validate.yml` runs the same validator from
  Ansible.
- `playbooks/netbox-inventory-intake-apply.yml` runs the dry-run or write path
  from Ansible. Set `netbox_inventory_apply=true` only after reviewing the plan.

Keep credentials, API tokens, serial-console passwords, and device login
secrets out of this tree. Store those in Ansible Vault or operator-private
paths only.
