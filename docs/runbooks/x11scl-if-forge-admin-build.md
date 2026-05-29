# X11SCL-IF Forge Admin Build Runbook

This runbook prepares the Supermicro X11SCL-IF to become the long-term Forge
automation-admin host. It intentionally does not replace the M70 until
acceptance gates pass.

## Safety Boundary

- Do not reimage X12AGAIN/Prinzessin during this work.
- Do not repoint `forge.rfc1918.host` or related aliases until validation
  passes.
- Keep the M70 online as the continuity host and rollback target.
- Record raw hardware evidence under operator-private storage, not in git.

## Physical Assembly

1. Install the replacement X11SCL-IF heatsink.
2. Install the current 2 x 16 GiB ECC UDIMMs.
3. Install 2 x Samsung 883-DCT 2TB SATA SSDs.
4. Install the selected QLogic RDMA-capable NIC if slot/cooling permits.
5. Install the M.2 NVMe only as scratch/build-cache storage.
6. Cable management NIC, BMC, serial if available, and PDU outlet.

## First Power-On

1. Validate POST and temperatures in BIOS/BMC.
2. Set UEFI-only boot policy where possible.
3. Disable legacy/CSM unless required for temporary diagnostics.
4. Enable virtualization features.
5. Enable SR-IOV/ARI/IOMMU settings if present.
6. Record BIOS and BMC firmware versions.
7. Assign BMC management IP/DNS after MAC discovery.

## Evidence Capture

Capture these before disk provisioning:

```sh
hostname
date -Is
dmidecode
lspci -nnvv
lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,WWN
blkid
ip -br link
ethtool -i <management-nic>
ethtool -i <qlogic-nic>
smartctl -a /dev/sdX
nvme list
```

Store raw output under an operator-private path such as:

```text
/root/operator-private/x11scl-if/preinstall/<timestamp>/
```

## Inventory Inputs To Collect

The following fields are required before creating final NetBox/IPAM records:

- Host serial number.
- BMC MAC and chosen BMC IP.
- Primary management NIC MAC and chosen SUN99 management IP.
- Switch name and switch port.
- PDU name and outlet.
- QLogic NIC model, PCI address, MACs, and connected switch ports.
- SATA SSD serials.
- NVMe serial and lane mapping.
- BIOS and BMC firmware versions.

## Provisioning Pattern

Use the existing `metal-forge-automation-admin` Stage5 profile unless a real
gap is found during provisioning.

Preferred storage:

```text
Samsung 883-DCT 2TB + Samsung 883-DCT 2TB -> mirrored zroot
M.2 NVMe -> scratch/build-cache only
```

Required ZFS datasets:

```text
zroot/ROOT/gentoo
zroot/home
zroot/opt
zroot/srv
zroot/tmp
zroot/usr-local
zroot/var-lib
zroot/var-log
```

## Continuity Restore

Restore only after the persistent root boots cleanly:

- `/root`
- `/opt`
- `/var/lib/ansible`
- `/var/lib/codex`
- `/var/lib/forge-memory`
- `/var/lib/git`

Prefer restoring from the latest off-host X12AGAIN backup. If the M70 has newer
Forge continuity state, capture an M70 backup first and restore from that
snapshot instead.

## Validation

Run:

```sh
hostname -f
findmnt -no SOURCE,FSTYPE,TARGET /
zpool status -x
ip -br addr
ip route
ansible --version
ansible-vault --version
git status
git lfs version
gh auth status
getent passwd codex-admin
sss_ssh_authorizedkeys codex-admin
```

Then validate reachability:

```sh
ping -c 3 172.16.99.1
ping -c 3 172.16.99.9
curl -fsS http://172.16.99.62/api/
curl -fkIs https://msg-sun99-ntfysys-099096.rfc1918.host/
/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin chassis status
```

## Cutover

Only after validation:

1. Create a post-install backup.
2. Update NetBox primary role/status from planned to active.
3. Repoint `admin-sun99-forge.rfc1918.host`, `forge.rfc1918.host`, and
   `forge-sun99.rfc1918.host` to the X11SCL-IF.
4. Validate from X12AGAIN, Hasslehoff, and the M70.
5. Leave the M70 online as rollback for at least one reboot cycle.

## Backout

If validation fails, leave aliases on the M70 and keep X12AGAIN online. Do not
debug by mutating X12AGAIN. Rebuild or repair the X11SCL-IF in place, then rerun
the full validation sequence.
