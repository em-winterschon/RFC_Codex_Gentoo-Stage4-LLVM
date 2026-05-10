# X12AGAIN Bare-Metal Reimage Prep

X12AGAIN must not be reimaged until its live boot, build-cache, and artifact
publisher duties have been moved to durable hosts.

## Current Hard Gate

The first hard gate is netboot. Desired state now moves K10 boot service to:

```text
boot-sun99-netboot-099088.rfc1918.host
172.16.99.88
Hasslehoff VMID 1088
profile: vm-netboot-publisher
publish root: /var/lib/netboot/path-b
HTTP: 8080
TFTP: 69
```

Live status as of 2026-05-10:

- Hasslehoff VM `1088` is running from the populated Stage4 service image with
  OVMF enabled and static OpenRC networking at `172.16.99.88/24`.
- `/var/lib/netboot/path-b/` and the absolute symlink target
  `/opt/gentoo-netboot/path-b/artifacts/` are copied from X12AGAIN.
- HTTP `:8080` validates for K10 host scripts, `g/vmlinuz`, and `g/rootfs.img`.
- TFTP validates for `k10-ipxe.efi` with SHA256
  `a3b9d117b69bb9f6387093011f7ace0e5f5ea2c76f679707f0229da634cd3e75`.
- CCR2004 DHCP now advertises `next-server=172.16.99.88`.
- CCR2004 DNS resolves `boot-sun99-netboot-099088.rfc1918.host` to
  `172.16.99.88` and `boot-sun99-netboot.rfc1918.host` as a CNAME.

The remaining hard gate is a K10 reboot validation through the new publisher.

## Cutover Sequence

1. Provision Hasslehoff VM `1088` from the Stage4 service-VM path with static
   address `172.16.99.88/24` and gateway `172.16.99.1`.
2. Apply the `vm-netboot-publisher` package/profile overlay.
3. Rsync X12AGAIN `/var/lib/netboot/path-b/` to VM `1088` preserving symlinks,
   modes, and timestamps.
   Also copy `/opt/gentoo-netboot/path-b/artifacts/` because the live publish
   tree uses absolute symlinks into that path.
4. Generate checksums on X12AGAIN and VM `1088` for:
   `k10-ipxe.efi`, `bootstrap.ipxe`, `hosts/gmktek-k10-stage5.ipxe`,
   `g/vmlinuz`, `g/initramfs-gz.img`, and `g/rootfs.img`.
5. Validate HTTP from a SUN99 client:
   `http://172.16.99.88:8080/hosts/gmktek-k10-stage5.ipxe`.
6. Validate TFTP from a SUN99 client:
   `k10-ipxe.efi` from `172.16.99.88`.
7. Render CCR2004 desired state and confirm DHCP `next-server=172.16.99.88`.
8. Capture pre-change RouterOS config backup with
   `scripts/backup-network-device-configs.sh`.
9. Apply the scoped RouterOS DHCP change through the existing live gate.
10. Reboot K10 and validate PXE -> iPXE -> kernel/initramfs/rootfs through VM
    `1088`.
11. Capture post-change RouterOS config backup with
    `scripts/backup-network-device-configs.sh --skip-collect --sync-git` if
    serial collection is unavailable in the exec environment.

## X12AGAIN Release Criteria

X12AGAIN can be shut down for bare-metal reimage only after:

- K10 boots from `172.16.99.88` without any asset fetch from `172.16.99.108`.
- RouterOS DHCP no longer references `172.16.99.108` for K10. This is complete
  for the CCR2004 management DHCP scope as of 2026-05-10.
- `/srv/build-cache`, `/srv/vm-images`, and any binpkg/distfiles caches are
  copied to Hasslehoff, Nexus, or NFS-backed storage.
- No QEMU process or tap bridge on X12AGAIN is serving production traffic.
- Git has the latest encrypted network-device config backups and X12AGAIN
  offload docs committed and pushed.
