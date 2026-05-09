# Netboot Lifecycle, NetBox Intake, And AAA Design

## Goal

Make bare-metal provisioning state explicit enough that Jenkins, NetBox, RouterOS,
and Ansible agree on how a host boots, which artifacts it consumes, where it is
connected, and which identity/AAA controls apply next.

## Current State

K10 has a validated emergency-compatible boot path:

- firmware uses UEFI PXE over TFTP
- TFTP loads `k10-ipxe.efi`
- iPXE loads host and role scripts over HTTP
- dracut uses static networking for `172.16.99.156/24`
- the live Gentoo rootfs reaches a login prompt

The repo tracks this as `netboot_type: static`, but that field only describes
IP assignment. It does not distinguish normal direct-iPXE hosts from K10-style
PXE-to-iPXE handoff hosts.

NetBox is reachable, but live NetBox does not yet contain the K10 device or the
AP7901 PDU. PDU secrets are vaulted and must not be copied into NetBox.

FreeIPA, SSSD, and FreeRADIUS are the selected AAA baseline. The immediate gap
is sequencing broad enrollment safely after inventory and power-device metadata
are represented.

## Design

### Netboot Protocol Flow

Keep `netboot_type` as the IP-assignment mode with existing values:

- `static`
- `dhcp`
- `bootp`

Add `netboot_protocol_flow` for firmware and handoff behavior:

- `ipxe-direct`: firmware or a controlled boot path reaches iPXE directly
- `pxe-to-ipxe`: firmware PXE/TFTP loads an iPXE binary, then iPXE uses HTTP
- `uefi-httpboot`: firmware UEFI HTTPBoot fetches the first-stage asset directly
- `disabled`: host is inventoried but should not receive automated netboot rules

K10 uses `pxe-to-ipxe`. Normal hosts default to `ipxe-direct`.

Both `netboot_assets` and `routeros_pathb` validate this enum and include it in
their rendered manifests. RouterOS render output logs the flow so operator
review can detect accidental direct-iPXE assumptions on Realtek or other
firmware-problematic systems.

### Boot-Image Manifest

Add an explicit boot-image manifest list for reproducible dracut builds. Each
entry captures:

- manifest name and target host
- kernel URL or artifact path
- initramfs URL or artifact path
- rootfs URL
- dracut modules and omitted modules
- required firmware paths
- required kernel modules
- rendered kernel command line
- build script used for artifact generation
- artifact hash strategy

The first entry is for K10. Jenkins can consume this data later without parsing
free-form docs or rendered iPXE scripts.

### NetBox Intake

Promote non-secret K10 and AP7901 PDU records through the existing structured
inventory intake file:

- K10 as a planned/active bare-metal workstation validation host
- K10 boot interface with MAC, switch, switchport, and netboot metadata notes
- AP7901 as a power-management device
- AP7901 management IP `172.16.99.241`
- AP7901 serial if known
- AP7901 SNMPv3 capability as non-secret metadata
- outlet map note for outlet 6 label `host_gmktec_k10`

NetBox receives only inventory and connectivity facts. SNMPv3 usernames,
authentication secrets, privacy secrets, and PDU mutation controls stay in
Ansible Vault.

### AAA Sequence

Do not enroll every host/device at once. Use a gated sequence:

1. Normalize identity controller secrets into vault-backed operations.
2. Enroll one Linux client through SSSD.
3. Validate one network device through FreeRADIUS.
4. Validate AP7901 RADIUS auth while retaining local break-glass.
5. Expand to UPS, ATS, PDU, switches, WAPs, routers, VPN edges, and HTTP apps.

The AP7901 RADIUS step depends on NetBox non-secret inventory first so power
automation, observability, and AAA all reference the same device identity.

## Testing

- Shell tests assert new enum fields exist in `netboot_assets` and
  `routeros_pathb`.
- Shell tests assert manifests expose `protocolFlow`.
- NetBox intake validator runs against all inventory files.
- NetBox dry-run plan must include K10 and AP7901 records without requiring a
  live NetBox token.
- Existing Ansible syntax checks for netboot and RouterOS Path B must continue
  passing.

## Backout

The new fields are additive. Backout is to remove `netboot_protocol_flow` from
host vars and manifests. Existing `netboot_type` behavior remains unchanged.

NetBox intake additions are dry-run first. If live apply causes incorrect
records, remove or correct the K10/AP7901 rows and rerun the apply script with
`--update-existing` only after reviewing the dry-run plan.
