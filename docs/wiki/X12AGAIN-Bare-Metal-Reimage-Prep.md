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
- HTTP `:8080` and TFTP `k10-ipxe.efi` validate from `172.16.99.88`; the
  embedded iPXE binary SHA256 is
  `0df096d92166a9c7e958fa719de9d31b3dfacecc70d33829b74ba615c4e74ed4`.
- CCR2004 DHCP now advertises `next-server=172.16.99.88`.
- CCR2004 DNS resolves `boot-sun99-netboot-099088.rfc1918.host` and the
  `boot-sun99-netboot.rfc1918.host` alias.
- RouterOS router/switch serial consoles are reachable from Hasslehoff instead
  of X12AGAIN. This is complete as of 2026-05-10 for CCR2004, CRS354, and
  CRS309 through stable `/dev/serial/by-id` paths on the interim generic USB
  hub.
- K10 AP7901 outlet 6 reboot validated generated PXE -> iPXE -> kernel ->
  initramfs -> `rootfs.img` from `172.16.99.88`, with SSH reachable on
  `172.16.99.156` and OpenRC `netmount`, `sshd`, and `local` started.
- The completed full backup is `eva@172.16.99.33:/home/x12again-root/20260510-173024`.
- The clean post-shutdown QCOW2 delta is
  `eva@172.16.99.33:/home/x12again-root/20260510-192925`, linked against the
  full backup and covering the binpkg repository, container-services, and
  workstation QCOW2 images.

Replacement services validated from X12AGAIN on 2026-05-10:

- NetBox `172.16.99.62` returns the expected login redirect.
- FreeIPA `172.16.99.63` has HTTP, HTTPS, LDAP, LDAPS, and Kerberos TCP ports
  reachable. FreeRADIUS must be tested over UDP, not a TCP `1812` probe.
- Prometheus `172.16.99.64:9090`, VictoriaMetrics `172.16.99.65:8428`,
  Grafana `172.16.99.66:3000`, Kibana `172.16.99.67:5601`, netboot
  `172.16.99.88:8080`, container-services `172.16.99.89`, Elasticsearch VIP
  `172.16.99.92:9200`, rsyslog VIP `172.16.99.93:6514`, and local ntfy HTTPS
  all answer basic readiness probes.

X12AGAIN live dependencies removed after backup and K10 validation:

- Stopped old `10.9.8.108:8080` Python netboot publisher.
- Stopped legacy local QEMU guests: `routeros-chr-pathb-fresh`,
  `container-services`, `binpkg-repository`, and `vm-workstation-nscde`.
- Removed old Path B networking: `br-pathb`, `br-ros-wan`, `tap-ros`,
  `tap-container`, `tap-binpkg`, `tap-ros-wan`, stale `tap-client`, and stale
  `tap-es-test`; `eno2` was detached from `br-ros-wan` and left unaddressed.
- Verified no active `qemu-system-*` or old `python3 -m http.server` process,
  no `10.9.8.0/24` bridge address, and no listeners on the old local serial,
  SPICE, SSH-forward, or HTTP ports.
- Completed a post-shutdown link-dest rsync against the verified
  `20260510-173024` off-host snapshot so QCOW2 images are clean rather than
  only crash-consistent.

Target installed profile:

- LOX Stage4 amd64 LLVM/OpenRC base.
- Stage5 workstation Xorg/NsCDE policy.
- AMDGPU display support first through the regular Portage Mesa/amdgpu stack;
  AMDGPU-PRO is added only if a specific application requires it.
- Optane Persistent Memory kernel support, userspace tools, and namespace
  inspection scripts.
- QEMU plus libvirt hypervisor overlay; Xen remains separately gated until the
  base host is stable.
- NFSv3, NFSv4, NFS over TCP, NFS-RDMA, iSER, NVMe-RDMA, and multipath client
  readiness where hardware supports it.
- FreeIPA/SSSD, rsyslog, observability exporters, ntfy client, and host E2ET
  conformance tooling.

Hard gates before imaging:

- K10 E2ET has produced a conformance report from the current Path B builder
  and publisher flow.
- The disposable builder VM can rebuild and stage K10 artifacts without using
  X12AGAIN as a mutable chroot workspace.
- All live service duties currently needed from X12AGAIN are reachable on
  Hasslehoff or another durable host.
- Off-host backup and backout media are verified.
- A rollback decision point is defined before wiping local disks.
