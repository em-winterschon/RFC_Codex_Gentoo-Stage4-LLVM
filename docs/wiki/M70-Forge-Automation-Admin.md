# M70 Forge Automation Admin

The first M70 node is reserved as `admin-sun99-forge-099070.rfc1918.host`
(`172.16.99.70`, MAC `00:07:32:78:65:C6`) and uses the
`metal-forge-automation-admin` Stage5 profile. Its primary NIC is connected to
CSS326 `ge14`, and its remote power path is AP7901 outlet 4 on
`pdu-rfc99-corectrl-099241`.

It is the migration target for Forge/Codex, Ansible, vault workflows, GitHub
CLI, X12AGAIN SoL access through `/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin`,
and restored `/root`, `/opt`, `/var/lib/ansible`, `/var/lib/codex`,
`/var/lib/forge-memory`, and `/var/lib/git` continuity data.

Provisioning is tracked as UEFI PXE to iPXE with static DHCP address
`172.16.99.70`, boot file `m70-forge-ipxe.efi`, and netboot publisher
`172.16.99.88`.

2026-05-13 live validation uses Hasslehoff `/dev/ttyUSB3` for serial console
and a local SATADOM ESP iPXE chainloader because the firmware did not expose a
usable UEFI PXE NIC entry. The M70-specific iPXE binary successfully chained the
published HTTP role and reached SSH at `172.16.99.70`.

The follow-up reboot validated the corrected `netboot0` dracut cmdline. The live
OS now exposes the management NIC as `netboot0`.

Later on 2026-05-13 the M70 stopped answering ARP from X12AGAIN and Hasslehoff
while CSS326 `ge14` still reported link up and the serial console remained at a
Linux login prompt. A PDU outlet-4 reboot restored the iPXE chainload and SSH.
Post-boot evidence showed this is a live-rootfs profile durability problem:
`netboot0` was correct after reboot, but hostname was still
`gmktek-k10-stage5`, `dhcpcd` was marked crashed, and `sssd` lacked
`/etc/sssd/sssd.conf`.

On 2026-05-14 the live enrollment was repaired. The FreeIPA host object existed
without `krbprincipalname`, so `ipa-getkeytab` failed with `PrincipalName not
found`; adding the canonical host principal fixed keytab generation. The live
apply now forces the active OpenRC hostname, removes the stale K10 hosts entry,
starts SSSD, validates `codex-admin` through NSS/PAM/SSH key lookup, and leaves
the host with a valid `/etc/krb5.keytab`.

Current blockers before this can replace X12AGAIN: convert the transient live
validation into a persistent Stage5 install, keep `/dev/sda` as the EFI/iPXE
boot disk only, use `/dev/nvme0n1` and `/dev/nvme1n1` as destructive mirrored
ZFS targets after a final health check, fix installed-system networking so
`dhcpcd` is not part of the static management path, and resolve the observed
32 GiB memory report against the planned 64 GiB inventory.
