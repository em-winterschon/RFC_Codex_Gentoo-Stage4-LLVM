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

Replacement services validated from X12AGAIN on 2026-05-10:

- NetBox `172.16.99.62` returns the expected login redirect.
- FreeIPA `172.16.99.63` has HTTP, HTTPS, LDAP, LDAPS, and Kerberos TCP ports
  reachable. FreeRADIUS must be tested over UDP, not a TCP `1812` probe.
- Prometheus `172.16.99.64:9090`, VictoriaMetrics `172.16.99.65:8428`,
  Grafana `172.16.99.66:3000`, Kibana `172.16.99.67:5601`, netboot
  `172.16.99.88:8080`, container-services `172.16.99.89`, Elasticsearch VIP
  `172.16.99.92:9200`, rsyslog VIP `172.16.99.93:6514`, and local ntfy HTTPS
  all answer basic readiness probes.

Remaining X12AGAIN live dependencies to remove after backup and K10 validation:

- Stop old `10.9.8.108:8080` Python netboot publisher.
- Stop legacy local QEMU guests: `routeros-chr-pathb-fresh`,
  `container-services`, `binpkg-repository`, and `vm-workstation-nscde`.
- Remove old Path B networking: `br-pathb`, `br-ros-wan`, `tap-ros`,
  `tap-container`, `tap-binpkg`, `tap-ros-wan`, stale `tap-client`, and stale
  `tap-es-test`.
- Run a second small post-shutdown rsync so QCOW2 images are clean rather than
  only crash-consistent.
- Re-run service endpoint checks and confirm no active DHCP/DNS/VIP/route
  reference still depends on `172.16.99.108` or `10.9.8.108`.
