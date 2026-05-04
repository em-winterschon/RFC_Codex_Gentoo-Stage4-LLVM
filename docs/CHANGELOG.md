# Changelog

This changelog tracks operator-visible changes to the Stage4/Stage5
infrastructure work. It is intentionally higher level than `git log`.

## 2026-05-03

### Added

- Added sanitized NetBox intake files derived from
  `/tmp/rfc99-sun99-host-networking.md`:
  - `inventory-intake/sites/rfc99.yml`
  - `inventory-intake/sites/sun99.yml`
  - `inventory-intake/sites/yks99.yml`
  - `inventory-intake/sites/fmt2.yml`
- Added a 2026-05-03 SITREP covering mixed-environment intake state, live
  management reachability, and CRS309 execution gates.
- Added the NetBox-driven provisioning and container-services action plan:
  `docs/superpowers/plans/2026-05-03-netbox-driven-provisioning-and-container-services.md`.
- Added `scripts/export-netbox-provisioning-inventory.py` and
  `playbooks/netbox-provisioning-inventory-export.yml` to generate Ansible
  inventory, IPAM records, and service validation targets from NetBox.
- Added `scripts/proxmox-create-stage4-service-vm.sh` for dry-run-first
  Proxmox service VM creation from Stage4/Stage5 QCOW images.
- Added the container-services safe-move change plan, SLO validator, SLO
  manifest, and runtime migration helper:
  - `docs/CHANGE-CONTROL-CONTAINER-SERVICES-SAFE-MOVE.md`
  - `scripts/slo_service_validator.py`
  - `scripts/migrate-container-services-runtime.sh`
  - `service-slo-definitions/container-services-safe-move.yml`
- Added Hetzner Cloud DNS token import and validation scaffolding:
  - `scripts/import-hetzner-dns-vault.sh`
  - `scripts/plan-hetzner-dns-from-netbox.py`
  - `scripts/report-hetzner-dns-inventory.py`
  - `group_vars/all/dns_hetzner_cloud.yml`
  - `playbooks/hetzner-dns-api-validate.yml`
  - `playbooks/hetzner-dns-plan-from-netbox.yml`
  - `playbooks/hetzner-dns-inventory-report.yml`
  - `docs/HETZNER-DNS-AUTOMATION.md`

### Changed

- Updated NetBox IPAM/DCIM and CRS309 plans now that the host-networking source
  file is present and archived outside the repo.
- Marked `PNR-011` complete for local structured intake conversion while keeping
  live NetBox writes gated by management reachability.
- Added `hetzner.hcloud` to Ansible collection requirements for future Hetzner
  Cloud DNS CRUD automation.
- Fixed NetBox intake device-type lookup to use manufacturer plus model during
  live applies, avoiding collisions with existing Device-Type-Library imports.
- Extended the Proxmox service VM creator with explicit OVMF/EFI disk support
  after the Stage4 ZFS base image proved unsuitable for SeaBIOS boot.
- Registered `svc_container_services_safe_move_01` in local NetBox intake as a
  planned Hasslehoff staging VM at `172.16.99.89`.

### Operational Notes

- Raw operator input was archived under
  `/root/operator-private/network-intake/2026-05-03/`.
- Local intake validation now covers `5` files, `5` sites, `25` prefixes, `11`
  devices, `5` clusters, and `4` service VIPs.
- Live NetBox writes are still blocked while `172.16.99.62` is unreachable from
  this host.
- Hetzner Cloud DNS API token validation passed for the `rfc1918`, `vernetzen`,
  and `yukon` token groups without printing token values.
- Multisite NetBox intake applied live after snapshot `nb-pre-ms-20260503`; the
  first pass created `21` objects and updated `78`, and the idempotence pass
  produced `0` creates and `0` updates.
- NetBox post-apply snapshot `nb-post-ms-20260503` was created.
- Hetzner DNS dry-run plan from NetBox generated `7` RRsets and skipped `5`
  IPs missing DNS names; no DNS writes were performed.
- Added a read-only Hetzner DNS provider inventory report which validates zone
  readability, counts records by zone/type, and emits deduplicated hostname/IP
  connectivity targets without serializing API tokens.
- Live provider inventory validation read `8/8` configured zones, counted `221`
  records across DNS types, and generated `99` address-bearing connectivity
  hosts for follow-on healthchecks and nmap scans.
- Live NetBox provisioning export currently yields `7` standalone IP bootstrap
  hosts from `12` IP records when run without an ownership tag filter; the
  default `codex-managed` filter correctly returns zero until tags are applied.
- NetBox snapshot `nb-pre-safe-move-20260503` was created before adding the
  container-services staging IPAM entry.
- `svc-container-services-safe-move-01` was created as Proxmox VM `1089` on
  Hasslehoff, using the bootable populated Stage4 image, OVMF, `8` vCPU,
  `32 GiB` RAM, and an `80 GiB` disk.
- The first create attempt exposed two useful constraints: Hasslehoff allows a
  maximum of `8` vCPU per VM, and the ZFS Stage4 base QCOW has an empty EFI
  partition, so the populated ext4 Stage4 image is required for this staging
  path until the generic base image is rebuilt.
- Source pre-move SLO validation passed `4/4` checks for HAProxy, nginx,
  rsyslog TCP, and the Elasticsearch test VIP. Target boot SLO validation
  passed `1/1` for SSH on `172.16.99.89`.
- The staging root filesystem was expanded from the populated image's `23.5 GiB`
  partition to the full `79 GiB` guest root.
- Container runtime bootstrap completed on the staging VM with buildpkg
  enabled; Podman `5.7.1`, Buildah `1.41.0`, and Skopeo `1.21.0` are
  installed, and iptables is selected through `xtables-nft-multi`.
- Applied the container-services runtime migration helper to
  `svc-container-services-safe-move-01`; rsyslog, nginx, and HAProxy are
  running under OpenRC/Podman with netavark networks.
- Post-move core SLO validation passed `8/8` checks while keeping the source VM
  online. The separate Elasticsearch dependency SLO currently fails with
  HAProxy `503` because the Hasslehoff management subnet cannot reach the
  existing `10.9.8.91` / `10.9.8.92` Elasticsearch path.
- Added vaulted bootstrap credentials and planned inventory metadata for the
  rackable MikroTik `CCR2004-16G-2S+PC` replacement-router target. It is staged
  as `gw_rfc99_mkccr2004_16g` without a management IP until serial discovery
  confirms baseline state and cabling.
- Completed first serial discovery for `gw_rfc99_mkccr2004_16g` on
  `/dev/ttyUSB2`: RouterOS `7.19.6`, arm64, `4` cores, `4096 MiB` RAM,
  observed board `CCR2004-16G-2S+`, default IP `192.168.88.1/24` on `ether15`,
  and physical ports `ether1` through `ether16` plus `sfp-sfpplus1` and
  `sfp-sfpplus2`.
- Added a render-only physical RouterOS gateway role for the CCR2004:
  `routeros_rfc99_gateway`. It translates the CRS309 replacement intent to the
  CCR2004 port map, renames `ether1` through `ether16` to `ge1` through `ge16`,
  assigns `sfp-sfpplus1` as WAN, assigns `sfp-sfpplus2` as the LAN trunk,
  enables SSH/HTTPS/API-SSL only, and renders a JSON manifest for review.
- Added `docs/ROUTEROS-RFC99-GATEWAY.md` and
  `docs/workflows/stage4-routeros-rfc99-gateway-deployment.json` for the
  CCR2004 render/review workflow.

### Changed

- Normalized the CRS309 WIP's overlapping `172.16.228.0/22` gateway entries in
  the CCR2004 render by keeping `172.16.228.1/22` and omitting
  `172.16.229.1/22` plus `172.16.230.1/22`.

### Operational Notes

- The CCR2004 role is intentionally render-only. No live RouterOS import has
  been implemented or executed yet; serial console and pre-change export remain
  mandatory gates before any live mutation.

## 2026-05-02

### Added

- Added the `netbox_essentials` role and wired it into the `vm-netbox-service`
  profile so `pynetbox`, `netbox-agent`, `netbox-sync`, `netbox-tools`,
  `devicetype-library`, and `Device-Type-Library-Import` are installed before
  any NetBox write workflows.
- Added `scripts/netbox_seed_local_network.py` for conservative NetBox seeding
  from the repo-safe local network fabric inventory.
- Added `scripts/proxmox-create-freeipa-rocky-vm.sh` and
  `scripts/bootstrap-freeipa-rocky.sh` to build a dedicated Rocky 9 FreeIPA
  controller VM when native FreeIPA server packaging is unavailable in the
  Gentoo image.
- Added `scripts/configure-freeradius-freeipa.sh` to configure the FreeRADIUS
  LDAP bridge against FreeIPA, seed central `codex-admin` SSH identity, and run
  a redacted RADIUS authentication validation.
- Added operational validation playbooks for the new NetBox and identity
  control-plane state:
  - `playbooks/identity-controller-validate.yml`
  - `playbooks/netbox-local-fabric-seed.yml`
- Added the infrastructure inventory intake checklist for the next
  cluster/datacenter import pass.
- Added structured NetBox inventory intake definitions and dry-run/apply
  tooling:
  - `inventory-intake/sites/local-rfc1918-lab.yml`
  - `scripts/validate_netbox_inventory_intake.py`
  - `scripts/netbox_apply_inventory_intake.py`
  - `playbooks/netbox-inventory-intake-validate.yml`
  - `playbooks/netbox-inventory-intake-apply.yml`
- Added EOD and next-step planning for NetBox IPAM/DCIM completion and the
  CRS309 RouterOS replacement path:
  - `docs/NETBOX-IPAM-DCIM-COMPLETION-PLAN.md`
  - `docs/CRS309-ROUTEROS-REPLACEMENT-PLAN.md`
  - `docs/EOD-STATUS-2026-05-02.md`
  - `docs/superpowers/plans/2026-05-02-netbox-dcim-ipam-and-crs309-router-replacement.md`

### Changed

- Added `svc_identity_ipa01` to the local-network inventory as Proxmox VM
  `1063` at `172.16.99.63`, with FreeIPA realm `RFC1918.HOST` and domain
  `rfc1918.host`.
- Updated the Hasslehoff inventory and network fabric model to treat
  `svc-netbox-stage4` as the active NetBox service and to track the identity
  controller bootstrap separately.
- Updated `playbooks/netbox-api-validate.yml` to support token-file
  authentication for NetBox instances that reject anonymous `/api/` access.

### Operational Notes

- NetBox essentials are intentionally isolated under `/opt/netbox-essentials`
  instead of being loaded as in-process NetBox Django plugins.
- The first device-type import set covers APC, Arista, Cisco, CyberPower,
  Eaton, Juniper, MikroTik, and Opengear.
- The local network fabric seed created `42` baseline NetBox objects for the
  site, VLANs, prefixes, devices, and management IPs.
- NetBox recovery snapshots now include `codex-netbox-after-essential-import`
  and `codex-netbox-after-fabric-seed`.
- FreeIPA bootstrap secrets are stored outside the repo under
  `/root/operator-private/identity/` and copied to root-only state on the VM.
- `svc_identity_ipa01` now has FreeIPA, SSSD, and FreeRADIUS active, with UDP
  listeners on `1812` and `1813`; Proxmox snapshot
  `codex-freeipa-radius-live` captures the validated state.
- The identity controller validation playbook passed against live VM `1063`
  with `6` active services, `6` TCP listeners, and `4` UDP listeners.
- The NetBox fabric seed playbook completed a no-change dry run against live
  VM `1062` using a private token-file path.
- Structured inventory intake was applied to NetBox VM `1062`; the first live
  pass created the missing Proxmox/service-cluster records plus rsyslog and
  Elasticsearch VIP IP records, and the second pass was idempotent with `0`
  creates and `0` updates.
- NetBox recovery snapshot `codex-netbox-after-intake-apply` was created after
  the structured intake apply. Proxmox reported the QEMU guest agent was not
  running, but storage snapshots for the root disk and EFI disk completed.
- Reviewed `/tmp/crs309-router-mode-idc.wip.rsc`; it is a destructive
  replacement-router import and should not be executed unattended.
- `/tmp/rfc99-sun99-host-networking.md` was not present at review time, so full
  RFC99/SUN99/FMT2 NetBox IPAM/DCIM import remains blocked on the corrected
  source file path or regenerated content.

## 2026-05-01

### Added

- Added the `vm-netbox-service` Stage5 profile and `netbox_server` role scaffold
  for native-source NetBox `v4.5.9` deployment on Gentoo-managed PostgreSQL,
  Redis, nginx, pip, and virtualenv.

### Changed

- Retired the Hasslehoff FreeBSD jail path for NetBox and moved the active
  inventory target to Stage4 Gentoo VM `svc-netbox-stage4` at `172.16.99.62`.

### Operational Notes

- The replacement NetBox VM was imported from the populated Stage4 QCOW image,
  then resized from a `24G` root disk to an `80G` root filesystem before
  continuing Portage work.
- `svc-netbox-stage4` now serves NetBox `v4.5.9` at `http://172.16.99.62/`;
  `/api/` returns the expected unauthenticated API response through nginx.
- A Proxmox recovery snapshot named `codex-netbox-stage4-live` was created for
  VM `1062` after PostgreSQL, Redis, gunicorn, RQ worker, nginx, and SSH were
  validated under OpenRC.

## 2026-04-30

### Added

- Added `container-service-base-image.yml` as the Stage5 service-layer reference
  for the published Gentoo stage3 LLVM/Clang OpenRC base image.
- Added preflight merge support for `container_base_image` and
  `container_app_build_defaults`.
- Added container-host rendering of `/etc/container-services/base-image.yml` so
  provisioned container hosts carry the base-image provenance and app build
  defaults used for service-layer work.
- Added `container-image-definitions/service-layers.yml` to track service-image
  build mode, package atoms, runtime roles, and GHCR naming on top of the
  published base image.
- Added package lists and a Path B launcher for package-backed service-layer
  image builds:
  - `gentoo-stage5-nginx`
  - `gentoo-stage5-haproxy`
  - `gentoo-stage5-rsyslog-collector`

### Changed

- Published `ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc` with
  immutable `git-e5bf45f` and promoted `latest` tags.
- Recorded the published base-image digest in the service base-image profile,
  service-layer manifest, and rendered container-host provenance template.
- Wired `vm-container-services` example inventory to load the service-base
  image profile before service-specific container profiles.
- Classified `nginx`, `haproxy`, and `rsyslog_collector` as package-backed
  service-image candidates, with `ntfy` remaining upstream-image mode until an
  overlay ebuild exists.
- Standardized service-layer binpkg repo IDs under
  `stage3-llvm_clang_openrc__stage5-service_container-<service>__amd64__x86_64_v2_generic`.
- Added a service-scoped GCC/binutils-bfd fallback for HAProxy service-layer
  builds so the default LLVM/Clang container policy does not leak into an atom
  that currently fails with `ld.lld` and an incompatible `libunwind`.

### Fixed

- Fixed ZFS child-dataset mount ordering during provisioning so target writes
  under `/usr/local`, `/var/lib`, and `/var/log` land in the mounted child
  datasets instead of being hidden on first boot.
- Preserved the provisioning hostid into the target root-on-ZFS install so the
  installed initramfs does not require a forced import of the freshly created
  root pool.
- Fixed container-service nftables generation for Podman published ports that
  include a bind address, such as `10.9.8.92:9200:9200/tcp`.
- Fixed nftables Podman forward matching by using `podman*` interface
  wildcards instead of the iptables-style `podman+` pattern.

### Validated

- Built and smoke-tested `localhost/gentoo-stage5-nginx:latest` with
  `www-servers/nginx-1.29.5` and `curl` present.
- Synced the nginx service-layer binpkg repository to `10.9.8.90` with package
  index files and nginx-related gpkg artifacts.
- Published both base-image GHCR tags with digest
  `sha256:4c0cc158b9ab55f7b126dcd80deb8327959a0fd8cd132af7fa09a438df4e85b6`.
- Built and smoke-tested `localhost/gentoo-stage5-haproxy:latest` with
  `net-proxy/haproxy-3.3.5`; the smoke test reports `CC = gcc`, OpenSSL, zlib,
  network namespace, transparent proxy, and PCRE2 support.
- Synced the HAProxy service-layer binpkg repository to `10.9.8.90` with
  package index files and HAProxy-related gpkg artifacts.
- Published `gentoo-stage5-nginx` to GHCR as `git-d5104ae` and `latest`, both
  resolving to digest
  `sha256:8604b39531e508348a3ac3094621b3aef51ca8927721f17087742b888e6e9c90`.
- Published `gentoo-stage5-haproxy` to GHCR as `git-d5104ae` and `latest`, both
  resolving to digest
  `sha256:322699f05e1109f63fff3796ce7dbbddb7200c7933c2eb7ae7aaaa6e88bc8f37`.
- Built and smoke-tested `localhost/gentoo-stage5-rsyslog-collector:latest`
  with `app-admin/rsyslog-8.2602.0` and `USE=elasticsearch`; the smoke test
  confirms `omelasticsearch.so`, `imudp`, `imtcp`, and `systemd support: No`.
- Built the rsyslog collector in two phases so `libestr` and `libfastjson`
  are installed before the rsyslog pkg-config/configure phase.
- Synced the rsyslog collector service-layer binpkg repository to `10.9.8.90`
  with package index files and rsyslog-related gpkg artifacts.
- Published `gentoo-stage5-rsyslog-collector` to GHCR as `git-396998a` and
  `latest`, both resolving to digest
  `sha256:2acfd8f06d7aa3a9524a95bade090793543c228bd62b6bf38e76302324195287`.
- Updated the `vm-container-services` and `container-rsyslog-collector`
  profiles to consume the published GHCR Stage5 images instead of upstream
  nginx, HAProxy, and rsyslog images.
- Added explicit Gentoo service commands, tmpfs runtime mounts, and required
  `NET_BIND_SERVICE` capability handling for the package-backed container
  images under the OpenRC Podman wrapper.
- Updated HAProxy deployment wiring to mount generated configuration at the
  Gentoo package path, `/etc/haproxy/haproxy.cfg`.
- Added a writable rsyslog collector spool volume while keeping the container
  root filesystem read-only.
- Added the rsyslog collector profile to the `vm-container-services` example
  inventory so the centralized logging container is included in live
  container-host deployments.
- Fixed Gentoo nginx runtime config for package-backed containers by using the
  packaged `/etc/nginx/mime.types.nginx`, routing early nginx errors to
  `/dev/stderr`, and increasing `types_hash_max_size` to avoid MIME hash
  warnings.
- Updated HAProxy rendering so explicit service-type frontends, such as
  `syslog-tcp`, are additive instead of disabling the default HTTP reverse
  proxy frontend for nginx and ntfy.
- Hardened the HAProxy container config to drop privileges to the packaged
  `haproxy` user and added narrowly scoped `SETGID`/`SETUID` capabilities to
  the HAProxy app profile so the drop works with `--cap-drop all`.
- Added shell coverage that renders the HAProxy template with both explicit
  service types and runtime apps, catching regressions where catalog-driven
  services suppress the default HTTP reverse proxy.
- Live-validated the package-backed service layer on the Path B
  `container-services` VM at `10.9.8.89`: generated OpenRC Podman wrappers,
  config validation, and runtime startup all passed for rsyslog collector,
  nginx, ntfy, and HAProxy.
- Confirmed direct nginx ingress on `127.0.0.1:8080`, HAProxy-to-nginx ingress
  on `127.0.0.1:80`, and HAProxy-to-ntfy ingress with `Host: ntfy.local`, each
  returning HTTP `200`.
- Confirmed rsyslog collector UDP and TCP ingress on port `514`; forwarding to
  Elasticsearch remains blocked only by the expected placeholder DNS dependency
  for `elastic-vip.example.internal`.
- Redeployed the Path B `container-services` VM from installed disk after the
  site outage and validated host-side ingress to `10.9.8.89:8080`,
  `10.9.8.89:80`, `10.9.8.89:514/tcp`, and the HAProxy Elasticsearch test VIP
  at `10.9.8.92:9200`.
- Loaded locally exported service image archives into the VM as a deterministic
  fallback when post-outage external image pulls were too slow; `ntfy` remains
  the upstream Docker Hub image path until a package-backed service image is
  added.
- Added the 2026-04-30 EOD status and Proxmox/NetBox/RouterOS tomorrow action
  plan, including a draft IPAM model for Path B, service VIPs, container
  segments, OOB, builder-farm, and ZeroTier follow-up.
- Corrected the live container-services status to show `ntfy` as blocked by the
  stalled upstream pull after redeploy, while `nginx`, `haproxy`, and
  `rsyslog-collector` remain validated.
- Added first-class Podman `pull_policy` support to generated service wrappers.
  Runtime profiles now default package-backed images to `missing`, and the live
  Path B inventory disables `ntfy` with `pull_policy: never` until a controlled
  image source exists.
- Added a read-only `netbox-pathb-lab-ipam-plan.yml` profile that carries the
  draft Path B, container, OOB, builder-farm, ZeroTier, Proxmox, NetBox, and
  CCR2004 objects for tomorrow's NetBox import planning.

## 2026-04-29

### Added

- Added a repo-managed RouterOS CHR Path B launcher with LAN tap on `br-pathb`
  and WAN tap on a dedicated `br-ros-wan` bridge backed by `eno2`.
- Added repeatable Path B container-base build launch helpers for binhost-backed
  reruns under the restart watchdog.
- Added an explicit compiler/runtime bootstrap package phase for the Gentoo
  rootfs container builder.
- Added a seeded Clang runtime bootstrap mode for container rootfs builds so
  early sysroot ABI checks do not require compiling full LLVM first.
- Added stage3-backed rootfs build support to the container builder, including
  latest-stage3 resolution, checksum verification, resettable rootfs extraction,
  and non-`--emptytree` package layering.
- Added the active `gentoo-stage3-llvm-clang-openrc` container definition for
  the standard Gentoo llvm-clang OpenRC stage3 path.

### Changed

- Rebuilt RouterOS CHR from a fresh disk and moved active builder egress from
  host NAT to RouterOS NAT through `192.168.1.222/24 -> 192.168.1.254`.
- Extended the RouterOS Path B Ansible role to render optional WAN static
  addressing, LAN-to-WAN masquerade, DHCP DNS split, and baseline WAN input
  filtering.
- Updated the container builder to use the Stage4/Stage5 binpkg repository
  during reruns and preserve sync auth from inside the installed Gentoo chroot.
- Split container rootfs builds into a small runtime bootstrap phase followed
  by the main image graph, so clang sysroot ABI failures are detected before
  the long dependency tree reaches CMake packages.
- Switched the Path B container-base launcher from `--bootstrap-package-list`
  to `--bootstrap-runtime-seed auto`; the package bootstrap path remains as a
  diagnostic fallback but is no longer the default.
- Switched the active Path B container-base launcher away from the hardened
  source-first Stage4 graph and onto the official Gentoo
  `amd64-llvm-openrc` stage3 plus small Stage5 service-container package
  layering.
- Deferred `rsyslog` out of the first base image because its same-transaction
  `--root` build could not see `libestr` through pkg-config; it remains a
  service/logging layer requirement.

### Fixed

- Fixed the repeated `dev-libs/json-c` CMake ABI failure path by seeding
  `libunwind`, `libc++`, and `libc++abi` into the target rootfs before the main
  graph, then verifying normal clang/libunwind C and C++ linking against the
  target rootfs.
- Avoided a bad bootstrap retry loop where the runtime-package bootstrap pulled
  in `llvm-core/llvm-21.1.8` and failed linking `libLLVM.so.21.1` from non-PIC
  static archives before the main graph could use available binpkgs.
- Fixed the generated local container profile repository lookup by exposing the
  config-root profile overlay through a host-side `/var/db/repos` symlink while
  the builder is active.
- Fixed stage3-backed binpkg use by disabling inherited stage3 binhost configs
  inside the target config-root and writing the Stage5 binhost with
  `verify-signature = false`.

### Validated

- Built and smoke-tested `localhost/gentoo-stage3-llvm-clang-openrc:latest`.
- Produced `/var/lib/container-services-ephemeral/images/gentoo-stage3-llvm-clang-openrc.tar.zst`
  on the container-services builder VM.

## 2026-04-28

### Added

- Added a Path B `vm-binpkg-repository` workflow for a durable custom Portage
  binary package repository.
- Added `qemu-launch-binpkg-repository-vm.sh` for installer and installed-disk
  launch paths.
- Added a Stage4/Stage5-specific binpkg repo ID:
  - `stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`
- Added `sync-binpkgs-to-repo.sh` for explicit PKGDIR publication.
- Added `watch-sync-binpkgs-to-repo.sh` for active or externally launched
  builders, including SSH-remote PKGDIR staging.
- Added `watch-container-base-build.sh` so detached container-image builds can
  sync binpkgs and relaunch a bounded number of times after failure.
- Added Jenkins controller and `distcc` builder-farm scaffolding.
- Added first-node builder-farm bring-up workflow.
- Added FreeIPA, SSSD, and FreeRADIUS scaffolding for RBAC/AAA.
- Added observability, telemetry, power, SNMP, IPMI, and Redfish scaffolding.

### Changed

- Moved the container base-image path toward a merged-usr Stage4 variant while
  keeping split-usr viable for host and VM profiles.
- Kept the repo-wide OpenRC and without-systemd posture, with scoped exceptions
  only where required by selected packages.
- Updated container-services Portage settings to build binpkgs, use binpkgs,
  pull from the new repository, and preserve autounmask continuity.
- Updated boot handling so ZFSBootMenu can carry an embedded commandline when
  NVRAM boot entries are unavailable.
- Updated the binpkg repository role so nginx includes `conf.d`, has its log
  directory, and serves a dataset-backed repository path.
- Updated rsyslog templating to use valid property expansion.
- Hardened the rootfs builder so inherited host `distcc` and `ccache`
  `FEATURES` are explicitly disabled for isolated container-image builds.

### Fixed

- Fixed binpkg repository VM installed-disk boot by adding Path B `uefi-disk`
  launch support and using valid OVMF firmware images.
- Fixed hidden repository/helper content caused by ZFS child datasets mounted
  over files created during target installation.
- Fixed invalid remote-to-remote package sync by staging remote PKGDIR content
  locally before publishing.
- Fixed `sync-binpkgs-to-repo.sh` executable mode so helper chaining works.
- Fixed watch-mode process tracking by adding `--watch-pid`.
- Fixed the `coreutils-9.10-r1` image overlay by staging the referenced patch
  files and preventing the split-usr install path from re-splitting merged-usr
  image roots.

### Active Build State

- The `coreutils` blocker was validated in isolation and its binpkg was
  published to the Stage4/Stage5 binpkg repository.
- The base-container build was restarted against the binhost and had advanced
  past early binary merges at last observation.
- A local binpkg watch-sync loop and a remote build restart watchdog are active
  for the overnight run.

## 2026-04-27

### Added

- Added the `vm-container-services` profile and Podman service roles.
- Added tmpfs-backed QEMU memory-drive workflows for faster ephemeral build and
  provision cycles.
- Added VM serial watcher helpers for Path B build visibility.
- Added modular cloud-init profile definitions.
- Added the Gentoo rootfs/container image builder flow.
- Added image-level USE, `package.use`, and `sysroot` support for the rootfs
  builder.

### Changed

- Normalized profile/package language around Stage3, Stage4, and Stage5 layers.
- Moved generic VM CPU tuning toward portable `x86_64_v2_generic`.
- Sanitized rootfs builder `FEATURES` so host distcc/ccache state does not leak
  into isolated container builds.

### Fixed

- Fixed container-services runtime stack validation for Podman, Buildah,
  Skopeo, netavark, nftables, nginx, ntfy, and HAProxy.
- Fixed initial `app-alternatives/awk` merged-usr collision through scoped
  container image overrides.
