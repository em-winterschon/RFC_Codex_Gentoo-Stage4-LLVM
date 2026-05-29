# M70 Automation Admin Install Runbook

This runbook records the 2026-05-14 install pattern used for
`admin-sun99-forge-099070.rfc1918.host`. It is intended for the remaining M70
nodes after their hostnames, MACs, IPs, switch ports, and PDU outlets are
inventoried.

## Safety Boundary

- Do not mutate X12AGAIN/Prinzessin while using this runbook.
- Confirm the target host is netbooted into a disposable live environment before
  wiping disks.
- Keep `/dev/sda` as the UEFI iPXE anchor and use NVMe devices for the durable
  ZFS root unless a firmware update proves NVMe boot support.
- Store raw disk backups outside the repo under operator-private storage.

## Disk Pattern

The first M70 uses:

- `/dev/sda`: SATADOM, clean GPT, one 1 GiB EFI System Partition labeled
  `M70IPXE`.
- `/dev/sda1`: FAT32 ESP containing `EFI/BOOT/BOOTX64.EFI`.
- `/dev/nvme0n1` and `/dev/nvme1n1`: mirrored ZFS pool `zroot`.
- `zroot/ROOT/gentoo`: bootfs and persistent `/`.

The validated iPXE binary hash is:

```text
239b5526f919e4aa4a833763d6db972675796452df8389efe9cb57fea6bab278  BOOTX64.EFI
```

## Boot Policy

The SATADOM ESP starts iPXE. iPXE chains the host script:

```text
http://172.16.99.88:8080/hosts/admin-sun99-forge-099070.ipxe
```

The host script chains `roles/forge-automation-admin-zfs.ipxe`, which loads the
HTTP kernel/initramfs and boots:

```text
root=ZFS=zroot/ROOT/gentoo rw zfs_force=1 rd.zfs.force=1
```

The first M70 also passes:

```text
spl.spl_hostid=0x0951f603
bootdev=netboot0
ifname=netboot0:00:07:32:78:65:c6
ip=172.16.99.70::172.16.99.1:255.255.255.0:admin-sun99-forge-099070:netboot0:none
nameserver=172.16.99.63
```

Use a different `spl.spl_hostid`, MAC, hostname, and static IP for each
additional M70.

## Persistent Root Baseline

The initial persistent root was seeded from the validated live root with
`rsync -aAXH --numeric-ids`, excluding `/dev`, `/proc`, `/sys`, `/run`, `/tmp`,
`/mnt`, `/media`, and `/lost+found`.

Required persistent files:

- `/etc/hostname`: `admin-sun99-forge-099070`
- `/etc/conf.d/hostname`: `hostname="admin-sun99-forge-099070"`
- `/etc/conf.d/net`: initramfs uses static `netboot0`; persistent target uses
  `bond0 = netboot0 + enp3s0` for `172.16.99.70/24` and the default route.
- `/etc/hosts`: local fallback for `admin-sun99-forge-099070.rfc1918.host` and
  `ipa01.rfc1918.host`.
- `/etc/hostid` and `/etc/zfs/zpool.cache`: copied/generated from the live
  install session.
- `/etc/local.d/devpts.start`: remounts `/dev/pts` with
  `gid=5,mode=620,ptmxmode=666` for reliable remote PTY allocation.

Required OpenRC services:

- `zfs-import` in `sysinit`
- `zfs-mount` in `sysinit`
- `zfs-zed` in `default`
- `net.netboot0` in `default` for the pre-cutover state
- `net.bond0` in `default` after the 2026-05-24 approved bond migration
- `sshd` in `default`
- `local` in `default`

Do not enable `sssd` until the persistent root has a valid host keytab and
`/etc/sssd/sssd.conf`.

## Post-Boot Validation

Run after every reboot:

```sh
hostname -f
findmnt -no SOURCE,FSTYPE,TARGET /
zpool status -x
zfs list -o name,mountpoint,canmount
ip -br addr
ip route
ssh -tt root@172.16.99.70 'tty; mount | grep devpts; ls -l /dev/ptmx /dev/pts/ptmx'
```

Expected first M70 results:

- FQDN: `admin-sun99-forge-099070.rfc1918.host`
- Root: `zroot/ROOT/gentoo zfs /`
- Pool health: `all pools are healthy`
- Management before bond cutover: `netboot0` with `172.16.99.70/24`
- Management after bond cutover: `bond0` with `172.16.99.70/24`, members
  `netboot0` and `enp3s0`
- PTY: `/dev/pts` has `gid=5,mode=620,ptmxmode=666`

## M70 Bond Cutover Runbook

Use this only after CSS326 LACP group 2 is ready on `ge14` plus `ge17`.

Preflight:

```sh
ip -br addr
ip route
cat /proc/net/bonding/bond0
ethtool -i netboot0
ethtool -i enp3s0
ethtool -i eno1
ethtool -i eno2
ethtool -i eno3
ethtool -i eno4
```

Target `/etc/conf.d/net` fragment:

```sh
config_bond0="172.16.99.70/24"
routes_bond0="default via 172.16.99.1"
dns_servers_bond0="172.16.99.1 9.9.9.9"
slaves_bond0="netboot0 enp3s0"
mode_bond0="802.3ad"
miimon_bond0="100"
lacp_rate_bond0="fast"
xmit_hash_policy_bond0="layer3+4"

config_netboot0="null"
config_enp3s0="null"
config_eno1="null"
config_eno2="null"
config_eno3="null"
config_eno4="null"
```

Cutover:

```sh
cp -a /etc/conf.d/net /root/m70-net-pre-bond0-cutover.conf
rc-service net.bond0 stop || true
rc-service net.netboot0 stop
rc-service net.bond0 start
ip -br addr show bond0
ip route get 172.16.99.1
ssh -o BatchMode=yes root@172.16.99.70 'hostname -f; ip route get 172.16.99.1'
```

Backout:

```sh
cp -a /root/m70-net-pre-bond0-cutover.conf /etc/conf.d/net
rc-service net.bond0 stop || true
rc-service net.netboot0 start
ip -br addr show netboot0
ip route get 172.16.99.1
ssh -o BatchMode=yes root@172.16.99.70 'hostname -f; ip route get 172.16.99.1'
```

## Remaining Acceptance Work

- Re-apply FreeIPA/SSSD to the persistent root.
- Install `gh` from an overlay, upstream binary, or internal package source.
- Restore Forge/Codex continuity paths from the X12AGAIN off-host backup.
- Validate X12AGAIN SoL using `/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin`.
- Validate Hasslehoff, CCR2004, NetBox, FreeIPA, ntfy, GitHub, and backup target
  reachability from the M70.
