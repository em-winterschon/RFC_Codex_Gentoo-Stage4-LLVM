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

Current blockers before this can replace X12AGAIN: rebuild or overlay the rootfs
so hostname is `admin-sun99-forge-099070` instead of the K10 hostname, render
host-specific `sssd.conf` and secure firstboot enrollment, create the missing
FreeIPA host principal through an admin ticket or host OTP, fix installed-system
networking so `dhcpcd` is not crashed after boot, and resolve the observed
32 GiB memory report against the planned 64 GiB inventory.
