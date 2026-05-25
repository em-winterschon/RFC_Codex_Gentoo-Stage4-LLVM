# M70 Canary SATADOM EFI Carrier

## Purpose

The M70 canary firmware does not enumerate the mini-PCIe NVMe devices as
bootable targets. The durable boot path is therefore:

```text
SATADOM removable EFI fallback -> ZFSBootMenu -> NVMe rpool/ROOT/gentoo
```

The SATADOM is only the EFI carrier. The Gentoo root remains on the mirrored
KIOXIA NVMe `rpool`.

## Current Gate

Do not write to, repartition, format, or repurpose the SATADOM until the
operator explicitly approves the SATADOM EFI carrier write gate.

Current evidence:

- Direct NVMe boot entries do not appear in Aptio Setup.
- CSM-disabled mode did not expose NVMe boot options.
- UEFI BBS priorities list the SATADOM and `none`.
- CSM-enabled mode is the known rescue path for legacy PXE/iPXE.
- The existing boot role already renders ZFSBootMenu into the target EFI tree:
  - `/efi/EFI/ZBM/VMLINUZ.EFI`
  - `/efi/EFI/BOOT/BOOTX64.EFI`

## Device Identity

Expected SATADOM identity from the canary discovery pass:

```text
model: SATADOM-SH 3ME3
serial: 20180915AA9241033080
FreeBSD view: ada0
Linux expected class: /dev/disk/by-id/ata-*
```

Expected NVMe root members:

```text
/dev/disk/by-id/nvme-eui.8ce38e0403ef1a38
/dev/disk/by-id/nvme-eui.8ce38e0403ef1adf
```

Never select either NVMe path for SATADOM carrier work.

## Read-Only Discovery

Run these only after `ssh m70_canary` returns and the operator is not using the
serial console:

```bash
fuser -v /dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if01-port0
ssh m70_canary 'hostname -f'
ssh m70_canary 'lsblk -e7 -o NAME,KNAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,PARTLABEL,PARTUUID,MOUNTPOINTS'
ssh m70_canary 'find /dev/disk/by-id -maxdepth 1 -type l -printf "%f -> %l\n" | sort'
ssh m70_canary 'blkid | sort'
ssh m70_canary 'test -s /efi/EFI/ZBM/VMLINUZ.EFI && test -s /efi/EFI/BOOT/BOOTX64.EFI && sha256sum /efi/EFI/ZBM/VMLINUZ.EFI /efi/EFI/BOOT/BOOTX64.EFI'
```

The read-only pass must prove all of the following before any write step:

- the host is `sbsoc-accel-int64-m70n2.rfc1918.host`
- `/` is `rpool/ROOT/gentoo`
- the SATADOM path is identified by model or serial
- the SATADOM ESP candidate is not mounted read-write
- both ZFSBootMenu EFI source files exist under `/efi`

## Approval Gates

Two separate approvals exist.

Approval 1 allows a non-destructive copy into an existing SATADOM ESP:

```text
AAA SATADOM EFI carrier write gate: existing ESP copy approved
```

Approval 2 allows destructive SATADOM carrier conversion if no usable ESP
exists:

```text
AAA SATADOM EFI carrier destructive conversion approved
```

Approval 1 does not imply Approval 2.

## Existing ESP Copy Procedure

Use this path only when the read-only pass finds a valid SATADOM ESP partition.
The operator must approve Approval 1 before this procedure runs.

Set these variables in the remote shell after confirming the actual partition:

```bash
satadom_esp=/dev/disk/by-partlabel/M70_CANARY_EFI
backup_root=/root/m70-canary-satadom-backups/$(date -u +%Y%m%dT%H%M%SZ)
```

Copy procedure:

```bash
ssh m70_canary 'set -euo pipefail
satadom_esp=/dev/disk/by-partlabel/M70_CANARY_EFI
backup_root=/root/m70-canary-satadom-backups/$(date -u +%Y%m%dT%H%M%SZ)
mountpoint=/mnt/satadom-efi
test -b "${satadom_esp}"
test -s /efi/EFI/ZBM/VMLINUZ.EFI
test -s /efi/EFI/BOOT/BOOTX64.EFI
mkdir -p "${backup_root}" "${mountpoint}"
mount -o ro "${satadom_esp}" "${mountpoint}"
tar -C "${mountpoint}" -cpf "${backup_root}/satadom-efi.before.tar" .
find "${mountpoint}" -maxdepth 4 -type f -exec sha256sum {} + | sort > "${backup_root}/satadom-efi.before.sha256"
umount "${mountpoint}"
mount -o rw,sync "${satadom_esp}" "${mountpoint}"
install -d -m 0755 "${mountpoint}/EFI/ZBM" "${mountpoint}/EFI/BOOT"
install -m 0755 /efi/EFI/ZBM/VMLINUZ.EFI "${mountpoint}/EFI/ZBM/VMLINUZ.EFI"
install -m 0755 /efi/EFI/BOOT/BOOTX64.EFI "${mountpoint}/EFI/BOOT/BOOTX64.EFI"
sync
find "${mountpoint}/EFI" -maxdepth 4 -type f -exec sha256sum {} + | sort > "${backup_root}/satadom-efi.after.sha256"
umount "${mountpoint}"
cat "${backup_root}/satadom-efi.after.sha256"'
```

## Destructive Carrier Conversion

Use this path only when the SATADOM has no valid ESP and the operator approves
Approval 2. This wipes the selected SATADOM device.

```bash
ssh m70_canary 'set -euo pipefail
satadom_disk=/dev/disk/by-id/ata-SATADOM_SH_3ME3_20180915AA9241033080
test -b "${satadom_disk}"
sgdisk --zap-all "${satadom_disk}"
sgdisk -n 1:1MiB:+512MiB -t 1:EF00 -c 1:M70_CANARY_EFI "${satadom_disk}"
partprobe "${satadom_disk}"
mkfs.vfat -F32 -n M70_EFI /dev/disk/by-partlabel/M70_CANARY_EFI'
```

After conversion, run the existing ESP copy procedure.

## Validation

Before any reboot:

```bash
ssh m70_canary 'findmnt /mnt/satadom-efi >/dev/null && exit 1 || true'
ssh m70_canary 'blkid /dev/disk/by-partlabel/M70_CANARY_EFI'
ssh m70_canary 'zpool status rpool'
```

Boot validation remains operator-gated. After the operator confirms the serial
console is free and the boot test is approved:

1. Boot with CSM enabled.
2. Leave the SATADOM as the first UEFI hard-disk target.
3. Do not remove the temporary iPXE bridge until SATADOM boot succeeds twice.
4. After boot, validate:

   ```bash
   ssh m70_canary 'hostname -f'
   ssh m70_canary 'findmnt -no SOURCE,FSTYPE /'
   ssh m70_canary 'zpool status rpool'
   ssh m70_canary 'rc-status default'
   ssh m70_canary 'ovs-appctl bond/show ovs_workload0'
   ```

Acceptance requires `rpool/ROOT/gentoo`, `rpool ONLINE`, and
`lacp_status: negotiated`.

## Rollback

If SATADOM boot fails:

1. Keep the temporary iPXE bridge role in place.
2. Reboot through the known legacy PXE/iPXE path.
3. Restore the pre-change SATADOM ESP backup only after the canary is reachable:

   ```bash
   ssh m70_canary 'set -euo pipefail
   satadom_esp=/dev/disk/by-partlabel/M70_CANARY_EFI
   backup_tar=$(find /root/m70-canary-satadom-backups -mindepth 2 -maxdepth 2 -name satadom-efi.before.tar | sort | tail -n1)
   mountpoint=/mnt/satadom-efi
   test -b "${satadom_esp}"
   test -f "${backup_tar}"
   mkdir -p "${mountpoint}"
   mount -o rw,sync "${satadom_esp}" "${mountpoint}"
   find "${mountpoint}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
   tar -C "${mountpoint}" -xpf "${backup_tar}"
   sync
   umount "${mountpoint}"'
   ```

4. Record the failure mode in `docs/M70-CANARY-VALIDATION-LANE.md` before the
   next boot attempt.
