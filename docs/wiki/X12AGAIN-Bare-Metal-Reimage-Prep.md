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

- Copy `/var/lib/netboot/path-b/` from X12AGAIN to VM `1088`.
- Validate HTTP `:8080` and TFTP `k10-ipxe.efi` from `172.16.99.88`.
- Apply CCR2004 DHCP `next-server=172.16.99.88` only after service validation.
- Reboot K10 and prove PXE -> iPXE -> rootfs without `172.16.99.108`.
- Move `/srv/build-cache`, `/srv/vm-images`, binpkg, and distfiles caches to
  durable storage before X12AGAIN shutdown.
