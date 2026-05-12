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
  `0df096d92166a9c7e958fa719de9d31b3dfacecc70d33829b74ba615c4e74ed4`.
- CCR2004 DHCP now advertises `next-server=172.16.99.88`.
- CCR2004 DNS resolves `boot-sun99-netboot-099088.rfc1918.host` to
  `172.16.99.88` and `boot-sun99-netboot.rfc1918.host` as a CNAME.
- AP7901 outlet 6 PDU reboot validated the generated K10
  `workstation-validation.ipxe` path through TFTP, iPXE, kernel, initramfs,
  `g/rootfs.img`, SSH on `172.16.99.156`, and OpenRC `netmount`, `sshd`, and
  `local` service checks.

The netboot hard gate is passed. The post-shutdown QCOW2 preservation gate is
also passed: the clean delta snapshot is
`eva@172.16.99.33:/home/x12again-root/20260510-192925`, linked against the
completed `20260510-173024` off-host backup.

## Replacement Service Validation

Live low-impact validation from X12AGAIN on 2026-05-10 confirms these
Hasslehoff replacements are reachable before the X12AGAIN reimage window:

| Service | Endpoint | Validation |
| --- | --- | --- |
| NetBox | `http://172.16.99.62/` | HTTP `302` to `/login/` from nginx/NetBox |
| FreeIPA / LDAP / Kerberos | `172.16.99.63` | TCP `80`, `443`, `389`, `636`, and `88` open |
| Prometheus | `http://172.16.99.64:9090/-/ready` | `Prometheus Server is Ready.` |
| VictoriaMetrics | `http://172.16.99.65:8428/health` | `OK` |
| Grafana | `http://172.16.99.66:3000/api/health` | database `ok`, version `12.4.0` |
| Kibana | `http://172.16.99.67:5601/api/status` | overall status `available` |
| Netboot publisher | `http://172.16.99.88:8080/hosts/gmktek-k10-stage5.ipxe` | iPXE host script served with base URL `172.16.99.88` |
| Container-services HAProxy | `172.16.99.89` | TCP `80`, `443`, `514`, `6514`, and `9200` reachable as applicable |
| Elasticsearch service VIP | `http://172.16.99.92:9200/` | Elasticsearch `9.3.1` cluster metadata returned |
| Rsyslog service VIP | `172.16.99.93:6514` | TCP listener open |
| Local ntfy HTTPS | `https://msg-sun99-ntfysys.rfc1918.host/` | HTTP `200` |

FreeRADIUS uses UDP `1812/1813`; a closed TCP probe on `1812` is not a
service failure.

## X12AGAIN Live Dependencies To Remove

As of the 2026-05-10 readiness pass, X12AGAIN still has the following
load-bearing or potentially load-bearing processes:

| Local duty | Process / listener | Removal condition |
| --- | --- | --- |
| Old netboot publisher fallback | `python3 -m http.server 8080 --bind 10.9.8.108` | Removed after K10 booted through `172.16.99.88` with no asset fetch from X12AGAIN |
| Legacy Path B RouterOS lab | `routeros-chr-pathb-fresh`, serial `127.0.0.1:5001`, taps `tap-ros` and `tap-ros-wan` | Removed after CCR2004/Hasslehoff paths were confirmed authoritative |
| Legacy local container-services VM | `container-services`, serial `127.0.0.1:5003`, tap `tap-container` | Stopped after `svc-container-services-safe-move-01` at `172.16.99.89` remained authoritative |
| Legacy local binpkg repository VM | `binpkg-repository`, serial `127.0.0.1:5004`, tap `tap-binpkg` | Stopped after pre-shutdown off-host preservation captured `/opt`, caches, and QCOW2 state |
| Legacy local workstation VM | `vm-workstation-nscde-x12again`, serial `127.0.0.1:4562`, SPICE `127.0.0.1:5932`, SSH forward `127.0.0.1:2232` | Stopped after Hasslehoff GPU workstation VM `1094` and copied QCOW artifacts were accepted |
| Path B bridge stack | `br-pathb`, `br-ros-wan`, `tap-ros`, `tap-container`, `tap-binpkg`, stale `tap-client`, stale `tap-es-test` | Removed after all local QEMU guests were stopped; `eno2` was detached from `br-ros-wan` and left unaddressed |

Post-removal validation on 2026-05-10 showed no `qemu-system-*` or old
`python3 -m http.server` process, no listeners on `:5001`, `:5003`, `:5004`,
`:4562`, `:2232`, `:5932`, or `10.9.8.108:8080`, no `10.9.8.0/24` bridge
address, and no stale Path B tap devices. X12AGAIN keeps `eno1` at
`172.16.99.108/24` for management reachability.

The currently mounted root is a live-ISO overlay, so `/opt` and `/srv` must be
treated as volatile until copied off-host. The preservation set is:

- `/opt`
- `/root`
- `/etc`
- `/srv`
- `/var/lib/netboot`
- `/var/cache/binpkgs`
- `/var/cache/distfiles`
- `/var/db/repos`
- `/var/log`
- `/home`
- `/usr/local`
- `/usr/src`
- selected `/tmp/docs`, `/tmp/*.md`, `/tmp/*.tar`, `/tmp/*.cfg`,
  `/tmp/*.tmp`, `/tmp/*creds*`, and `/tmp/*token*`

Use `/root/operator-private/rsync-off-host-codex.sh` for the operator-run
snapshot. The post-shutdown targeted delta captured the clean QCOW2 set below
under `eva@172.16.99.33:/home/x12again-root/20260510-192925`, using
`20260510-173024` as `--link-dest`:

- `/opt/gentoo-netboot/path-b/vms/binpkg-repository/binpkg-repository-root.qcow2`
- `/opt/gentoo-netboot/path-b/vms/container-services-profile/container-services-root.qcow2`
- `/opt/gentoo-virt-qemu/workstation-nscde/images/vm-workstation-nscde.qcow2`

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
    `scripts/backup-network-device-configs.sh --skip-collect --sync-git` until
    the Hasslehoff serial gateway execution path is promoted into automation.

## X12AGAIN Release Criteria

X12AGAIN can be shut down for bare-metal reimage only after:

- RouterOS router/switch serial consoles are reachable from Hasslehoff instead
  of X12AGAIN. This is complete as of 2026-05-10 for CCR2004, CRS354, and
  CRS309 through stable `/dev/serial/by-id` paths on the interim generic USB
  hub.
- K10 boots from `172.16.99.88` without any asset fetch from `172.16.99.108`.
- RouterOS DHCP no longer references `172.16.99.108` for K10. This is complete
  for the CCR2004 management DHCP scope as of 2026-05-10.
- `/opt`, `/root`, selected volatile state, and the clean post-shutdown QCOW2
  delta set are copied off-host to `eva@172.16.99.33`.
- No QEMU process or tap bridge on X12AGAIN is serving production traffic.
- Git has the latest encrypted network-device config backups and X12AGAIN
  offload docs committed and pushed.

## Target Installed Profile

The first installed X12AGAIN profile should be a workstation plus hypervisor
host, not another live-ISO operating state.

Required profile overlays:

- LOX Stage4 amd64 LLVM/OpenRC base
- Stage5 workstation Xorg/NsCDE policy
- AMDGPU display support; use the regular Portage `amdgpu`/Mesa stack first,
  and add AMDGPU-PRO only if a specific application requires it
- Optane Persistent Memory support: kernel config, userspace management tools,
  and scripts for namespace inspection
- hypervisor overlay for QEMU plus libvirt; Xen remains a separately gated
  subtype until the base host is stable
- NFSv3, NFSv4, NFS over TCP, NFS-RDMA, iSER, NVMe-RDMA, and multipath client
  package/kernel readiness where hardware supports it
- FreeIPA/SSSD client profile, rsyslog, observability exporters, ntfy client,
  and host E2ET conformance tooling

Hard gates before image:

- K10 E2ET has produced a conformance report from the current Path B builder
  and publisher flow.
- The disposable builder VM can rebuild and stage K10 artifacts without using
  X12AGAIN as a mutable chroot workspace.
- All live service duties currently needed from X12AGAIN are reachable on
  Hasslehoff or another durable host.
- Off-host backup and backout media are verified.
- A rollback decision point is defined before wiping local disks.

## Final De-Load Sequence

Run this only after the off-host backup completes and K10 has booted from the
Hasslehoff netboot publisher:

1. Gracefully stop the local X12AGAIN workstation VM if no console validation is
   in progress.
2. Gracefully stop the local X12AGAIN container-services VM after validating
   `172.16.99.89:80`, `172.16.99.89:443`, `172.16.99.89:6514`, and
   `172.16.99.92:9200`.
3. Gracefully stop the local X12AGAIN binpkg repository VM only after the
   package/cache preservation target is accepted.
4. Stop the local Path B RouterOS lab VM after confirming CCR2004 owns the live
   WAN, DHCP, DNS, VIP, and routing duties.
5. Stop the local `10.9.8.108:8080` Python netboot publisher.
6. Remove stale tap devices and bridges: `tap-client`, `tap-es-test`,
   `tap-ros`, `tap-container`, `tap-binpkg`, `tap-ros-wan`, `br-pathb`, and
   `br-ros-wan`.
7. Run a small second `rsync-off-host-codex.sh` snapshot or targeted delta for
   `/opt/gentoo-netboot/path-b`, `/opt/gentoo-virt-qemu`, `/opt/routeros`,
   `/srv`, and `/var/lib/netboot`.
8. Re-run the endpoint validation table above.
9. Confirm no route, DNS record, DHCP option, HAProxy backend, or NetBox record
   still references `172.16.99.108` or `10.9.8.108` for active service duties.
