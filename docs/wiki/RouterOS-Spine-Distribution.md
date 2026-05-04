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

- add RouterOS read-only state collectors for package, firmware, bond, bridge,
  service, and route state
- add fixture-backed tests for RouterOS RSC rendering
- add explicit `ROUTEROS_APPLY=1`-style gated imports only after serial-backed
  failure handling is scripted
- push rendered desired state into NetBox interface and cable records
