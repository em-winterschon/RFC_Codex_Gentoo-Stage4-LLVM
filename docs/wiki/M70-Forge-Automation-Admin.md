# M70 Forge Automation Admin

The first M70 node is reserved as `admin-sun99-forge-099070.rfc1918.host`
(`172.16.99.70`, MAC `00:07:32:78:65:C6`) and uses the
`metal-forge-automation-admin` Stage5 profile. Its primary NIC is connected to
CSS326 `ge14`, and its remote power path is AP7901 outlet 4 on
`pdu-rfc99-corectrl-099241`. The AP7901 control-panel outlet label is
`admin-sun99-forge`.

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

The follow-up reboot validated the corrected `netboot0` dracut cmdline. The
persistent OS now exposes the management NIC as `netboot0`.

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
the host with a valid `/etc/krb5.keytab`. After the persistent ZFS root came
online, the same client apply was re-run and validated `/etc/krb5.keytab`,
`/etc/sssd/sssd.conf`, SSSD service startup, NSS/PAM lookup, SSSD SSH
authorized-key lookup, and non-root `codex-admin` SSH on the persistent host.

Also on 2026-05-14 the SATADOM boot path was backed up before disk prep under
`/root/operator-private/m70/preinstall/`. After confirming the live root was the
netboot overlay and neither NVMe disk was mounted, `/dev/sda` was wiped and
rebuilt as a clean 1 GiB `M70IPXE` ESP containing the published
`m70-forge-ipxe.efi` binary, and both NVMe devices were wiped by clearing
filesystem signatures plus the head and tail GPT regions.

The active persistent layout is now a mirrored ZFS root named `zroot` across the
two KIOXIA NVMe devices. `bootfs=zroot/ROOT/gentoo`, iPXE chains the
`forge-automation-admin-zfs` role, and repeat reboot validation returned
hostname `admin-sun99-forge-099070`, root source `zroot/ROOT/gentoo`, and a
healthy pool.

The first live admin baseline installed Ansible, `ansible-vault`, `ipmitool`,
`nmap`, `tcpdump`, `tmux`, `jq`, `pciutils`, `usbutils`, `gentoolkit`, `eix`,
Git, and the existing static `/usr/local/bin/gh` 2.88.1 binary from the current
automation host. The copied `gh` binary SHA256 is
`c1be595a7357120e28886922c050fed34ad347c36adf37370ad91d4972a416d5`; `gh auth
status` validates when the current Forge token is supplied through the
environment.

Current blockers before this can replace X12AGAIN: restore Forge continuity
data from the off-host X12AGAIN backup, validate X12AGAIN SoL from M70, and
resolve the observed 32 GiB memory report against the planned 64 GiB inventory.

## Intel QAT

The M70 Atom C3000 platform exposes Intel QuickAssist at PCI `01:00.0`
(`8086:19e2`). Live validation on 2026-05-14 showed kernel driver `c3xxx`,
module `qat_c3xxx`, supporting module `intel_qat`, and in-tree kernel config for
`CONFIG_CRYPTO_DEV_QAT_C3XXX=m` plus `CONFIG_CRYPTO_DEV_QAT_C3XXXVF=m`.

The profile includes the reusable `stage5-metal-intel-platform` package layer
for `sys-firmware/intel-microcode` and `sys-kernel/linux-firmware`, and it loads
`intel_qat` plus `qat_c3xxx`. Application consumers stay gated: OpenSSL,
HAProxy, Nginx, and OpenZFS must each get benchmark evidence and rollback
commands before QAT acceleration is enabled in production. OpenZFS+QAT is
tracked as a separate CI/CD artifact lane because Gentoo does not currently
treat QAT-enabled ZFS as the stock ebuild path.

Live installation on 2026-05-14 completed `sys-firmware/intel-microcode`,
`sys-kernel/linux-firmware`, and `sys-apps/iucode_tool`. The required C3000 QAT
firmware files are present at `/lib/firmware/intel/qat/qat_c3xxx.bin` and
`/lib/firmware/intel/qat/qat_c3xxx_mmp.bin`.
