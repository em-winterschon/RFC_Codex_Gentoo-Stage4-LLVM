# Changelog

## 2026-05-10 - X12AGAIN Builder VM Isolation

- Defined X12AGAIN as a stable hypervisor/resource provider and moved
  heavyweight stage4/stage5, Portage, Path B, and rootfs build work into
  disposable high-resource builder VMs.
- Added staged artifact promotion rules so active netboot paths remain
  publish-only targets and failed builds can be discarded without poisoning the
  host.
- Added a Path B build-root recovery script for stale pseudo-filesystem mounts
  and documented that blind `rm -rf` must not be used against potentially
  mounted build roots.
- Added `gentoo-virt-qemu/x12again-stagebuild-vm.sh` as the repo wrapper for
  disposable high-resource X12AGAIN builder VMs.
- Extended the observability stack with collectd aggregation, Prometheus
  remote-write, a single-node VictoriaMetrics retention profile, NFS-backed
  metrics persistence intent, Grafana dashboard provisioning, and a service
  role to telemetry collector matrix.
- Added SUN99 live observability deployment intent for Prometheus
  `172.16.99.64`, VictoriaMetrics `172.16.99.65`, and Grafana `172.16.99.66`,
  including local-network host vars, Hetzner DNS RRsets, NetBox intake rows,
  fabric metadata, and Hasslehoff NFS metrics export intent.
- Added `scripts/proxmox-materialize-gentoo-openrc-static-net.sh` for
  Proxmox-hosted Gentoo Stage4 service VMs that do not consume Proxmox
  cloud-init metadata inside the guest.
- Applied the SUN99 observability DNS and NetBox inventory live, provisioned
  Hasslehoff VMs `1064`-`1066`, exported VictoriaMetrics NFS persistence from
  Hasslehoff, and converted NetBox plus the observability VMs to static OpenRC
  networking after the cloned image exposed stale DHCP behavior.
- Added a VictoriaMetrics service-VM build governor after the first live
  collectd dependency build exposed `dev-libs/protobuf` using `ninja -j64` and
  OOM-killing `clang++` inside the 8 GiB guest.
- Disabled collectd `rrdtool` and `rrdcached` plugins for the
  VictoriaMetrics/collectd profile because this pipeline uses Graphite and
  Prometheus exporters, and the unnecessary `net-analyzer/rrdtool` dependency
  failed with LLD version-script symbols when graph support was disabled.
- Corrected the NFS storage-client OpenRC service set from the non-existent
  `nfsmount` service to `rpcbind`, `rpc.statd`, `nfsclient`, and `netmount`
  after the live NFSv3 metrics mount required lock-manager startup.
- Brought the Prometheus VM service layer up with Prometheus, Alertmanager,
  blackbox_exporter, snmp_exporter, node_exporter, remote_write to
  VictoriaMetrics, and local exporter scrape validation.
- Brought the Grafana VM service layer up with `grafana-bin`, node_exporter,
  provisioned Prometheus/VictoriaMetrics datasources, and a baseline SUN99
  observability dashboard.
- Brought the VictoriaMetrics VM service layer up with NFS-backed persistence,
  VictoriaMetrics HTTP/Graphite listeners, node_exporter, collectd
  write_prometheus/write_graphite, Prometheus all-target health, VictoriaMetrics
  remote_write visibility, direct collectd Graphite namespace visibility, and
  Grafana datasource health validation.
- Fixed the live rsyslog collector JSON template for `omelasticsearch` by
  quoting the `message` field while retaining JSON escaping, then validated a
  unique TCP syslog marker through `10.9.8.89:514` into the `stage5-syslog`
  Elasticsearch index via the HAProxy VIP `10.9.8.92:9200`.
- Added `scripts/syslog_elasticsearch_validator.py` and `service_readiness`
  support for `type: syslog_elasticsearch`, so post-boot validation can emit a
  fresh syslog marker and verify it is searchable in Elasticsearch.
- Added SUN99 Kibana deployment intent for
  `obs-sun99-kibana-099067.rfc1918.host` / `172.16.99.67`, wired to the live
  Elasticsearch HAProxy VIP `http://10.9.8.92:9200`.

This changelog tracks operator-visible changes to the Stage4/Stage5
infrastructure work. It is intentionally higher level than `git log`.

## 2026-05-09

### Added

- Added the `nfs-storage-client` Stage5 overlay and `nfs_storage_client`
  Ansible role for bare-metal/VM NFSv3, NFSv4, NFS-RDMA, and storage multipath
  readiness. The profile keeps NFSv3/TCP as default, requires AAA/SSSD for
  consistent NFSv4 UID/GID behavior, and excludes containers by default.
- Added gated identity apply automation for the RFC1918 AAA source of truth:
  dry-run JSON plans, explicit global and provider mutation gates, redacted
  audit logging, FreeIPA CLI reconciliation for groups/users/hosts, FreeRADIUS
  `clients.d` rendering, and Ansible playbook integration.
- Added live K10 FreeIPA client enrollment automation and regression coverage:
  host-specific inventory, apply/validate playbooks, SSSD IPA backend checks,
  SSH key lookup checks, PAM checks, and transient floating `codex-admin` SSH
  validation.
- Added K10 netboot-image manifest requirements for carrying the
  `aaa-domain-client` profile into the rebuilt rootfs so future validation can
  prove reboot-durable SSSD/RBAC behavior instead of one-time live mutation.
- Added the `RFC99 Host E2ET Acceptance Pipeline` policy, wiki mirror, and
  regression coverage defining transient validation, reboot-durable acceptance
  gates, conformance tiers, and K10 release-gating semantics.
- Added the first Host E2ET conformance report renderer with JSON, Markdown,
  and JUnit outputs, an Ansible wrapper, and a K10 post-reboot AAA durability
  manifest.

### Changed

- Updated the AAA domain-client package policy to build `sys-auth/sssd` with
  `samba` and `net-fs/samba` with `winbind`, which is required for Gentoo's
  SSSD IPA provider module.
- Removed the obsolete `config_file_version = 2` SSSD directive and made live
  K10 domain-status validation tolerant only of the known no-system-D-Bus live
  image condition after stronger NSS, SSH, PAM, backend-module, and config
  gates pass.
- Recorded the post-PDU-reboot K10 continuity gap: the current netboot rootfs
  returns without SSSD, so AAA client enrollment remains active until the
  rebuilt rootfs or disk-installed Stage5 image survives reboot validation.

## 2026-05-08

### Added

- Added GitHub project-management scaffolding for the interim NOW() tracker:
  structured issue forms, label catalog, milestone catalog, roadmap-derived
  issue seeding, query-parameter issue URLs, and a dry-run-first local seed
  script that avoids GitHub Actions.
- Created the `RFC Codex Infrastructure Roadmap` GitHub Projects v2 board with
  seeded roadmap items and repo-specific `Roadmap Status` / `Roadmap ID`
  fields.
- Added the GitHub issue relationship pass: 14 milestone epic issues,
  relationship labels, roadmap dependency sections with live issue references,
  and Projects v2 `Roadmap Status` / `Roadmap ID` field synchronization.
- Added an AAA identity source-of-truth scaffold for RFC1918: non-secret
  group/user/service-account/host-enrollment/RADIUS-client definitions,
  validation, render-only sync-plan output, Ansible validation playbook, docs,
  and shell regression coverage.
- Extended NetBox structured inventory intake apply support for device
  interfaces, interface-bound management IP assignment, same-host IP convergence
  across prefix-length drift, and non-secret PDU outlet to host power-port
  mapping.
- Promoted the GMKtek K10 Stage5 validation host and APC AP7901 PDU into live
  NetBox with primary management IPs, management interfaces, AP7901 outlet 6,
  and K10 `power0` metadata.
- Added the Alienware `lap-sun99-chonkers.rfc1918.dev` laptop as the second
  physical Stage5 workstation validation target, with Realtek RTL8111H LOM MAC,
  CSS326 `ge15`, AP7901 outlet 4, and iPXE/HTTPv4 boot metadata.

### Changed

- Updated the AAA rollout sequence to use the now-inventoried K10 as the first
  Linux SSSD/RBAC validation client and the AP7901 as the first power-device
  RADIUS enrollment target after local break-glass checks.

## 2026-05-07

### Added

- Added Stage5 `vm-redfish-emulator` profile scaffolding using OpenStack
  `sushy-tools` as the primary libvirt-backed VM Redfish path and DMTF Redfish
  Interface Emulator as the static mockup fallback.
- Added explicit Stage5 workstation AMDGPU/AMDGPU-PRO fallback policy and
  Intel Optane Persistent Memory 200-series `libnvdimm`/`ndctl` readiness.
- Expanded FMT2 NetBox intake from placeholders into a legacy-evidence based
  SFO-200 discovery baseline for tomorrow's BigNetwork L2 validation.
- Added private-CA vault import scaffolding for the RFC1918 certificate
  authority, including PEM/PKCS#12 source support and encrypted
  `vault_private_ca_rfc1918_*` variables.
- Enabled profile-driven HAProxy TLS termination for the container-services
  ntfy VIP while keeping HTTP available concurrently.
- Removed implicit public ntfy fallback from Codex and Ansible notification
  helpers; missing local URL configuration now skips or fails explicitly.
- Added the 2026-05-07 EOD report and wiki mirror covering K10 netboot
  validation, AP7901 PDU vaulting, NetBox inventory gaps, ntfy topic state, and
  the next netboot lifecycle/AAA automation block.
- Added a repeatable BigNetwork vault importer, repo-safe local-network
  BigNetwork variable wiring, and docs for the Forge/Codexian token plus NanoPi
  R6S Edge Lite bridge path.
- Added BigNetwork FMT2 smoke-test scaffolding: a disposable Devuan iPXE/preseed
  asset role, a `bignetwork_edge` service role for the extracted `bn` binary,
  regression coverage, and operator documentation.
- Added `docs/FMT2-INFRA-UPGRADE-PLANNING.md` and wiki mirror to capture the
  legacy SFO-200/FMT2 wiki as traceable evidence for future transport,
  NetBox/IPAM/DCIM, OOB, monitoring, and rack-inventory work.
- Added FMT2 roadmap tasks for evidence consolidation, live validation, NetBox
  intake promotion, transport validation, and Check_MK integration.
- Added explicit `netboot_protocol_flow` modeling for Path B hosts, separating
  IP assignment mode from firmware/handoff behavior.
- Added a reproducible K10 netboot-image manifest for Jenkins-driven future
  dracut/kernel/rootfs artifact rebuilds.
- Added repo-safe local NetBox intake rows for the GMKtek K10 validation host
  and AP7901 PDU, including management IPs and non-secret operational metadata.

### Changed

- Moved GMKtek K10 Stage5 validation from MAC-discovery blocked to active
  iPXE validation tracking after observing DHCP requests from NIC slot
  `04:00:00`, MAC `84:47:09:5F:21:64`.
- Recorded the x86/amd64 netboot policy as UEFI/EFI-only, scoped the K10
  RouterOS DHCP lease to `172.16.99.156`, and set its EFI handoff URL to
  `http://172.16.99.108/k10-ipxe.efi`; the RouterOS gateway role now renders
  DHCP option 60, option 67, `next-server`, and static leases for this class of
  UEFI handoff.
- Captured the current K10 blocker: DHCP ACK is validated, but the firmware has
  not issued ARP or TCP toward `172.16.99.108`, so the remaining work is BIOS or
  UEFI HTTPBoot behavior rather than the on-host netboot address.
- Switched the active K10 fallback to UEFI PXE/TFTP after PXE IPv4 issued ARP
  and TFTP RRQ traffic. The current RouterOS lease renders option 67
  `k10-ipxe.efi` with `next-server=172.16.99.108`; local TFTP fetch from
  `/var/lib/netboot/path-b` validates.
- Patched the live Path B installer initramfs with
  `rtl_nic/rtl8125b-2.fw` after K10 dracut boot showed the Realtek 8125
  firmware missing and DHCP failure. The Path B artifact builder now installs
  `sys-kernel/linux-firmware` and forces the same firmware into future dracut
  initramfs builds.
- Updated the netboot iPXE role template and live K10 installer handoff to use
  the served initramfs basename `initramfs-gz.img` directly, avoiding an
  EFI/iPXE initrd name remap that reached the kernel but skipped dracut.
- Validated K10 through the full UEFI PXE/TFTP to iPXE path using
  `initrd=initrd.magic`, patched RTL8125B firmware in the initramfs, and static
  dracut networking; it now fetches the HTTP rootfs and reaches the Gentoo live
  login prompt.
- Confirmed live NetBox API reachability while identifying that K10 and AP7901
  PDU records still need repo-safe inventory-intake promotion before live apply.
- Updated RouterOS and netboot manifests so managed host entries expose
  protocol-flow intent such as `pxe-to-ipxe`.
- Confirmed the active shell does not currently load the LAN ntfy export file;
  helper defaults now avoid public fallback and require explicit local URL
  configuration.
- Updated the FMT2 Check_MK transport plan to depend on legacy-evidence review
  and live validation before importing Check_MK targets or alerting
  dependencies.

## 2026-05-06

### Added

- Added the 2026-05-06 EOD report and wiki mirror covering workstation GPU
  validation, ntfy topics, K10 discovery state, and active package-build gates.
- Added `scripts/proxmox-create-workstation-nscde-gpu-vm.sh` for the
  Hasslehoff Stage5 workstation GPU VM path.
- Added regression coverage for Proxmox workstation VM rendering, extra Proxmox
  NICs, host PCI passthrough options, and imported-disk resolution from Proxmox
  `unusedN` slots.
- Added exact workstation GPU package pins for the Quadro K1200 validation VM:
  `=x11-drivers/nvidia-drivers-580.159.03-r1` and
  `=dev-util/nvidia-cuda-toolkit-12.9.1-r1`.
- Added `workstation_session_stack`, a cross-OS session abstraction for display
  managers, desktop environments, and window managers. Initial mappings cover
  Gentoo, Debian/Devuan, FreeBSD 14, Solaris 11.4, Tribblix-CE, OmniOS, and
  OpenIndiana task families.
- Added an opt-in workstation GPU display policy for NVIDIA passthrough guests.
  It renders a deterministic Xorg config and `workstation-gpu-display-test`
  helper for PiKVM capture validation.
- Added `scripts/capture-gentoo-emerge-state.sh` and captured the current
  X12AGAIN Portage world, since-boot merge log, and workstation package
  candidate state under `docs/workstation-package-capture/`.
- Added `scripts/generate-workstation-package-review.sh`, imported the microbox
  Gentoo capture, and generated the combined Stage4 LOX workstation package
  review set.
- Added sanitized former LLVM/Clang Portage policy notes from the `legiongo`
  and `susse` etc-keeper archives without importing raw GnuPG/private-key
  material.
- Added Stage4 LOX workstation package policy coverage for NVIDIA, AMDGPU,
  ROCm/AMDGPU-PRO, Intel Xe/Level Zero/OpenCL/Vulkan, and Xorg-only operation.
- Added CCR2004 RouterOS role coverage for LAN ICMP redirect suppression while
  legacy `/24` prefixes share the `br-lan` L2 domain.
- Added a scoped CCR2004 management-compat DHCP definition for
  `172.16.99.150-172.16.99.158` with `1h` leases.
- Added live ntfy service DNS tracking for
  `msg-sun99-ntfysys-099096.rfc1918.host` / `msg-sun99-ntfysys.rfc1918.host`
  on `172.16.99.96`, including RouterOS static DNS render data, Hetzner
  managed RRset inventory data, and NetBox service VIP intake metadata.

### Changed

- Switched the Stage5 workstation Intel policy to display-only by default:
  retained Intel Xorg/Mesa/libdrm/libva/firmware support and removed IGC,
  Level Zero, `intel-compute-runtime`, `intel-metrics-library`, and `gmmlib`
  from the base package path because Gentoo's current IGC hard-locks to
  `llvm:16`.
- Completed the display-only Intel workstation package run on VM `1094` and
  depcleaned stale Intel compute packages from the live validation VM.
- Extended the generic Proxmox Stage4 service VM creator with configurable
  serial, VGA, extra `netN`, and `hostpciN` settings.
- Fixed the Proxmox VM creator to attach the disk reported by `qm config` after
  `qm importdisk` instead of assuming the imported zvol is always
  `vm-${VMID}-disk-0`.
- Updated the workstation profile with explicit NVIDIA/CUDA keyword, license,
  and package-mask gates so the Maxwell K1200 stays on the R580 driver branch.
- Normalized workstation profile naming to
  `stage4-lox__stage5-workstation-nscde__<arch>__gpu-universal-xorg`, with the
  active amd64 binpkg path using
  `stage4-lox__stage5-workstation-nscde__amd64__gpu-universal-xorg`.
- Added profile-level no-Wayland masks for Wayland, Plasma, SDDM, XWayland,
  wlroots, and xdg-desktop-portal in the Stage4 LOX workstation profile.
- Switched the workstation profile to disk-backed `PORTAGE_TMPDIR=/var/tmp/portage`
  for CUDA builds on smaller VMs.
- Added `x11-misc/slim` and `workstation_session_stack` wiring to the NsCDE
  workstation profile, package list, installer playbook, and install sequences.
- Updated the live CCR2004 gateway to disable IPv4 redirects and drop generated
  LAN ICMP redirect packets so `172.16.99.0/24` hosts can consistently transit
  to `172.16.199.0/24` through the router.
- Enabled the live CCR2004 DHCP server `rfc99-management-compat` on `br-lan`
  for `172.16.99.0/24`, gateway/DNS `172.16.99.1`, pool
  `172.16.99.150-172.16.99.158`, and `1h` leases.
- Enabled ntfy in the `vm-container-services` profile and moved its internal
  listener to unprivileged port `8080` so the container can keep `--cap-drop
  all` while HAProxy publishes LAN HTTP on port `80`.
- Updated the `dev-libs/intel-metrics-library` user patch to match the current
  upstream source context and remove upstream release-mode `-flto`, `-fPIE`,
  and linker `-pie` flags.
- Documented the GMKtek K10 discovery blocker: physical link moved to CSS326
  `ge16`, no confirmed DHCP/iPXE lease observed, and `172.16.99.160` is a
  duplicate/unknown host rather than safe K10 evidence.

### Operational Notes

- Hasslehoff QLogic LACP is live through host bond `bond-qlogic0`, VLAN-aware
  Proxmox bridge `vmbr-qlogic0`, and CRS309 `bond-hasslehoff-qlogic`.
- The installed QLogic QL41232HOCU does not expose SR-IOV in Linux, so the
  requested workstation one-VF-per-port design is blocked. The live fallback is
  virtio NICs on tagged VLANs over `vmbr-qlogic0`.
- Proxmox VM `1094`, `vm-workstation-nscde-gpu01`, is running at
  `172.16.99.94` with K1200 VGA/audio functions passed through and a serial
  console enabled for boot visibility.
- The live workstation VM completed the NVIDIA R580 and CUDA 12.9.1 package
  merge. After blacklisting `nouveau` and `nvidiafb` in the guest and rebooting,
  `nvidia-smi` reports Quadro K1200 on driver `580.159.03`, and
  `/opt/cuda/bin/nvcc --version` reports CUDA `12.9`.
- Hasslehoff VM `1089`, `svc-container-services-safe-move-01`, now serves ntfy
  through HAProxy on `172.16.99.96:80`; health and publish validation passed
  through both the long hostname and CNAME alias.
- Xorg and `startx` are present in VM `1094`; `/opt/NsCDE/bin/nscde` and SLiM
  are still pending live application of the workstation session-stack role.
- PiKVM raw uStreamer snapshots showed the original corruption before browser
  transport, so WebRTC/Direct H.264/Legacy MJPEG were ruled out. The live VM now
  has a managed NVIDIA Xorg policy at `1280x720@60`; Direct H.264 displays the
  deterministic K1200 test pattern cleanly.
- Workstation Intel/K10 package build remains active on VM `1094`. Near EOD,
  Portage had an active `emerge --jobs=2 --load-average=10`, the binpkg cache
  was `5.7G` / `437` files, and a second guarded rerun was queued to reuse
  binpkgs after the fixed Intel metrics patch lands.
- Draft PR `#20` was green at commit
  `f61b75d8f0c686d4e82fcdaf6b72df88e580c973` before this EOD documentation
  update.

## 2026-05-05

### Added

- Added `bmc_redfish` and `bmc_idrac` Ansible roles for BMC management
  scaffolding. The roles default to safe read-only behavior and require
  explicit mutation gates for power, boot override, and virtual media actions.
- Added `gpu_host_policy` for GPU compute and passthrough hosts. The role
  renders `nouveau` and `nvidiafb` blacklist controls plus a GRUB drop-in and
  does not reboot or run update commands unless explicitly enabled.
- Added BMC and GPU validation playbooks:
  - `playbooks/bmc-redfish-validate.yml`
  - `playbooks/gpu-host-policy.yml`
  - `playbooks/gpu-host-policy-render-check.yml`
- Added Hasslehoff post-maintenance PCIe inventory for the NVIDIA Quadro K1200
  and QLogic QL41232HOCU CNA.
- Added gated Proxmox host maintenance upgrade scaffolding with pre/post ZFS
  root snapshots.
- Added gated NVIDIA DOCA/OFED repository/package scaffolding for future RoCE
  standardization.
- Added CRS309 render-only intent for Hasslehoff QLogic LACP on
  `sfp-sfpplus4/5`.
- Added `scripts/routeros-serial-command.py`, a RouterOS serial helper that
  handles the `ESC Z` terminal-identification probe emitted after login.
- Added `tests/shell/test_routeros_serial_command.sh` to regression-test serial
  helper answerback and transcript redaction behavior.
- Added EOD status for 2026-05-05 covering GPU passthrough scaffolding, QLogic
  link validation, RouterOS serial automation, and the gated Hasslehoff
  workstation VM next path.

### Changed

- Added `gpu_compute`, `bmc_managed`, and `dell_idrac` inventory groups to the
  local-network inventory.
- Placed Hasslehoff in `gpu_compute` and `bmc_managed`, with BMC live access
  disabled until its IPMI/Redfish credentials are imported into Ansible Vault.
- Extended Hasslehoff GPU policy to blacklist `snd_hda_intel` and prepare exact
  vfio-pci binding for K1200 functions `10de:13bc` and `10de:0fbc`.
- Documented live Hasslehoff QLogic to CRS309 10G-SR validation and the failed
  optic diagnosis.

## 2026-05-04

### Changed

- Upgraded the active CCR2004 gateway from RouterOS `7.19.6` to RouterOS
  package and RouterBOARD firmware `7.22.2`.
- Disabled RouterOS bandwidth-server and the RouterOS `7.22.2`
  `reverse-proxy` service on the CCR2004 gateway and encoded those controls in
  the RFC99 gateway role.
- Confirmed CRS354 is already running RouterOS package and RouterBOARD firmware
  `7.22.2`; disabled bandwidth-server and the `reverse-proxy` service there
  without changing existing SSH/HTTP/HTTPS/WinBox management posture.
- Reframed CRS309 from failed replacement gateway to planned RouterOS
  10GbE spine/aggregation switch.
- Added CRS354 distribution-switch standardization docs and NetBox intake
  coverage for `ether49` management, planned CRS309 LACP on `sfp-sfpplus1/2`,
  existing QNAP TS435XEU DAC LACP on `sfp-sfpplus3/4`, and disconnected QSFP
  RoCE-v2 reservations.
- Recorded the default optical inventory rule: 10G SFP+ optics are `10G-SR`
  over MMF unless explicitly noted otherwise; no SMF optics are currently in
  use. Reference 10G-SR SKUs are FS.com `SFP-10GSR-85` and 10Gtek
  `AXS85-192-M3`.

### Operational Notes

- CCR2004 post-upgrade validation passed for WAN DHCP, dynamic default route,
  DNS resolution, internet egress, LAN reachability, HTTPS management,
  API-SSL, NAT, hardened service surface, and remote syslog to `172.16.99.89`.
- CCR2004 on-device exports/backups were created before and after the upgrade
  under names matching `pre-upgrade-ccr2004-*` and `post-upgrade-ccr2004-*`.
- CRS354 on-device exports/backups were created under
  `precheck-crs354-*` and `post-hardening-crs354-*`.
- CRS309 spine planning found a physical map conflict on `sfp-sfpplus3`; the
  normalized map uses `sfp-sfpplus4` plus `sfp-sfpplus5` for the Hasslehoff
  CCR2004-1G-2XS-PCIe DAC pair.
- CCR2004-to-CRS309 `10G-SR` link came up at `10Gbps` after replacing the
  suspect Intel SR optic pair with FS.com `SFP-10GSR-85` optics.
- CRS309-to-CRS354 `802.3ad` LACP is live using CRS309
  `sfp-sfpplus2/3` and CRS354 `sfp-sfpplus1/2`; both members are active at
  `10Gbps` with FS.com `SFP-10GSR-85` optics.
- Upgraded CRS309 from RouterOS package and RouterBOARD firmware `7.22.1` to
  `7.22.2`; removed unused optional `container` and `zerotier` packages first
  to recover flash space before upgrade.
- Added the SwOS snapshot helper for CSS326, captured current CSS326 state, and
  documented the SwOS automation boundary: HTTP Digest backup/state collection
  plus SNMP polling, not RouterOS-style CLI automation.
- Added render-only RouterOS spine/distribution automation for CRS309 and
  CRS354, including RSC render output, JSON manifest, LACP desired state,
  CRS354 stale-route cleanup, and validation command blocks.
- Confirmed CSS326 is already on the latest SwOS release reported by MikroTik
  (`2.18.1751448030`), with identity `sw-mgmt-mkcss326`, static management IP
  `172.16.99.6`, SNMP enabled, and Hasslehoff LACP on `ge5/ge6`.
- Corrected CRS354 stale OPNsense state for real after serial verification:
  `172.16.254.7/24` on `sfp-sfpplus1` and the `172.16.254.1` default route
  are now disabled while `bond-crs309` remains active.
- CRS354 serial snapshot was archived under
  `/root/operator-private/routeros/crs354/20260504T194533Z`.
- CRS309/CRS354 LACP post-change evidence was archived under
  `/root/operator-private/routeros/lacp-cutover/20260504T210857Z`.
- CRS309 upgrade evidence was archived under
  `/root/operator-private/routeros/crs309/upgrade-*`; CSS326 SwOS snapshots
  are archived under `/root/operator-private/swos/css326/`.
- Live NetBox fabric refresh was applied after snapshot
  `nb-pre-fabric-refresh-20260504`, creating the missing CRS309 spine, QNAP
  archive server, and CCR2004 gateway records. A follow-up apply produced `0`
  creates and `0` updates, then snapshot `nb-post-fabric-refresh-20260504` was
  created.
- Added `scripts/collect-mikrotik-routeros-state.py` and
  `playbooks/routeros-state-snapshot.yml` for read-only RouterOS state
  snapshots. CRS309 SSH snapshot capture is validated; CRS354 remains on
  serial snapshot capture until its SSH command behavior is normalized.
- Added the Forge GitHub token to the encrypted local-network Ansible Vault
  under `vault_github_forge_*` variables and documented the non-secret usage
  pattern for `FORGE_TOKEN`.
- Added the 2026-05-04 EOD report and opened the next Stage5 workstation VM
  planning track for a QEMU-first Xorg, SPICE, and NsCDE workstation profile.
- Added initial `vm-workstation-nscde` profile scaffolding, normalized Xorg and
  NsCDE package atoms, SPICE/QXL QEMU launch support, and the
  `nscde_workstation` source-install role pinned to NsCDE `2.3`.
- Added Stage3 QCOW builder overlay hooks for profile-specific `make.conf` and
  `package.use` fragments, including RAM-backed Portage temp directory
  preparation for `/dev/shm/portage-tmpfs`.
- Started the on-host `vm-workstation-nscde` image build in tmux session
  `codex-workstation-nscde-build` with Portage binpkg generation enabled and
  workstation Xorg/SPICE/NsCDE dependencies staged from the profile package
  list.
- Encoded the first workstation resolver corrections: `media-libs/freetype`
  requires `harfbuzz` for the GTK/xscreensaver path, and PyQt5 remains
  explicitly unmasked until NsCDE can be moved to a non-masked dependency path.
- Added `app-text/xmlto[text]` to the workstation Portage policy for the
  `dunst[xdg] -> xdg-utils` documentation helper dependency chain.
- Added `dev-python/pillow -truetype` as a scoped workstation bootstrap cycle
  break and unmasked `dev-python/pyqt5-sip` alongside PyQt5 for the current
  NsCDE PyQt5 dependency path.

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
- Added `scripts/backup-hasslehoff-config.sh` and
  `docs/HASSLEHOFF-BACKUP.md` to capture Proxmox/Hasslehoff host configuration
  into on-host operator-private storage before gateway and VM changes.
- Added the `vm-nexus-repository` Stage5 profile and `nexus_repo` role for
  Sonatype Nexus Repository OSS `3.90.1-01`, pinned to the local installer
  checksum under `/tmp/Nexus-Repo-OSS`.
- Added Stage5 service app version tracking in
  `app-version-locks/stage5-service-apps.yml` plus
  `docs/PACKAGE-VERSION-PINNING.md`.
- Added `docs/EOD-STATUS-2026-05-03.md` and the CCR2004 gateway swap plan
  `docs/superpowers/plans/2026-05-04-ccr2004-gateway-swap.md`.

### Changed

- Normalized the CRS309 WIP's overlapping `172.16.228.0/22` gateway entries in
  the CCR2004 render by keeping `172.16.228.1/22` and omitting
  `172.16.229.1/22` plus `172.16.230.1/22`.
- Added `package_pins` metadata coverage to Stage4 base metadata and
  observability VM metadata so profile definitions expose tracked atoms and
  known version-lock gaps.

### Operational Notes

- The CCR2004 role is intentionally render-only. No live RouterOS import has
  been implemented or executed yet; serial console and pre-change export remain
  mandatory gates before any live mutation.
- The CCR2004 swap plan now requires an Emergency Gateway Ethernet WAN Link from
  the Codex host to the AT&T gateway L2 before physical cutover.
- Nexus repository proxy API automation is intentionally deferred until Nexus
  admin credentials and TLS are vaulted.
- Hasslehoff backup completed successfully to
  `/root/operator-private/hasslehoff/backups/20260504T040948Z/` with SHA256
  verification.

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
