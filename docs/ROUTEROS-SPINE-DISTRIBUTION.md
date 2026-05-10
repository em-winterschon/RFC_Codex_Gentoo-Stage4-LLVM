# RouterOS Spine Distribution Automation

## Scope

This workflow renders repeatable RouterOS intent for the RFC99 10G spine and
distribution layer:

- CRS309 spine switch: `sw-spine-crs309-rfc99`
- CRS354 distribution switch: `sw-mgmt-mkcrs354`
- CRS309 to CRS354 `802.3ad` LACP
- CRS354 stale OPNsense address/default-route cleanup
- validation commands for version, firmware, LACP state, bridge membership,
  optical links, and management reachability

The role is render-only. It does not SSH into RouterOS devices and does not
import live configuration.

## Render

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook playbooks/routeros-spine-distribution.yml
```

Rendered output defaults to:

```text
/tmp/routeros-spine-distribution/
```

Files:

- `sw_spine_crs309_rfc99.rsc`
- `sw_mgmt_mkcrs354.rsc`
- `routeros-spine-distribution.json`

## Live Import Gate

Do not import rendered RSC files until these conditions are true:

- serial console is attached for CRS309 on `/dev/ttyUSB0`
- serial console is attached for CRS354 on `/dev/ttyUSB1`
- fresh off-device exports/backups exist
- current physical cabling matches NetBox/source inventory
- operator has accepted the backout path

This keeps RouterOS live changes explicitly gated while still making the desired
state reviewable and reproducible.

## Current Validated State

As of 2026-05-04:

- CRS309 runs RouterOS package and RouterBOARD firmware `7.22.2`
- CRS354 runs RouterOS package and RouterBOARD firmware `7.22.2`
- CRS309 `bond-crs354` uses `sfp-sfpplus2,sfp-sfpplus3`
- CRS354 `bond-crs309` uses `sfp-sfpplus1,sfp-sfpplus2`
- both LACP members are active after post-reboot settle
- CRS354 stale `172.16.254.7/24` address and `172.16.254.1` default route are
  disabled
- CCR2004, CSS326, CRS354, and CRS309 management endpoints are reachable

## Follow-Up Automation

Next steps:

- use `scripts/collect-mikrotik-routeros-state.py` through
  `playbooks/routeros-state-snapshot.yml` for read-only package, firmware,
  bond, bridge, service, route, neighbor, and hide-sensitive export snapshots
- add fixture-backed tests for RouterOS RSC rendering
- add explicit `ROUTEROS_APPLY=1`-style gated imports only after serial-backed
  failure handling is scripted
- push rendered desired state into NetBox interface and cable records

## Serial Console Automation

RouterOS emits an `ESC Z` terminal-identification probe after serial login.
Plain raw scripts can appear stuck after password entry if they do not answer
that probe. Use `scripts/routeros-serial-command.py` for serial command
execution because it responds with a VT100/ANSI answerback before sending
commands.

Example read-only CRS309 serial check:

```bash
ROUTEROS_PASSWORD='...' scripts/routeros-serial-command.py \
  --port /dev/ttyUSB0 \
  --username admin \
  --command '/system identity print'
```

The helper has been validated against CRS309 by returning
`sw-spine-crs309-rfc99` from `/system identity print`.

## State Snapshot Workflow

The live snapshot workflow intentionally separates read-only state collection
from config mutation:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ANSIBLE_CONFIG=/tmp/stage4-ansible.cfg ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/routeros-state-snapshot.yml \
  --vault-id RFC99@/root/.ssh/vault/cdex-vault-ops.ansiblevault.key
```

Snapshots are written outside the repository under:

```text
/root/operator-private/routeros/state-snapshots/<inventory-host>/<timestamp>/
```

After any live RouterOS or SwOS change, use the encrypted post-change backup
back-channel to capture current device configs and stage only Ansible Vault
files into git:

```bash
scripts/backup-network-device-configs.sh --sync-git
```

That wrapper requests RouterOS `show-sensitive` exports for encrypted backup
workflows, includes SwOS `backup.swb`, and writes encrypted artifacts under
`encrypted-backups/network-devices/`. Plaintext remains in operator-private
storage.

Current live behavior:

- CRS309 SSH snapshot is enabled and validated.
- CRS354 serial snapshot collection is enabled through
  `scripts/collect-mikrotik-routeros-serial-state.py`.
- CCR2004-16G serial snapshot collection is available through `/dev/ttyUSB2`
  when its vault-backed admin credentials are present.
