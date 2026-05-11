# X12AGAIN Bare-Metal Reimage Prep

Do not reimage X12AGAIN until netboot and build-cache duties are offloaded.

The netboot offload target is:

```text
boot-sun99-netboot-099088.rfc1918.host
172.16.99.88
Hasslehoff VMID 1088
profile: vm-netboot-publisher
```

Cutover gates:

- VM `1088` is running from the populated Stage4 service image with OVMF and
  static OpenRC networking at `172.16.99.88/24`.
- `/var/lib/netboot/path-b/` and `/opt/gentoo-netboot/path-b/artifacts/` have
  been copied from X12AGAIN.
- HTTP `:8080` and TFTP `k10-ipxe.efi` validate from `172.16.99.88`.
- CCR2004 DHCP now advertises `next-server=172.16.99.88`.
- CCR2004 DNS resolves `boot-sun99-netboot-099088.rfc1918.host` and the
  `boot-sun99-netboot.rfc1918.host` alias.
- RouterOS router/switch serial consoles are reachable from Hasslehoff instead
  of X12AGAIN. This is complete as of 2026-05-10 for CCR2004, CRS354, and
  CRS309 through stable `/dev/serial/by-id` paths on the interim generic USB
  hub.
- Reboot K10 and prove PXE -> iPXE -> rootfs without `172.16.99.108`.
- Move `/srv/build-cache`, `/srv/vm-images`, binpkg, and distfiles caches to
  durable storage before X12AGAIN shutdown.
