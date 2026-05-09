# EOD Status 2026-05-04

## Completed

- Cut over the active RFC99 gateway role to the physical
  `CCR2004-16G-2S+PC` and validated WAN DHCP, DNS, NAT, management reachability,
  HTTPS, API-SSL, and remote syslog.
- Upgraded the CCR2004 gateway to RouterOS package and RouterBOARD firmware
  `7.22.2`.
- Reset and rebuilt the CRS309 as the RouterOS 10GbE spine/aggregation switch.
- Upgraded CRS309 to RouterOS package and RouterBOARD firmware `7.22.2`.
- Brought up the CCR2004-to-CRS309 `10G-SR` uplink on CRS309 `sfp-sfpplus1`
  after replacing the suspect optics pair.
- Brought up CRS309-to-CRS354 LACP using CRS309 `sfp-sfpplus2/3` and CRS354
  `sfp-sfpplus1/2`, with both members active at `10Gbps`.
- Confirmed CRS354 is on RouterOS package and RouterBOARD firmware `7.22.2`,
  disabled stale OPNsense route/address state, and archived serial evidence.
- Confirmed CSS326 is on current SwOS release `2.18.1751448030`; added the
  SwOS snapshot helper and archived access-switch state.
- Applied the refreshed NetBox fabric intake live and validated idempotence
  with `0` creates and `0` updates after the follow-up pass.
- Added read-only RouterOS state snapshot automation and validated SSH snapshot
  collection for CRS309.
- Added the Forge GitHub token to the encrypted local-network Ansible Vault and
  documented the non-secret usage pattern.
- Marked GitHub PRs `#13`, `#14`, `#15`, and `#16` ready for review through the
  local `gh` fallback after the GitHub connector ready-for-review mutation hit
  a connector-side GraphQL field mismatch.

## Current Gates

- CSS326-to-CRS309 `10G-SR` uplink on CSS326 `sfp1` to CRS309
  `sfp-sfpplus8` still needs physical cabling and validation.
- Hasslehoff CCR2004-1G-2XS-PCIe DAC links to CRS309 `sfp-sfpplus4/5` still
  need cabling, link validation, and NetBox interface/cable modeling.
- CRS354 read-only collection remains serial-backed until SSH command behavior
  is normalized.
- RouterOS spine/distribution automation is render-only. Live import/apply
  remains gated behind fixture-backed render tests, explicit serial gates, and
  backup evidence.
- Deep NetBox interface, LAG, optics, and cable modeling is still pending for
  CRS309, CRS354, CSS326, Hasslehoff, QNAP, and CCR-PCI.
- The container-services safe-move target still has an Elasticsearch dependency
  gap from `172.16.99.89` to the existing `10.9.8.91` / `10.9.8.92` test path.
- Nexus Repository OSS API automation remains deferred until credentials and
  TLS are vaulted.

## Outstanding Actions

1. Cable and validate CSS326 `sfp1` to CRS309 `sfp-sfpplus8`.
2. Cable and validate Hasslehoff CCR-PCI DAC links to CRS309 `sfp-sfpplus4/5`.
3. Add NetBox interface, LAG, optic, and cable records for the spine/leaf fabric.
4. Add fixture-backed tests for RouterOS spine/distribution renders.
5. Decide whether CRS354 SSH behavior can be normalized or whether serial
   collection remains the operational source for CRS354 state snapshots.
6. Resume container-services safe-move routing validation after the management
   and Path B networks have a deliberate transit path.
7. Start the Stage5 workstation VM branch with a QEMU-first Xorg, SPICE, and
   NsCDE overlay design.

## Tomorrow First Steps: 2026-05-05

1. Validate the active gateway and spine fabric with a short reachability pass:
   CCR2004, CRS309, CRS354, CSS326, NetBox, Hasslehoff, and internet egress.
2. Complete the remaining CSS326 and Hasslehoff CCR-PCI physical links if
   cabling is available.
3. Back up live RouterOS and SwOS state before any further mutation.
4. Open the workstation VM feature branch and build the implementation plan:
   profile definition, package list, NsCDE packaging strategy, SPICE QEMU
   launch options, and validation steps.
5. Keep Hasslehoff GPU passthrough as a follow-on validation target only after
   the on-host QEMU workstation build is repeatable.

## Backout Summary

The CCR2004 is the current active gateway. If gateway behavior regresses, use
serial access plus the archived pre/post upgrade RouterOS backups to restore the
last known-good state. If spine changes regress, preserve the CCR2004 gateway
uplink and temporarily bypass CRS309 aggregation until the affected downstream
link is isolated.
