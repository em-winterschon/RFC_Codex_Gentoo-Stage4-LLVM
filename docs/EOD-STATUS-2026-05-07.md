# EOD Status 2026-05-07

## Completed

- Advanced the GMKtek K10 from firmware discovery into a validated Path B
  bare-metal netboot target.
- Confirmed the K10 boot chain:
  - UEFI PXE/TFTP fetches `k10-ipxe.efi` from `172.16.99.108`
  - iPXE fetches `hosts/gmktek-k10-stage5.ipxe`
  - role handoff loads `g/vmlinuz` and `g/initramfs-gz.img`
  - kernel command line uses `initrd=initrd.magic`
  - dracut uses static networking for `172.16.99.156/24`
  - HTTP rootfs fetch succeeds
  - Gentoo live login prompt is reached
- Added the K10 to local Ansible inventory as the Stage5 workstation bare-metal
  validation host:
  - model: `GMKtek NucBox K10`
  - CPU: `Intel Core i9-13900HK`
  - GPU: `Intel Iris Xe`
  - boot NIC MAC: `84:47:09:5F:21:64`
  - switch path: CSS326 `ge16`
  - static address: `172.16.99.156`
- Added RouterOS DHCP option support for the K10 fallback path:
  - option 67: `k10-ipxe.efi`
  - next-server: `172.16.99.108`
  - UEFI PXE client-class scoping
- Patched Path B artifact generation so future dracut initramfs builds include
  Realtek RTL8125B firmware from `sys-kernel/linux-firmware`.
- Added AP7901 PDU credential import automation:
  - plaintext source remains operator-private
  - encrypted vault stores the `vault_pdu_rfc99_corecontrol_*` values
  - K10 power control must verify outlet label `host_gmktec_k10` before
    mutating outlet command OIDs
- Validated live NetBox API reachability at `172.16.99.62` and confirmed the
  current gap: K10 and the AP7901 PDU are not yet present in live NetBox.
- Reconfirmed local ntfy endpoint and topics:
  - endpoint: `http://msg-sun99-ntfysys.rfc1918.host`
  - alert topic: `codex-alerts-rfc99-sun99-3457621907`
  - reply topic: `codex-replies-rfc99-sun99-3457621907`
- Identified a notification-environment gap: the active shell falls back to
  `https://ntfy.sh` with no topics unless the local export file is sourced.
- Confirmed the central-auth direction remains FreeIPA, SSSD, and FreeRADIUS,
  with APC PDU/RADIUS enrollment dependent on non-secret power inventory first.

## Current Gates

- K10 has reached a live Gentoo prompt, but the Stage5 workstation installer has
  not yet been executed on the K10 target disk.
- K10 is tracked in Ansible inventory and documentation, but live NetBox has no
  K10 device, interface, IPAM, service-IP, or component records yet.
- The AP7901 PDU credentials are vaulted, but live NetBox has no non-secret PDU
  inventory record, management IP, SNMP capability tag, outlet map, or K10
  power-cable association yet.
- The netboot roles still encode `netboot_type` as IP assignment mode
  (`static`, `dhcp`, `bootp`) and do not yet model the protocol flow
  (`ipxe-direct`, `pxe-to-ipxe`, `uefi-httpboot`, `disabled`).
- The K10 static dracut command line is documented in the rendered iPXE role,
  but a Jenkins-consumable boot-image manifest does not exist yet.
- Local ntfy helpers need the LAN export file loaded by default before approval
  and status notifications can be treated as reliable operator plumbing.
- FreeIPA/RADIUS is live as a controller pattern, but broad host/device
  enrollment remains gated on vault cleanup, one Linux client validation, one
  network device validation, and one low-risk power-device validation.

## Major Pivots And Errors

- Native K10 UEFI HTTPBoot stalled after DHCP. The successful path is UEFI
  PXE/TFTP handoff to iPXE, then HTTP for the heavier assets.
- K10 dracut initially failed because the RTL8125B firmware was absent from the
  initramfs. The Path B artifact builder now includes the firmware package and
  forces the firmware path into future initramfs builds.
- iPXE reached the kernel while dracut skipped the initramfs until the handoff
  was normalized around `initrd=initrd.magic`.
- Live NetBox reachability is good, but inventory promotion is lagging behind
  operational discovery for the K10 and AP7901 PDU.

## Outstanding Actions

1. Add explicit netboot protocol-flow modeling so K10-style PXE-to-iPXE hosts
   are handled differently from normal iPXE-direct hosts.
2. Add boot-image manifests for reproducible dracut artifact generation and
   Jenkins rebuilds.
3. Promote K10 into NetBox through repo-safe inventory intake, including
   hostname, management IP, boot interface, switchport path, and hardware
   metadata.
4. Promote AP7901 PDU inventory into NetBox without secrets, including
   management IP, model, serial, SNMPv3 capability, outlet map, and K10 outlet
   relationship.
5. Normalize local ntfy environment loading so Codex hooks and Ansible callback
   notifications use the LAN service and current topics by default.
6. Continue central-auth rollout in this order:
   - vault identity controller secrets
   - enroll one Linux client with SSSD
   - validate one network device through FreeRADIUS
   - validate AP7901 RADIUS auth with local break-glass retained
   - widen to UPS, ATS, PDU, switches, WAPs, routers, and VPN endpoints
7. Run the K10 Stage5 workstation install workflow after NetBox/IPAM records are
   in place and a backout path is documented.

## Backout Summary

The K10 netboot changes are reversible by removing the K10 RouterOS static DHCP
lease option, leaving CSS326 `ge16` disconnected, and disabling the K10 host
entry in local inventory. The Path B firmware inclusion is safe to retain
because it only makes Realtek firmware available in the initramfs.

PDU vault import is non-destructive. Any future PDU control action must validate
the outlet label before writing an outlet command OID. NetBox PDU inventory must
remain non-secret; secrets stay in Ansible Vault.

## Next Work Block

1. Commit and push this EOD report, changelog, roadmap, and wiki mirror.
2. Write the approved netboot lifecycle and infrastructure-source-of-truth
   design spec.
3. Add an implementation plan for:
   - netboot protocol-flow enum
   - boot-image manifests
   - K10 NetBox intake
   - AP7901 PDU NetBox intake
   - AAA enrollment sequence updates
4. Implement the first automation slice with tests and docs before running any
   live NetBox writes.
