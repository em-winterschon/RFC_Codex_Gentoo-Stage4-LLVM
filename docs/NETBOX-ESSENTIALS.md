# NetBox Essentials

This page documents the required NetBox operational integrations that must be
present before NetBox becomes the IPAM/DCIM source of truth for the lab.

## Required Integrations

The source list is `/tmp/docs/netbox.essential.md`. The repo models those
items as operational tooling installed beside NetBox, not as Django plugins
loaded into the NetBox application process:

- `pynetbox`
- `netbox-agent`
- `netbox-sync`
- `netbox-tools`
- `devicetype-library`
- `Device-Type-Library-Import`

This isolation keeps NetBox upgrades safer. The tools live under
`/opt/netbox-essentials`, use their own Python virtualenv, and render a
manifest at `/etc/stage5-services/netbox/netbox-essentials.yml`.

## Stage5 Role

The `netbox_essentials` role is included by the `vm-netbox-service` profile
after `netbox_server` and before any connector/write workflows.

Primary files:

- `roles/netbox_essentials/defaults/main.yml`
- `roles/netbox_essentials/tasks/main.yml`
- `roles/netbox_essentials/templates/netbox-essentials.yml.j2`
- `profile-definitions/vm-netbox-service.yml`

The role clones pinned operational repositories, installs required Python
packages into the isolated virtualenv, and optionally runs the device-type
library importer for selected vendors.

## Live Service State

Current service:

- VM: `svc-netbox-stage4`
- Proxmox VMID: `1062`
- URL: `http://172.16.99.62`
- NetBox version: `v4.5.9`
- Essentials root: `/opt/netbox-essentials`
- Recovery snapshot before device-type import:
  `codex-netbox-before-essential-import`
- Recovery snapshot after device-type import:
  `codex-netbox-after-essential-import`
- Recovery snapshot after local fabric seed:
  `codex-netbox-after-fabric-seed`
- Recovery snapshot after structured inventory intake apply:
  `codex-netbox-after-intake-apply`

The first required import targets:

- `APC`
- `Arista`
- `Cisco`
- `CyberPower`
- `Eaton`
- `Juniper`
- `MikroTik`
- `Opengear`

Validated import state:

- manufacturers: `8`
- device types: `1924`
- interface templates: `55748`
- power port templates: `1506`
- console port templates: `2406`
- module types: `748`

The importer logs non-fatal HTTP `500` responses for some elevation image
uploads and NetBox `4.5` module-profile validation errors for a small subset of
module definitions. Core manufacturers, device types, and interface/power/console
templates are present and usable.

## NetBox Seed Workflow

After the essential import finishes, seed repo-safe local fabric objects with:

```bash
python3 scripts/netbox_seed_local_network.py \
  --api-url http://172.16.99.62 \
  --token-file /root/operator-private/netbox/svc-netbox-stage4-admin-token \
  --dry-run
```

If the dry run is sane, apply with:

```bash
python3 scripts/netbox_seed_local_network.py \
  --api-url http://172.16.99.62 \
  --token-file /root/operator-private/netbox/svc-netbox-stage4-admin-token \
  --update-existing
```

The live seed created `42` baseline fabric objects with no updates. The seed
script is intentionally conservative: it creates missing sites, VLANs, prefixes,
device roles, manufacturers, device types, devices, and management IP addresses
from `inventories/local-network/group_vars/all/network_fabric.yml`. It does not
overwrite existing records unless `--update-existing` is passed.

Dry-run through Ansible:

```bash
scripts/with-ansible-vault-env.sh ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/netbox-local-fabric-seed.yml \
  -e netbox_seed_token_file=/root/operator-private/netbox/svc-netbox-stage4-admin-token
```

Apply intentionally by adding:

```bash
-e netbox_seed_apply=true
```

## Structured Inventory Intake Workflow

The local fabric now also has a normalized structured intake file:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml
```

Validate and dry-run before applying:

```bash
python3 scripts/validate_netbox_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites

python3 scripts/netbox_apply_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites \
  --api-url http://172.16.99.62
```

Apply through the token-file path only after reviewing the dry-run plan:

```bash
python3 scripts/netbox_apply_inventory_intake.py \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites \
  --api-url http://172.16.99.62 \
  --token-file /root/operator-private/netbox/svc-netbox-stage4-admin-token \
  --apply \
  --update-existing
```

The first live structured intake pass created the missing Proxmox and Stage4
service cluster records plus the `log-sun99-rsyslog-099093` and
`elasticsearch-vip`
IP records. A second apply pass completed with `0` creates and `0` updates.
