# M70 Canary SATADOM EFI Carrier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the M70 canary boot durable by using the SATADOM as an EFI carrier for ZFSBootMenu while keeping the Gentoo root on the mirrored NVMe `rpool`.

**Architecture:** The existing boot role already renders ZFSBootMenu into the target EFI tree. The SATADOM workflow adds a gated carrier step that first discovers the SATADOM read-only, then either copies EFI payloads into an existing ESP or performs an explicitly approved destructive conversion.

**Tech Stack:** Gentoo, OpenRC, ZFSBootMenu, ZFS, Ansible, shell validation, NetBox/DNS source-of-truth workflow.

---

### Task 1: Read-Only Canary State Check

**Files:**
- Read: `docs/M70-CANARY-SATADOM-EFI-CARRIER.md`
- Read: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/host_vars/m70_canary.yml`

- [ ] **Step 1: Confirm serial is free**

Run:

```bash
fuser -v /dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if01-port0
```

Expected: exit `1` with no listed process, or explicit operator confirmation
that their serial session is detached.

- [ ] **Step 2: Confirm SSH returns through the alias**

Run:

```bash
ssh m70_canary 'hostname -f'
```

Expected:

```text
sbsoc-accel-int64-m70n2.rfc1918.host
```

- [ ] **Step 3: Confirm the installed root**

Run:

```bash
ssh m70_canary 'findmnt -no SOURCE,FSTYPE /; zpool status rpool'
```

Expected: `/` is `rpool/ROOT/gentoo` with filesystem type `zfs`, and `rpool`
is `ONLINE`.

- [ ] **Step 4: Capture block-device evidence**

Run:

```bash
ssh m70_canary 'lsblk -e7 -o NAME,KNAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,PARTLABEL,PARTUUID,MOUNTPOINTS'
ssh m70_canary 'find /dev/disk/by-id -maxdepth 1 -type l -printf "%f -> %l\n" | sort'
ssh m70_canary 'blkid | sort'
```

Expected: the SATADOM is identifiable by model or serial, and neither
`nvme-eui.8ce38e0403ef1a38` nor `nvme-eui.8ce38e0403ef1adf` is selected for
carrier work.

### Task 2: Existing ESP Copy

**Files:**
- Read: `docs/M70-CANARY-SATADOM-EFI-CARRIER.md`
- Modify live host only after Approval 1.

- [ ] **Step 1: Confirm Approval 1**

Required operator text:

```text
AAA SATADOM EFI carrier write gate: existing ESP copy approved
```

- [ ] **Step 2: Confirm source payloads**

Run:

```bash
ssh m70_canary 'test -s /efi/EFI/ZBM/VMLINUZ.EFI && test -s /efi/EFI/BOOT/BOOTX64.EFI && sha256sum /efi/EFI/ZBM/VMLINUZ.EFI /efi/EFI/BOOT/BOOTX64.EFI'
```

Expected: two SHA256 lines.

- [ ] **Step 3: Backup the SATADOM ESP before writing**

Run with the confirmed SATADOM ESP path:

```bash
ssh m70_canary 'set -euo pipefail
satadom_esp=/dev/disk/by-partlabel/M70_CANARY_EFI
backup_root=/root/m70-canary-satadom-backups/$(date -u +%Y%m%dT%H%M%SZ)
mountpoint=/mnt/satadom-efi
test -b "${satadom_esp}"
mkdir -p "${backup_root}" "${mountpoint}"
mount -o ro "${satadom_esp}" "${mountpoint}"
tar -C "${mountpoint}" -cpf "${backup_root}/satadom-efi.before.tar" .
find "${mountpoint}" -maxdepth 4 -type f -exec sha256sum {} + | sort > "${backup_root}/satadom-efi.before.sha256"
umount "${mountpoint}"
printf "%s\n" "${backup_root}"'
```

Expected: prints the backup directory path.

- [ ] **Step 4: Copy the EFI payload**

Run:

```bash
ssh m70_canary 'set -euo pipefail
satadom_esp=/dev/disk/by-partlabel/M70_CANARY_EFI
backup_root=$(find /root/m70-canary-satadom-backups -mindepth 1 -maxdepth 1 -type d | sort | tail -n1)
mountpoint=/mnt/satadom-efi
test -b "${satadom_esp}"
test -d "${backup_root}"
test -s /efi/EFI/ZBM/VMLINUZ.EFI
test -s /efi/EFI/BOOT/BOOTX64.EFI
mount -o rw,sync "${satadom_esp}" "${mountpoint}"
install -d -m 0755 "${mountpoint}/EFI/ZBM" "${mountpoint}/EFI/BOOT"
install -m 0755 /efi/EFI/ZBM/VMLINUZ.EFI "${mountpoint}/EFI/ZBM/VMLINUZ.EFI"
install -m 0755 /efi/EFI/BOOT/BOOTX64.EFI "${mountpoint}/EFI/BOOT/BOOTX64.EFI"
sync
find "${mountpoint}/EFI" -maxdepth 4 -type f -exec sha256sum {} + | sort > "${backup_root}/satadom-efi.after.sha256"
umount "${mountpoint}"
cat "${backup_root}/satadom-efi.after.sha256"'
```

Expected: SHA256 lines for `EFI/ZBM/VMLINUZ.EFI` and
`EFI/BOOT/BOOTX64.EFI`.

### Task 3: Destructive Carrier Conversion

**Files:**
- Read: `docs/M70-CANARY-SATADOM-EFI-CARRIER.md`
- Modify live SATADOM only after Approval 2.

- [ ] **Step 1: Confirm Approval 2**

Required operator text:

```text
AAA SATADOM EFI carrier destructive conversion approved
```

- [ ] **Step 2: Convert the SATADOM to a single ESP**

Run only after confirming the exact by-id path:

```bash
ssh m70_canary 'set -euo pipefail
satadom_disk=/dev/disk/by-id/ata-SATADOM_SH_3ME3_20180915AA9241033080
test -b "${satadom_disk}"
sgdisk --zap-all "${satadom_disk}"
sgdisk -n 1:1MiB:+512MiB -t 1:EF00 -c 1:M70_CANARY_EFI "${satadom_disk}"
partprobe "${satadom_disk}"
mkfs.vfat -F32 -n M70_EFI /dev/disk/by-partlabel/M70_CANARY_EFI'
```

Expected: `/dev/disk/by-partlabel/M70_CANARY_EFI` exists and `blkid` reports a
FAT32 ESP.

- [ ] **Step 3: Run Task 2**

Expected: the copy procedure succeeds and produces `satadom-efi.after.sha256`.

### Task 4: Boot Validation

**Files:**
- Modify: `docs/M70-CANARY-VALIDATION-LANE.md`
- Modify: `docs/wiki/M70-Canary-Validation-Lane.md`

- [ ] **Step 1: Confirm the SATADOM ESP is unmounted**

Run:

```bash
ssh m70_canary 'findmnt /mnt/satadom-efi >/dev/null && exit 1 || true'
```

Expected: exit `0`.

- [ ] **Step 2: Boot-test through SATADOM**

Operator action: boot with CSM enabled and leave the SATADOM as the first UEFI
hard-disk target. Keep the temporary iPXE bridge intact.

- [ ] **Step 3: Validate post-boot state**

Run:

```bash
ssh m70_canary 'hostname -f'
ssh m70_canary 'findmnt -no SOURCE,FSTYPE /'
ssh m70_canary 'zpool status rpool'
ssh m70_canary 'rc-status default'
ssh m70_canary 'ovs-appctl bond/show ovs_workload0'
```

Expected: hostname is `sbsoc-accel-int64-m70n2.rfc1918.host`, `/` is
`rpool/ROOT/gentoo zfs`, `rpool` is `ONLINE`, and OVS reports
`lacp_status: negotiated`.

- [ ] **Step 4: Record the result**

Add the result to both:

```text
docs/M70-CANARY-VALIDATION-LANE.md
docs/wiki/M70-Canary-Validation-Lane.md
```

Then run:

```bash
bash tests/shell/test_m70_canary_docs.sh
git diff --check
```

Expected: both commands pass.

### Task 5: Rollback

**Files:**
- Modify: `docs/M70-CANARY-VALIDATION-LANE.md`
- Modify: `docs/wiki/M70-Canary-Validation-Lane.md`

- [ ] **Step 1: Keep the temporary iPXE bridge**

Run:

```bash
cat /root/m70-canary-netboot-shim/hosts/m70-canary.ipxe
```

Expected: the host still chains into the installed-root bridge role.

- [ ] **Step 2: Restore the SATADOM ESP backup**

Run with the actual backup timestamp:

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

Expected: command exits `0`.

- [ ] **Step 3: Document rollback evidence**

Add the failure mode and rollback timestamp to:

```text
docs/M70-CANARY-VALIDATION-LANE.md
docs/wiki/M70-Canary-Validation-Lane.md
```

Then run:

```bash
bash tests/shell/test_m70_canary_docs.sh
git diff --check
```

Expected: both commands pass.
