# EOD Status 2026-05-22

## Completed

- Continued the M70 validation migration on branch `m70-canary-validation-lane`
  and kept PR #144 open as a draft against `codex/slurm-pilot-control-plane`.
- Added the approved M70 canary validation lane:
  - documented the i211 management/rescue split and X553 OVS/LACP workload
    topology
  - captured cable, NetBox, boot, management failover, OVS/LACP,
    runtime-network, and promotion gates
  - preserved the rule that the canary validates risky runtime/netboot changes
    before promotion to the primary Forge M70
- Refreshed the primary M70 serial-console map after the powered USB hub swap.
  Stable `/dev/serial/by-id` paths survived, while runtime `/dev/ttyUSB*`
  aliases shifted.
- Recorded the CRS354 management-port move:
  - CSS326 `ge15` now carries CRS354 `ether49`
  - CSS326 `ge24` is released for the M70 canary `eno4`
  - NetBox cable `4` models the CSS326 `ge15` to CRS354 `ether49` link
- Modeled the M70 canary in NetBox and repo intake:
  - device: `m70_canary`
  - role: `m70-canary-validation`
  - `netboot0` MAC: `00:07:32:58:73:34`
  - six Ethernet links from CSS326 `ge19` through `ge24`
  - AP7901 outlet 7 to `m70_canary:power0`
- Confirmed SwOS link state for CSS326 `ge19` through `ge24` in the local
  operator-private SwOS snapshot.
- Verified that passive DHCP/ARP/tcpdump checks did not yet observe the M70
  canary `netboot0` MAC.
- Verified that passive 115200 serial capture on both spare FT2232H paths did
  not yet produce M70 canary console bytes.
- Corrected stale DNS resolver state on the primary Forge M70:
  - removed `172.16.99.63` from `/etc/resolv.conf`
  - removed `172.16.99.63` from `/etc/conf.d/net`
  - changed `/etc/kernel/cmdline` to `nameserver=172.16.99.1`
  - kept `172.16.99.1` primary and `9.9.9.9` fallback
- Verified that `172.16.99.63` is the FreeIPA identity controller but is not a
  DNS listener on TCP/UDP 53 today.
- Verified that RouterOS DNS at `172.16.99.1` resolves internal
  `rfc1918.host` names and forwards external names.
- Added the netboot DNS validation gate:
  - `scripts/validate_netboot_dns.py`
  - `netboot-dns-policy.yml`
  - static policy validation before Path B iPXE/PXE asset publish
  - optional live TCP/UDP resolver validation on publishers
  - explicit deny for `172.16.99.63` until FreeIPA DNS is intentionally
    enabled and validated
- Updated K10 Path B netboot DNS values to use `172.16.99.1` primary with
  `9.9.9.9` fallback.
- Confirmed current NetBox hostname/service identity:
  - VM object: `svc-netbox-stage4`
  - API URL: `http://172.16.99.62`
  - service/DNS alias: `netbox-http.rfc1918.host`
  - no `dcim-rfc99-netbox.rfc1918.host` record is currently modeled
- Clarified the current FreeIPA to NetBox admin process:
  - FreeIPA users are modeled through `identity-source-definitions/local-rfc1918.yml`
  - FreeIPA mutation remains gated through `IDENTITY_SYNC_APPLY=1` and
    provider-specific gates
  - NetBox admin rights remain local-NetBox permissions until FreeIPA/NetBox
    SSO and group mapping are implemented
- Rotated the live NetBox local `admin` password.
- Stored active NetBox credential material in the encrypted local-network Vault:
  - `vault_netbox_admin_username`
  - `vault_netbox_admin_password`
  - `vault_netbox_api_token`
  - token metadata fields
- Preserved `/root/operator-private/netbox/svc-netbox-stage4-admin-token` as
  the root-only break-glass API token file.
- Updated Vault and identity documentation so the next operator does not chase a
  missing NetBox Vault key.

## Commits Pushed

- `486361c` - Document M70 canary validation lane
- `e036567` - Refresh M70 serial aliases after hub power swap
- `a455b4f` - Document M70 canary cabling plan
- `30f8960` - Record CRS354 management move to ge15
- `887c1fc` - Model M70 canary cabling in NetBox intake
- `8c51807` - Document M70 DNS resolver correction
- `e4945d4` - Add netboot DNS validation gate
- `4dac910` - Format netboot DNS validation test
- `3e364e4` - Store NetBox admin credentials in vault

## Verification

- `git diff --check`
  - result: pass before commits
- `python3 scripts/validate_netbox_inventory_intake.py gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites`
  - result: pass during M70 canary intake work
- NetBox intake dry run for `local-rfc1918-lab.yml`
  - result: pass
- `bash tests/shell/test_netbox_inventory_intake.sh`
  - result: pass
- `bash tests/shell/test_local_network_inventory.sh`
  - result: pass
- Live NetBox API readback confirmed CSS326 `ge15`, CSS326 `ge19` through
  `ge24`, CRS354 `ether49`, device `m70_canary`, AP7901 outlet 7, and cables
  `4` through `11`.
- SwOS snapshot confirmed CSS326 `ge19` through `ge24` are enabled and linked.
- `nmap -sTU -p 53 172.16.99.63`
  - result: TCP/UDP 53 closed
- DNS checks against `172.16.99.1`
  - result: internal `rfc1918.host` and external forwarding work
- `python3 -m py_compile scripts/validate_netboot_dns.py`
  - result: pass
- `bash tests/shell/test_netboot_dns_validation.sh`
  - result: pass
- `bash tests/shell/test_netboot_assets.sh`
  - result: pass
- `python3 scripts/validate_netboot_dns.py --policy .../netboot-dns-policy.yml --path .../netboot-image-manifests --live`
  - result: live TCP/UDP DNS validation passed for `172.16.99.1` and `9.9.9.9`
- `ansible-playbook -i inventories/examples/hosts.yml playbooks/netboot-path-b.yml --syntax-check`
  - result: pass
- `ansible-playbook -i inventories/local-network/hosts.yml playbooks/netboot-path-b.yml --syntax-check`
  - result: pass
- `bash tests/shell/test_identity_source_of_truth.sh`
  - result: pass
- `bash tests/shell/test_identity_apply_plan.sh`
  - result: pass
- `scripts/validate-ansible-vaults.sh .../inventories/local-network/group_vars/all/vault.yml`
  - result: pass
- Vault key-name check confirmed the expected `vault_netbox_*` variables are
  present without printing secret values.
- Vault-backed NetBox API token validated against live NetBox status.
- Vault-backed NetBox `admin` password validated through the NetBox web login
  flow.
- `bash tests/shell/test_ansible_vault_tools.sh`
  - result: pass
- PR #144 GitHub checks after the NetBox credential vault commit:
  - `pre-commit`: pass
  - `shell-tests`: pass
  - `notify`: pass

## Current Gates

- M70 canary has not yet emitted observable DHCP/ARP/iPXE traffic from
  `netboot0`.
- M70 canary serial path remains unidentified. Physical RS232 is attached, but
  neither spare FT2232H path produced console bytes during passive capture.
- M70 canary hostname, management IP, and the remaining five NIC MAC addresses
  are still pending boot discovery and NetBox update.
- FreeIPA DNS remains disabled or not listening on `172.16.99.63`; do not use
  that host as a netboot or static resolver until TCP/UDP 53 validates.
- NetBox still uses local `admin` access for UI administration. FreeIPA-backed
  NetBox SSO/group mapping is not active yet.
- The branch remains a draft PR. It is pushed and validated, but not merged.
- No reboot was performed on the primary Forge M70.

## Major Errors Or Direction Changes

- The stale resolver source was local M70 configuration and kernel cmdline, not
  the RouterOS role defaults. RouterOS DHCP role state already advertised
  `172.16.99.1` only for DNS.
- The initial PR-body update for the netboot DNS gate used shell backticks in a
  double-quoted string and was mangled by command substitution. The PR body was
  corrected immediately using plain text.
- The first pushed netboot DNS test failed GitHub `pre-commit` because `shfmt`
  wanted heredoc and redirection spacing changes. A follow-up formatting commit
  fixed it and all checks passed.
- NetBox documentation claimed an admin password was generated during initial
  bootstrap, but the password was not present in Vault or in the M70
  operator-private NetBox directory. The local `admin` password was therefore
  rotated and stored properly in Vault.

## Outstanding Actions

1. Boot the M70 canary far enough to observe BIOS, iPXE, or OS console output,
   then bind the correct RS232 by-id path to the canary record.
2. Observe M70 canary `netboot0` traffic, then add its hostname, primary
   management IP, and DNS records to NetBox/source-of-truth.
3. Discover and record the remaining five M70 canary NIC MAC addresses.
4. Use the canary for Intel and AMD microcode, initramfs, IOMMU, OVS/LACP,
   Kata, Firecracker, QEMU, LXC, and runtime package validation before
   promoting changes to the primary Forge M70.
5. Add ATS/PDU/UPS serial paths after RJ12 adapters are installed and by-id
   paths are validated.
6. Implement the durable FreeIPA to NetBox SSO/group mapping path:
   repo-modeled `netbox-admin` group, NetBox auth configuration, and explicit
   validation that the group maps to the intended admin permission set.
7. Keep NetBox as the source of truth for FMT2/SUN99 inventory and continue
   adding gap-analysis findings through intake/apply workflows.

## Backout Summary

- Repo-side M70 canary lane commits are isolated on
  `m70-canary-validation-lane` and can be reverted independently before merge.
- NetBox canary intake changes are modeled in repo source-of-truth and already
  applied live; any rollback should be done by applying a deliberate NetBox
  intake change rather than manual object deletion.
- Resolver changes on the primary M70 were live local file edits. If FreeIPA DNS
  is intentionally enabled later, update `/etc/resolv.conf`, `/etc/conf.d/net`,
  `/etc/kernel/cmdline`, and `netboot-dns-policy.yml` together after TCP/UDP 53
  validation.
- NetBox `admin` password rotation is live. The encrypted Vault now stores the
  active value, and the root-only operator-private API token file remains
  available as break-glass.

## Next Work Block

1. Commit and push this EOD report and wiki mirror.
2. Continue M70 canary boot/serial discovery.
3. Add the canary management identity to NetBox once DHCP/ARP/iPXE evidence is
   observed.
4. Prepare the canary netboot validation sequence for microcode, initramfs, and
   OVS/LACP runtime networking.
5. Start the FreeIPA-backed NetBox admin design only after the current local
   admin credential vaulting is accepted as the stable break-glass baseline.
