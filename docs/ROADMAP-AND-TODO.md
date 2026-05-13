# Roadmap and TODO

This page tracks concrete next work, dependencies, and current blockers.

## Critical Path

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `CP-001` | completed | Fix `sys-apps/coreutils-9.10-r1` overlay patch failure | current failed build logs | Overlay now carries referenced patch files and skips split-usr relocation for merged-usr image roots. |
| `CP-002` | completed | Validate `coreutils` in isolation | `CP-001` | `ebuild clean prepare` and focused `emerge --buildpkg` passed; binpkg published. |
| `CP-003` | completed | Restart base-container build against the simplified stage3 path | `CP-002` | Completed on `10.9.8.89` using cached Gentoo `amd64-llvm-openrc` stage3 and Stage5 service-container package layering without `--emptytree`. |
| `CP-004` | completed | Keep successful packages synced during the rerun | `CP-003` | Stage3 repo synced to `10.9.8.90`; package index and reusable binpkgs are present. |
| `CP-005` | completed | Validate finished local image and tarball | `CP-003` | Target image validated: `localhost/gentoo-stage3-llvm-clang-openrc:latest`; tarball exists at `633M`. |
| `CP-006` | completed | Push validated image to GHCR | `CP-005` | Published `git-e5bf45f` and `latest` for `ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc`; both resolve to digest `sha256:4c0cc158b9ab55f7b126dcd80deb8327959a0fd8cd132af7fa09a438df4e85b6`. |

## Active Infrastructure State

### Binpkg Repository

Current repo:

- ID:
  - `stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic`
- VM:
  - `binpkg-repository`
- address:
  - `10.9.8.90`
- HTTP endpoint:
  - `http://10.9.8.90:8088/stage3-llvm_clang_openrc__stage5-service_container-base__amd64__x86_64_v2_generic`
- last observed package index:
  - `12` repository files for the stage3 container repo, including `Packages`
    and `Packages.gz`

Dependency:

- base-container reruns should use this binhost before building missing
  Stage5 service-container packages.

### Container-Services Builder

Current state:

- VM:
  - `container-services`
- address:
  - `10.9.8.89`
- last build state:
  - active path switched to the official Gentoo `amd64-llvm-openrc` stage3
  - hardened source-first graph deferred because it repeatedly hit late
    toolchain/filesystem-layout blockers
  - stage3 rootfs extraction preserves the upstream profile and layers only the
    small Stage5 service-container package list
- synced build artifacts:
  - focused `coreutils` binpkg sync completed
  - periodic watch-sync active during rerun
- live service state:
  - package-backed `rsyslog-collector`, `nginx`, and `haproxy` containers start
    from generated OpenRC Podman wrappers
  - upstream-image `ntfy` is currently stopped after the Docker Hub pull
    stalled during the post-outage redeploy
  - direct nginx ingress on `172.16.99.89:8080` and HAProxy ingress on
    `172.16.99.89:80` return HTTP `200`
  - rsyslog TCP receive on `172.16.99.89:514` works, and HAProxy syslog TCP on
    `172.16.99.89:6514` forwards to the collector
  - HAProxy Elasticsearch VIP on `172.16.99.92:9200` reaches the test
    Elasticsearch backend
  - dedicated CCR2004 rsyslog VIP `172.16.99.93:6514` /
    `log-sun99-rsyslog.rfc1918.host` keeps syslog flows independent from
    Elasticsearch/search VIP changes

Dependency:

- next dependencies are replacing or preloading the `ntfy` image path and
  moving Path B routing/IPAM source-of-truth into Proxmox/NetBox/CCR2004.

## Short-Term Work

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `ST-001` | pending | Add a repo-native mounted-target builder launcher | `CP-003` | Should enforce high-performance defaults and binpkg sync by default. |
| `ST-002` | active | Reduce base-container closure | `CP-005` | Active path now starts from official stage3 and layers only Stage5 service-container packages. |
| `ST-003` | pending | Add explicit binpkg cleanup/retention policy | binpkg VM stable | Decide retention by repo ID, profile generation, and disk pressure. |
| `ST-004` | completed | Validate GHCR publish workflow end-to-end | `CP-006` | Base image published to GHCR; VM-side Podman was too slow, so host-side `crane` pushed the docker archive and recorded the registry digest. |
| `ST-005` | pending | Add build metrics as CI artifacts | `CP-003` | Use `scripts/export_build_metrics.py` output in Jenkins later. |
| `ST-006` | active | Reduce dependency-tree failure blast radius | `CP-003` | Default to the standard stage3 base for the first image; keep hardened source-first work as a later, isolated track. |
| `ST-007` | completed | Add rsyslog as a service-container layer | `CP-005` | Two-phase `rsyslog_collector` service-layer image built, smoke-tested, published to GHCR, and synced to its service binpkg repo. |
| `ST-008` | completed | Wire service layers to the published base image | `CP-006` | `container-service-base-image.yml` defines GHCR base-image provenance and app build defaults; container hosts render `/etc/container-services/base-image.yml`; `service-layers.yml` tracks package-backed and upstream-image service candidates. |
| `ST-009` | completed | Add service-layer build automation | `ST-008` | `run-container-service-layer-build-pathb.sh` can build `nginx`, `haproxy`, and `rsyslog_collector` service images with per-service package lists and binpkg repo IDs. |
| `ST-010` | completed | Validate package-backed service images | `ST-009` | `nginx`, `haproxy`, and `rsyslog_collector` images built, smoke-tested, published to GHCR, and synced to service binpkg repos. |
| `ST-011` | completed | Wire package-backed images into runtime profiles | `ST-010` | `vm-container-services` now defaults nginx and HAProxy to the published GHCR Stage5 images; `container-rsyslog-collector` now uses the published GHCR rsyslog image with explicit command, tmpfs, and spool-volume handling. |
| `ST-012` | completed | Live-validate generated Podman service wrappers on the container-services VM | `ST-011` | Initial chroot/live validation passed for `rsyslog-collector`, `nginx`, `ntfy`, and `haproxy`. Hasslehoff safe-move validation now has `ntfy`, `rsyslog-collector`, `nginx`, and `haproxy` running under OpenRC/Podman. |
| `ST-013` | completed | Validate post-outage installed-disk container-services redeploy | `ST-012` | Host-side checks passed for `172.16.99.89:8080`, `172.16.99.89:80`, `172.16.99.89:514/tcp`, `172.16.99.89:6514/tcp`, and `172.16.99.92:9200`. |
| `ST-014` | pending | Replace `ntfy` upstream-image dependency | `ST-013` | Build a package-backed Stage5 image or add a controlled archive preload path so redeploys do not depend on Docker Hub availability. |
| `ST-015` | completed | Add explicit image pull/preload policy to runtime app profiles | `ST-013` | Generated Podman wrappers emit `--pull`; package-backed GHCR profiles default to `missing`, and the live Path B `ntfy` override uses `never` while the upstream-image path is blocked. |
| `ST-016` | active | Safe-move container-services workload to Hasslehoff Stage4 VM | `PNR-014`, `ST-013` | Staging VM `svc-container-services-safe-move-01` is live at `172.16.99.89`; Podman/Buildah/Skopeo bootstrap completed; rsyslog, nginx, HAProxy, and ntfy are running. ntfy is exposed on service VIP `172.16.99.96` as `msg-sun99-ntfysys-099096.rfc1918.host` with RouterOS, Hetzner, and NetBox tracking. CCR2004 owns the scoped Elasticsearch/search VIP `obs-sun99-esvip-099092.rfc1918.host` / `172.16.99.92` and the dedicated rsyslog VIP `log-sun99-rsyslog-099093.rfc1918.host` / `172.16.99.93` with RouterOS DNS, Hetzner DNS, DNAT, and hairpin SRCNAT. Elasticsearch now runs on Hasslehoff VM `1091` at `10.9.8.91` on VLAN1098; temporary `/32` Path-B backend routes via X12AGAIN were removed after validation. |

## Proxmox, NetBox, And RouterOS

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `PNR-001` | active | Bootstrap Codex SSH access to Proxmox, NetBox jail host, and CCR2004 RouterOS | operator-provided addresses and credentials | Proxmox SSH/API token and CRS354 vaulting are complete; Hasslehoff inventory validates through Ansible. NetBox API root is reachable at `172.16.99.62`; CCR2004 vault-backed SSH auth validated for the scoped service-VIP apply. |
| `PNR-002` | completed | Confirm management subnet and NetBox API access | `PNR-001` | Management subnet is tracked as `172.16.99.0/24`; replacement Stage4 VM `1062` serves NetBox `v4.5.9` at `172.16.99.62`. |
| `PNR-003` | completed | Import draft Path B, VIP, container, OOB, and builder prefixes into NetBox | `PNR-008` | `scripts/netbox_seed_local_network.py` created `42` conservative fabric objects from the local network fabric inventory. |
| `PNR-007` | completed | Deploy NetBox `v4.5.9` on Stage4 VM `1062` | `PNR-002` | NetBox is live under OpenRC with PostgreSQL, Redis, gunicorn, RQ worker, nginx, and API token validation. |
| `PNR-008` | completed | Install essential NetBox operational integrations before writes | `PNR-007` | `pynetbox`, `netbox-agent`, `netbox-sync`, `netbox-tools`, `devicetype-library`, and `Device-Type-Library-Import` are isolated under `/opt/netbox-essentials`; the initial device-type import loaded `1924` device types. |
| `PNR-009` | completed | Inventory additional clusters and datacenters into NetBox | `PNR-010` | RFC99, SUN99, YKS99, and FMT2 structured intake applied live with pre/post snapshots and idempotence validation. |
| `PNR-010` | completed | Add structured NetBox inventory intake and apply workflow | `PNR-003` | Validator, dry-run/apply script, Ansible wrappers, local baseline file, live apply, idempotence pass, and post-apply snapshot are complete. |
| `PNR-011` | completed | Convert RFC99/SUN99/FMT2 host/IP/MAC source file into structured NetBox intake | `PNR-010` | `/tmp/rfc99-sun99-host-networking.md` is archived under operator-private storage; sanitized `rfc99`, `sun99`, `yks99`, and `fmt2` intake files validate locally and were applied live on 2026-05-03. |
| `PNR-013` | active | Use NetBox to drive provisioning inventory and IPAM maps | `PNR-011`, `DNS-003` | Action plan and exporter are in place. Current live unfiltered export produces `7` standalone IP bootstrap hosts from `12` NetBox IP records; VM/device primary-IP ownership tags remain next. |
| `PNR-014` | active | Prepare generic Proxmox Stage4 service VM creation path | `PNR-013` | Dry-run-first VM creator is added for Hasslehoff service VMs; live apply requires `PROXMOX_APPLY=1` and existing VM replacement requires `PROXMOX_REPLACE=1`. `scripts/proxmox-materialize-gentoo-openrc-static-net.sh` now covers cloned Gentoo images that do not consume Proxmox cloud-init inside the guest. |
| `PNR-015` | active | Track temporary Hasslehoff staging VMs in NetBox before live cutover | `PNR-014` | `svc_container_services_safe_move_01` is in NetBox/IPAM as planned with DNS name `svc-container-services-safe-move-01.rfc1918.host` and IP `172.16.99.89/24`; DNS plan is dry-run only. |
| `PNR-012` | completed | Replace failed OPNsense path with RouterOS after NetBox staging | `PNR-011` | CCR2004 is the active gateway on RouterOS package and RouterBOARD firmware `7.22.2`; WAN DHCP, default route, DNS, NAT, HTTPS/API-SSL management, hardened surface, and remote syslog validated after upgrade. |
| `PNR-017` | active | Rebuild CRS309 as RouterOS 10GbE spine aggregation switch | `PNR-012` | CRS309 is live on RouterOS package and RouterBOARD firmware `7.22.2`; port conflict normalized by assigning CRS354 LACP to CRS309 `sfp-sfpplus2/3`, Hasslehoff QLogic QL41232HOCU LACP to CRS309 `sfp-sfpplus4/5`, CSS326 to `sfp-sfpplus8`, and CCR2004 gateway uplink to `sfp-sfpplus1`. Remaining work is cabling/validating CSS326 `sfp1` to CRS309 `sfp-sfpplus8` and the Hasslehoff QLogic LACP pair. |
| `PNR-018` | completed | Standardize CRS354 distribution-switch inventory and CRS309 LACP uplink | `PNR-017` | Live CRS354 snapshot archived under `/root/operator-private/routeros/crs354/20260504T194533Z`; CRS309/CRS354 LACP validated active on 2026-05-04 with both members at `10Gbps`; NetBox intake models management on `ether49`, CRS309 LACP on `sfp-sfpplus1/2`, QNAP TS435XEU DAC LACP on `sfp-sfpplus3/4`, and disconnected QSFP RoCE-v2 reservations. |
| `PNR-019` | completed | Normalize CSS326 SwOS access-switch state and backup collection | `PNR-017` | CSS326 is reachable at `172.16.99.6`, identity `sw-mgmt-mkcss326`, latest SwOS `2.18.1751448030`, SNMP enabled, and Hasslehoff LACP active on `ge5/ge6`; `scripts/collect-mikrotik-swos-state.py` captures SwOS state and `backup.swb` to operator-private storage. SwOS has no observed syslog destination support, so monitoring is SNMP plus snapshots. |
| `PNR-020` | active | Convert RouterOS spine/distribution changes into idempotent Ansible roles | `PNR-017`, `PNR-018` | Render-only role and playbook now emit CRS309/CRS354 RSC plus manifest for LACP and stale-state cleanup. Read-only RouterOS SSH snapshot automation is in place and validated for CRS309. Hasslehoff now has validated serial paths for CRS309, CRS354, and CCR2004; remaining work is fixture-backed RouterOS render tests, serial-gateway execution automation, and explicit serial-gated apply handling. |
| `PNR-021` | completed | Apply latest local fabric intake to live NetBox | `PNR-019`, `PNR-020` | Snapshot `nb-pre-fabric-refresh-20260504` was created before write. NetBox fabric refresh created CRS309 spine, QNAP archive storage, and CCR2004 gateway objects, then idempotence completed with `0` creates and `0` updates before snapshot `nb-post-fabric-refresh-20260504`. |
| `PNR-022` | pending | Deep-model NetBox interfaces, LAGs, optics, and cables | `PNR-021` | Current intake covers devices, prefixes, management IPs, clusters, and VIPs. Next DCIM step is interface-level records for CRS309/CRS354/CSS326/Hasslehoff/QNAP with cable and optic metadata. |
| `PNR-023` | pending | Add Hasslehoff IPMI and Redfish credentials to Ansible Vault | `PNR-016`, vault workflow | Operator provided temporary credential source at `/tmp/hasslehoff-ipmi-creds.tmp`; import into encrypted local-network vault as `vault_hasslehoff_ipmi_*` / `vault_hasslehoff_redfish_*`, validate Redfish auth against `https://ipmi-verwalterin.rfc1918.host/redfish/v1/`, then remove the plaintext temp file. |
| `PNR-024` | scaffolded | Add Redfish and Dell iDRAC BMC control-plane roles | `PNR-023` for live Hasslehoff validation | `bmc_redfish` and `bmc_idrac` roles are scaffolded with read-only defaults and explicit mutation gates for power, boot override, and virtual media workflows. Live Dell R630/R730xd and IBM LC922 validation waits for SD-WAN/L2 reachability and vaulted BMC credentials. |
| `PNR-025` | active | Track Hasslehoff GPU compute and passthrough host policy | workstation VM profile | Hasslehoff is in `gpu_compute`; the `gpu_host_policy` role renders `nouveau`, `nvidiafb`, and Hasslehoff-specific `snd_hda_intel` blacklist controls, vfio-pci K1200 ID binding, a GRUB drop-in, and optional Proxmox `/etc/kernel/cmdline` handling. |
| `PNR-026` | scaffolded | Add gated Proxmox host maintenance upgrade workflow | `PNR-016` | `proxmox_host_upgrade` is plan-only by default, validates the PVE8/bookworm lane, and creates pre/post recursive ZFS snapshots around apt maintenance when explicitly applied. |
| `PNR-027` | scaffolded | Add gated NVIDIA DOCA/OFED host-driver workflow | `PNR-026`, RoCE fabric | `nvidia_doca_ofed` requires explicit repo package input, matching kernel headers, and a custom-kernel acknowledgement before installing on a Proxmox kernel. |
| `PNR-028` | active | Bring up Hasslehoff QLogic LACP and workstation VM high-speed network test | `PNR-020`, `PNR-025` | CRS309 `bond-hasslehoff-qlogic`, Hasslehoff `bond-qlogic0`, and `vmbr-qlogic0` are live. SR-IOV is blocked because the QLogic functions expose no SR-IOV capability; workstation VM `1094` uses tagged virtio NICs on `vmbr-qlogic0` as the fallback. |
| `PNR-029` | completed | Normalize RouterOS serial command automation for CRS309 | `PNR-020` | Added `scripts/routeros-serial-command.py` with VT100/ANSI answerback handling for RouterOS `ESC Z` terminal-identification probes; live read-only CRS309 identity command validated. |
| `PNR-030` | completed | Promote K10, AP7901 PDU, and Chonkers operational discoveries into NetBox intake | `PNR-010`, `WS-006`, PDU vault import | Repo-safe intake now covers K10 device/interface/IPAM/switchport metadata, AP7901 non-secret inventory/outlet mapping, and Chonkers laptop LOM/switch/power metadata. PR `#103` carries the stacked first-enrollment intake. |
| `PNR-031` | completed | Add NetBox power-chain modeling for PDU outlet to host relationships | `PNR-030`, power-device model support confirmed | NetBox now has real DCIM cable objects for AP7901 `outlet6 -> gmktek_nucbox_k10_stage5_candidate:power0` and AP7901 `outlet4 -> lap_sun99_chonkers:power0`. Live apply was snapshot-backed and idempotence validated with `created=0`, `updated=0`, `existing=303`. |
| `PNR-032` | completed | Add encrypted network-device post-change config backup back-channel | `PNR-019`, `PNR-020`, vault workflow | `scripts/backup-network-device-configs.sh` now runs RouterOS and SwOS snapshot playbooks, requests RouterOS `show-sensitive` exports over SSH or serial for encrypted backup workflows, encrypts selected artifacts with `ansible-vault`, and stages repo-safe vault files under `encrypted-backups/network-devices/` with optional git add/commit/push sync. |
| `PNR-033` | completed | Move live RouterOS serial consoles off X12AGAIN onto Hasslehoff interim USB hub | X12AGAIN reimage prep, `PNR-020` | CCR2004, CRS354, and CRS309 serial consoles were moved to Hasslehoff on 2026-05-10 through an interim generic VIA Labs USB hub. Stable FTDI by-id paths are tracked in local-network inventory, and all three prompts were validated at `115200` baud. Target state remains a dedicated serial gateway VM plus Coolgear `CG-4PU3MGD` managed hub after replacement power is available. |
| `PNR-016` | active | Capture Hasslehoff host backups before gateway and VM changes | `PNR-001` | `scripts/backup-hasslehoff-config.sh` now captures `/etc/pve`, network/sysctl state, Proxmox JSON, and host summaries to `/root/operator-private/hasslehoff/backups`. |
| `PNR-004` | planned | Export current QEMU RouterOS Path B config as rollback | `PNR-001` | Must happen before CCR2004 mutations. |
| `PNR-005` | planned | Apply CCR2004 management-only baseline | `PNR-004` | Routing migration waits until management access is repeatable. |
| `PNR-006` | planned | Move Path B gateway functions to CCR2004 | `PNR-005` | Validate DNS, internet egress, binpkg access, and HAProxy VIP ingress before retiring QEMU RouterOS. |

## Repository Proxy And Version Locks

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `REPO-001` | active | Add Sonatype Nexus Repository OSS as an infrastructure proxy VM | Stage5 VM profile base | `vm-nexus-repository` and `nexus_repo` are scaffolded with installer checksum pinning and declarative proxy intent. Live API repo creation waits for vaulted credentials and TLS. |
| `REPO-002` | active | Track app/service version locks in repo data | profile metadata | `app-version-locks/stage5-service-apps.yml` tracks explicit locks and pin gaps for Portage-resolved services. |

## Stage5 Service Tracks

### Jenkins And Builder Farm

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `CI-001` | scaffolded | Validate Jenkins controller VM role | binpkg repo stable | Role and example inventory exist; needs a real installed VM test. |
| `CI-002` | scaffolded | Validate first Atom C3758 distcc worker | builder fabric cabled | Start with one node before rolling to all six. |
| `CI-003` | pending | Wire Jenkins jobs for base image, binpkg sync, and GHCR push | `CI-001`, `CP-006` | Jobs should publish build metrics and artifacts. |
| `CI-004` | pending | Expand distcc policy around network isolation and QoS | `CI-002` | Builder fabric should land on `ens7f0np0` or `ens7f1np0` via switch. |

### Identity, RBAC, And AAA

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `AAA-001` | completed | Validate FreeIPA server/client roles on fresh VMs | basic VM provisioning stable | Rocky 9 controller VM `1063` / `svc_identity_ipa01` is live at `172.16.99.63`; FreeIPA, SSSD, and central SSH key identity are validated. |
| `AAA-002` | completed | Validate FreeRADIUS against LDAP/FreeIPA backend | `AAA-001` | FreeRADIUS LDAP bind and `radtest` validation passed; UDP `1812`/`1813` are listening. |
| `AAA-003` | pending | Define optional TACACS+ bridge | `AAA-002` | Only needed for Cisco devices if RADIUS is insufficient. |
| `AAA-004` | active | Map RBAC policy to SSH keys, VPN users, switches, smartcards | `AAA-001` | Initial `codex-admin`, `linux-admin`, `network-readonly`, and RADIUS validation mappings exist. The non-secret identity source-of-truth scaffold now records first users, groups, service account, K10 host enrollment, and AP7901 RADIUS client intent. |
| `AAA-005` | active | Enroll APC PDUs, APC ATS, and UPS management cards into central RADIUS auth | `AAA-002`, `OBS-004`, power-device inventory | Scope includes APC AP7901/AP7902 PDUs, AP4450 ATS, AP9631/AP9641 UPS cards, and any compatible CyberPower/Eaton management modules. First target is the AP7901 at `172.16.99.241` after non-secret NetBox inventory exists. Preserve local break-glass accounts, test one low-risk device first, and document vendor-specific RADIUS attributes before bulk rollout. |
| `AAA-006` | completed | Convert AAA source-of-truth render output into gated FreeIPA/FreeRADIUS apply automation | `AAA-001`, `AAA-002`, `AAA-004` | `scripts/apply_identity_sync_plan.py` and `identity-source-apply.yml` add dry-run plans, explicit global/provider mutation gates, vault-variable resolution, redacted audit logging, FreeIPA CLI reconciliation, and FreeRADIUS `clients.d` rendering. |
| `AAA-007` | active | Enroll K10 as the first SSSD/RBAC workstation client | `AAA-006`, `WS-006`, `PNR-030` | Transient live Gentoo image enrollment passed on 2026-05-09. On 2026-05-11 AP7901 outlet 6 rebooted the promoted Path B rootfs with SSSD, Samba, Kerberos, OpenLDAP, and `libsss_ipa.so` present; post-boot `ipa-client-live-apply.yml` and `ipa-client-live-validate.yml` passed, and floating SSH as `codex-admin` resolved expected UID/GID/group mappings. Remaining blocker: unattended reboot-durable host enrollment must not embed `/etc/krb5.keytab` in HTTP netboot artifacts, so removal condition is disk-installed Stage5 or `stage5-firstboot-enroll` consuming an age-encrypted FreeIPA host OTP bundle and generating the keytab on-target. |
| `AAA-008` | pending | Enroll AP7901 as the first RADIUS-managed power device | `AAA-006`, `AAA-005`, `PNR-031` | Render and deploy the AP7901 FreeRADIUS client stanza, preserve local break-glass access, validate read-only RADIUS login first, then test power-admin authorization before any wider PDU/UPS/ATS rollout. |
| `AAA-009` | active | Persist K10 Stage5 installed-system SSSD policy | `AAA-007`, `WS-006` | Package-layer rootfs rebuild is complete; the remaining work is persistent hostname/FQDN behavior, secure first-boot FreeIPA OTP bundle delivery or disk-install enrollment, SSSD offline cache, sudo rule refresh, local break-glass account access, and reboot durability before enrolling additional Linux clients. |
| `AAA-010` | planned | Add optional Tang/Clevis NBDE hardening for firstboot enrollment | `AAA-009`, Guru package pinning | Immediate K10 path remains age-encrypted FreeIPA OTP. Tang/Clevis should be modeled as optional `tpm2+tang` host-bound hardening with a Tang service role, Clevis client package policy, Guru atoms `app-crypt/tang` and `app-crypt/clevis`, and explicit validation that Tang-only unlock is never used for host enrollment secrets. |

### Storage, NAS, And Home Directories

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `NAS-001` | pending | Inventory QNAP TS435XEU and prepare NFS home-directory service | `AAA-006`, `PNR-021`, `PNR-022` | Operator is powering on the QNAP NAS with roughly 16TB raw storage, 2x 2.5GbE, and 2x 10GbE currently expected on CRS354 `sfp-plus3/4`. First pass should discover firmware, storage pools, NIC MACs, link mode, LACP state, NFS capabilities, LDAP/RADIUS/SSSD integration options, and safe backup/export settings before enabling floating home directories. |

### Observability, Logs, And Telemetry

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `OBS-001` | scaffolded | Validate baseline `node_exporter` on machine/VM/container profiles | VM roles stable | Should be common across Stage5 profile types. |
| `OBS-002` | scaffolded | Validate Prometheus and Grafana VM profiles | `OBS-001` | Prometheus scrape config intentionally remains raw/flexible. |
| `OBS-003` | scaffolded | Validate IPMI and Redfish exporter containers | container-services stable | Needed for builder farm and chassis telemetry. |
| `OBS-004` | scaffolded | Validate SNMP modules for UPS, ATS, PDU, and OOB devices | observability network access | Start conservative, then tune vendor OIDs per device. |
| `OBS-005` | active | Add VictoriaMetrics retention and collectd aggregation | `OBS-001`, NFS client profile | Added single-node VictoriaMetrics profile, Prometheus remote_write, collectd Graphite forwarding, collectd Prometheus scrape, NFS-backed metrics mount intent, and SUN99 live VM reservations for Prometheus `172.16.99.64`, VictoriaMetrics `172.16.99.65`, and Grafana `172.16.99.66`. |
| `OBS-006` | scaffolded | Add service-specific dashboards and alert thresholds | `OBS-002`, `OBS-003`, `OBS-004`, `OBS-005` | Initial Grafana dashboard provider exists; avoid fake thresholds before real device walks. |
| `OBS-007` | completed | Provision SUN99 observability VM trio on Hasslehoff | `PNR-014`, `OBS-005`, DNS/NetBox dry-run review | DNS, NetBox intake, Hasslehoff NFS export, Proxmox VMs `1064-1066`, static OpenRC networking, SSH, rootfs growth, Prometheus, Alertmanager, blackbox_exporter, snmp_exporter, node_exporter, VictoriaMetrics, collectd, NFS-backed persistence, Prometheus remote_write, and Grafana datasource health are validated live. Follow-on work is post-install automation hardening and device-specific collector tuning. |

### Time Authority

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `TIME-001` | scaffolded | Build local Stratum 1 NTP authority | CM4 hardware assembled, GNSS antenna placement | `metal-time-authority-stratum1` defines the CM4 plus U-Blox MAX-M8Q primary GNSS, USB GPS secondary, Chrony, GPSD, PPS, Chrony exporter, and gated LinuxPTP package/profile baseline. |
| `TIME-002` | pending | Validate PPS/GNSS/Chrony source selection | `TIME-001` | Acceptance requires `/dev/pps*`, GNSS fix state, `chronyc tracking`, `chronyc sources -v`, `chronyc sourcestats -v`, exporter scrape, and alerts for lost GPS/PPS/high offset. |
| `TIME-003` | pending | Decide PTP grandmaster hardware path | `TIME-001`, timestamp-capable NIC test | PTP remains disabled until `ethtool -T` proves hardware timestamp support on the selected NIC. If no timestamp NIC is available, NTP Stratum 1 remains the supported first release. |

### Logging And Search

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `LOG-001` | scaffolded | Validate rsyslog client templating everywhere | base profiles stable | Base rsyslog role now supports remote forwarding. |
| `LOG-002` | completed | Validate centralized rsyslog receiver container | container-services stable | Live TCP receive is validated on `172.16.99.89:514`; HAProxy syslog TCP is validated on `172.16.99.89:6514`; dedicated rsyslog ingress is tracked as `log-sun99-rsyslog.rfc1918.host` / `172.16.99.93:6514`; HAProxy exposes Elasticsearch through the CCR2004 SUN99 VIP at `172.16.99.92:9200`; `scripts/syslog_elasticsearch_validator.py` sends a unique marker through rsyslog and verifies it is searchable in `stage5-syslog.message`. |
| `LOG-003` | pending | Validate 3-node Elasticsearch VM profile | VM provisioning stable | Must include load-balanced access path. |
| `LOG-004` | completed | Validate Kibana VM profile | `LOG-002`, `PNR-014` | Hasslehoff VM `1067`, `obs-sun99-kibana-099067` / `172.16.99.67`, is live with upstream Kibana `9.3.1`, HTTP status `available`, Elasticsearch `9.3.1` reachable through the CCR2004 SUN99 VIP `172.16.99.92:9200`, and default `stage5-syslog*` data view created. Gentoo `www-apps/kibana-bin` was rejected because it is `7.17.25` and incompatible with Elasticsearch `9.3.1`; the profile now uses the verified Elastic tarball. |
| `LOG-005` | pending | Validate APM container profile | `LOG-003`, container-services stable | Feed traces into Elasticsearch cluster. |

### FMT2 / SFO-200 Recovery

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `FMT2-001` | completed | Capture legacy FMT2/SFO-200 wiki as evidence | old wiki clone available | Evidence index lives in `docs/FMT2-INFRA-UPGRADE-PLANNING.md`; source repo is `/opt/repos/remote/blumens/wikis-mkdocs/blumen-arch.wiki` at observed commit `bd5b71b`. |
| `FMT2-002` | active | Validate FMT2 transport path from RFC99/SUN99 | BigNetwork SDN or compatibility OpenVPN VM | BigNetwork is the first implementation path. Devuan smoke-test netboot assets and `bignetwork_edge` role scaffolding exist; Forge/Codexian BigNetwork token import is vaulted. Preferred steady-state is re-onboarding the local NanoPi R6S Edge Lite as a transparent L2 bridge; removal condition is repeatable bidirectional reachability to one FMT2 management prefix plus DNS resolution for legacy monitoring names. |
| `FMT2-003` | pending | Promote verified FMT2 prefixes, racks, and devices into NetBox | `FMT2-001`, `FMT2-002` | Import prefixes and racks first, then routers/switches, then hosts/BMCs, then services. All records should be tagged to the old wiki source commit until independently verified. |
| `FMT2-004` | pending | Reconnect FMT2 Check_MK to managed observability | `FMT2-002`, `FMT2-003` | Confirm `app-sfo200-monitoring-9927.vernetzen.io`, `/vernetzen/`, API endpoint, agents path, and return routing before adding targets or alert dependencies. |
| `FMT2-005` | planned | Bring up BigNetwork L2 path for FMT2/SFO-200 discovery | `FMT2-002`, BigNetwork portal/device access | Issue #114. Readiness runbook and evidence-bundle requirements are now captured in `docs/BIGNETWORK-FMT2-SMOKETEST.md`; live transport work remains deferred until the X12AGAIN off-host backup is complete. Once reachable, run connectivity discovery, promote verified records into NetBox, and feed Check_MK/observability onboarding. |

### DNS Automation

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `DNS-001` | completed | Vault Hetzner Cloud DNS API token groups | Ansible Vault workflow | Imported `rfc1918`, `vernetzen`, and `yukon` token groups into encrypted local-network vault and validated API access without printing token values. |
| `DNS-002` | completed | Generate Hetzner DNS RRset plans from NetBox | `DNS-001`, NetBox IPAM/DCIM apply | Dry-run planner generated `7` RRsets from NetBox and skipped `5` unnamed management IPs; apply and delete remain disabled. |
| `DNS-003` | completed | Validate live Hetzner zone inventory and build connectivity target maps | `DNS-001` | Read-only provider report validated `8/8` zones, counted `221` records, and emitted `99` hostname/IP connectivity targets for healthchecks and nmap scans. |
| `DNS-004` | pending | Apply controlled Hetzner DNS CRUD operations | `DNS-002`, `DNS-003` | Use reviewable RRset plans and require explicit apply/delete gates. |

### LLM API And RAG Services

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `LLM-001` | planned | Reserve VLAN, VIP, and NetBox model space for LLM/RAG service traffic | network fabric source of truth | Track Ollama, OpenWebUI, vLLM, SourceBot, API proxy, provider pools, GPU hosts, and RAG data paths without blocking current fabric work. |
| `LLM-002` | pending | Scaffold LLM API proxy service role | `LLM-001`, container-services stable | Proxy must route across local vLLM providers and external APIs such as OpenAI. |
| `LLM-003` | pending | Scaffold OpenWebUI and Ollama service definitions | `LLM-001`, GPU service inventory access | Operator already has separate deployment automation; import only after Codex access is available. |
| `LLM-004` | pending | Scaffold RAG ingestion, embedding, and retrieval pipeline roles | `LLM-002`, `LLM-003` | Keep metrics, logs, provider routing, and service VIPs explicit. |

### Project Management And MCP Control Plane

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `PM-001` | completed | Bootstrap GitHub Issues, milestones, and project board from the roadmap | GitHub token with issue/project permissions | Issue forms, labels, milestones, roadmap-derived issues, and Projects v2 board are seeded. Project URL: `https://github.com/users/em-winterschon/projects/1`. |
| `PM-002` | completed | Enable GitHub Projects v2 board creation scope | GitHub token with `project` / `read:project` scope | Scope updated and validated. Project board has `81` items plus `Roadmap Status` and `Roadmap ID` fields. |
| `PM-003` | completed | Layer roadmap issues into milestone epics and dependency chains | `PM-001`, `PM-002` | Relationship pass created `14` milestone epic issues, added `type:epic` / `type:story` / `type:task` and dependency labels, rewrote issue dependency sections with live `#issue` references, and synced project fields. Native GitHub issue-link mutations remain optional/best-effort. |
| `MCP-001` | active | Add generic MCP and Nginx-UI control-plane services behind HAProxy | container-services stable, private CA, vault workflow | `vm-mcp-control-plane` scaffolds Nginx-UI MCP routing, OpenAI-compatible env references, and a disabled-by-default generic MCP backend. Live deployment waits for vaulted Nginx-UI secrets, DNS/IPAM records, and TLS certificate material. |
| `MCP-002` | pending | Validate live Nginx-UI MCP service on LAN | `MCP-001`, AAA apply path | Validate HTTPS, `/mcp` SSE behavior, `node_secret` auth, no Docker socket mount, and OpenAI-compatible config without exposing tokens in logs. |
| `MCP-003` | ready | Evaluate self-hosted MCP runtime and safe Trac integration | `PM-001`, `MCP-001` | Keep Trac write access blocked until a custom allowlisted MCP wrapper or equivalent control plane exists. |
| `MCP-004` | planned | Implement FastMCP infrastructure service wrappers | `MCP-001`, `MCP-002`, `DNS-003`, `AAA-009` | Promotion order is Nginx-UI native validation, then `netbox-mcp`, `proxmox-mcp`, `routeros-mcp`, `trac-mcp`, and `infra-mcp`. Every mutation requires `MCP_ALLOW_MUTATIONS`, vaulted credentials, an idempotency key, and an audit artifact. See `docs/FASTMCP-INFRA-CONTROL-PLANE.md`. |
| `MCP-005` | scaffolded | Add FastMCP common safety helpers and NetBox wrapper skeleton | `MCP-004` | `scripts/mcp_servers/` now has shared settings, mutation gate, audit artifact helpers, and a NetBox MCP skeleton with read/plan/apply boundaries. Backend NetBox client wiring remains gated follow-up work. |

### Agent Analytics And Shared Memory

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `AGENT-001` | active | Track per-query and response-cycle timing in project memory | repo operating policy | `AGENTS.md` now requires start/end/elapsed timing capture when practical, with durable storage in EOD/SITREP or future structured analytics logs. Do not estimate uncaptured timings. |
| `MEM-001` | planned | Design distributed Codex shared memory service | object storage backend, MCP control plane | Target backend is S3-compatible object storage with append-only event logs, signed manifests, replayable summaries, and per-agent namespace isolation. |
| `MEM-002` | planned | Add S3 object-store service role for agent memory artifacts | storage fabric and private CA | Define bucket policy, lifecycle retention, object naming, encryption, and audit logs before using it as a cross-agent memory substrate. |
| `MEM-003` | scaffolded | Implement Forge cross-machine continuity bootstrap | `MEM-001`, `MEM-002`, `MCP-004` | Issue #115. Initial `scripts/forge_memory_spool.py` writes append-only local events, unsigned closeout manifests, and local session summaries with secret-key rejection. Remaining work is object-store upload, manifest signing, MCP facade methods, and bootstrap reconciliation against repo/GitHub state. |
| `COH-001` | planned | Package and service-role Coherence-CE for memory/cache experiments | `CI-003`, `MEM-001` | Determine source/build path, license, runtime requirements, service topology, and Jenkins build hooks. Treat as experimental until repeatable build and service readiness checks exist. |

### Storage Fabric, RDMA, And HPC Planning

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `RDMA-001` | planned | Define RoCE-v2 switch tuning profiles | CRS309/CRS354/CRS354 leaf-spine model, NIC inventory | Track PFC/ECN/DSCP, MTU, queueing, LAG behavior, lossless class boundaries, and rollback for mixed storage/VM traffic. |
| `RDMA-002` | planned | Define host RDMA storage client baseline | `RDMA-001`, NFS/NVMe-oF/iSER requirements | Cover `rdma-core`, OFED/DOCA alignment, NFS-RDMA, iSER, NVMe-RDMA, multipath, ZFS consumers, and telemetry gates for bare-metal and VM roles. |
| `RDMA-003` | scaffolded | Deploy OFED driver path for BlueField-2 and ConnectX-5 hosts | `RDMA-001`, `RDMA-002`, host PCI inventory | Issue #111. `nvidia_doca_ofed` now has read-only `lspci -Dnn` detection for NVIDIA/Mellanox `15b3` devices, BlueField-2/ConnectX-5 markers, required mlx5/RDMA module intent, RoCE validation command planning, and an apply-time detection gate. Live driver installation remains disabled by default and requires repo package input, kernel headers, and explicit custom-kernel acknowledgement. |
| `STOR-001` | planned | Model NVMe-oF/ZFS storage fabric datasets | `RDMA-001`, `RDMA-002`, QNAP/array inventory | Inventory dual-port NVMe-oF drives, ZFS dataset ownership, export protocols, IOPS/latency SLOs, and filesystem CRUD semantics before live mutation. |
| `STOR-002` | planned | Import coherent storage ADR reference set | `STOR-001`, `MEM-001`, `LLM-004` | Issue #112. Tomorrow action item: review `/tmp/docs/ADRs/RFC_Proj-Coherent-Storage-ADRs.2026-Q2.v1` and map storage, K/V cache, prompt-caching, scale-up, and scale-out decisions into repo ADRs and implementation tasks. |
| `HPC-001` | planned | Produce AI/ML HPC supercomputer hardware and network meta-analysis | workload taxonomy and reference designs | Compare upward trends across GPU, accelerator, CPU, memory, storage, and interconnect specialization. Output should separate verified facts from inference and map designs to workload classes. |
| `HPC-002` | scaffolded | Build SLURM-first workload scheduler pilot | `AAA-009`, `DNS-003`, `E2ET-002`, `BUILD-VM-001`, observability baseline | Issue #116. Initial `vm-slurm-controller`, `slurm-worker-node`, and `slurm_cluster` scaffolding exists for deterministic build, validation, GPU-test, and RDMA-test partitions. Live deployment remains gated on vaulted MUNGE/database secret delivery, DNS/IPAM records, NetBox node features, and a non-production controller VM. |
| `HPC-003` | planned | Add scheduler node health and feature inventory | `HPC-002`, NetBox host inventory, `RDMA-002` | Generate SLURM node features from NetBox and Ansible inventory: CPU generation, ISA flags, memory class, GPU model, RDMA capability, storage locality, and power-control method. Integrate NHC, E2ET, and observability. |
| `HPC-004` | planned | Evaluate HTCondor opportunistic overlay | `HPC-002`, stable AAA, scheduler telemetry | Test HTCondor only after SLURM can reliably run build and validation jobs. Target mixed, opportunistic, or federated workloads rather than replacing the first local scheduler. |
| `HPC-005` | planned | Import heterogeneous compute ADR reference set | `HPC-001`, `HPC-002`, `LLM-004` | Issue #113. Tomorrow action item: review `/tmp/docs/ADRs/RFC_Proj-Heterogeneous-Compute-ADRs.2026-Q2` and map heterogeneous compute, scale-up/scale-out, GPU/RDMA, scheduler, and FMT2 100GbE implications into repo ADRs and Kanban tasks. |

### Host E2ET And Release Acceptance

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `E2ET-001` | completed | Define RFC99 Host E2ET Acceptance Pipeline | K10 transient AAA validation evidence | `docs/HOST-E2ET-ACCEPTANCE.md` defines transient validation, reboot-durable acceptance, inventory/provisioning/boot/platform/network/storage/identity/service/performance gates, and p60/p80/p90/p95/p99 conformance tiers. |
| `E2ET-002` | completed | Implement host E2ET conformance report tooling | `E2ET-001`, service validator patterns | `scripts/host_e2et_conformance.py` and `host-e2et-conformance-report.yml` emit JSON, Markdown, and JUnit artifacts from host acceptance manifests. K10 has a sample blocked post-reboot manifest for the AAA durability gap. |
| `E2ET-003` | active | Apply E2ET pipeline to K10 rebuilt rootfs or disk install | `AAA-009`, `WS-006` | K10 E2ET manifest now reflects 2026-05-11 evidence: promoted rootfs boots from netboot, `aaa-domain-client` packages survive reboot, and post-boot FreeIPA/SSSD apply passes. Release remains blocked by unattended host-enrollment durability until disk install or secure first-boot age-encrypted FreeIPA OTP bundle apply generates `/etc/krb5.keytab` on the target. |
| `BUILD-VM-001` | active | Move X12AGAIN builds into disposable builder VMs | K10 Path B rebuild blocker | X12AGAIN must remain a stable resource provider until netboot is offloaded. Heavy Portage, stage4/stage5, rootfs, and Path B builds should run in disposable high-resource VMs with staged artifact promotion and rollback. See `docs/X12AGAIN-BUILDER-VM-ISOLATION.md`. |
| `BUILD-VM-002` | active | Move SUN99 netboot publishing off X12AGAIN | `BUILD-VM-001`, `WS-006` | Hasslehoff VM `1088`, `boot-sun99-netboot-099088.rfc1918.host` / `172.16.99.88`, is live with copied `/var/lib/netboot/path-b` and `/opt/gentoo-netboot/path-b/artifacts` content. HTTP `:8080` validates for K10 scripts/kernel/rootfs, TFTP validates `k10-ipxe.efi`, CCR2004 DHCP advertises `next-server=172.16.99.88`, and CCR2004 DNS has the netboot A/CNAME records. Readiness pass also validates Hasslehoff replacements for NetBox, FreeIPA, Prometheus, VictoriaMetrics, Grafana, Kibana, container-services HAProxy, Elasticsearch VIP, rsyslog VIP, and ntfy HTTPS. Remaining gates: reboot K10 and prove PXE -> iPXE -> rootfs without fetching from X12AGAIN, then stop local X12AGAIN QEMU guests, remove Path B bridges/taps, and run a post-shutdown delta backup. |

### Workstation VM Profiles

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `WS-001` | scaffolded | Define Stage5 workstation VM overlay | stable Stage4 VM base | `vm-workstation-nscde` profile, metadata, package list, host vars, SPICE QEMU wrapper, and source-install role are scaffolded on the workstation branch. |
| `WS-002` | active | Decide NsCDE packaging strategy | `WS-001`, upstream install review | First path is a controlled source-install role pinned to upstream tag `2.3`; a local overlay ebuild remains the preferred follow-up after live validation. |
| `WS-003` | completed | Build and validate workstation on on-host QEMU before Hasslehoff | `WS-001`, `WS-002` | Bootable NsCDE workstation QCOW was built on the on-host system and copied to Hasslehoff as `/var/lib/vz/template/cache/vm-workstation-nscde.qcow2`. |
| `WS-004` | active | Validate Hasslehoff GPU workstation VM | `WS-003`, `PNR-025`, `PNR-028` | VM `1094` is running at `172.16.99.94` with K1200 passthrough and serial console. NVIDIA R580 plus CUDA 12.9.1 are validated with `nvidia-smi` and `nvcc`; PiKVM Direct H.264 is validated through the managed `1280x720@60` NVIDIA Xorg display policy. Intel workstation support is now display-only by default, and the live VM completed the display-only package run with `xf86-video-intel`, Mesa, libdrm, libva, Vulkan, SLiM, NFS utils, and firmware installed. Stale Intel compute packages were depcleaned. |
| `WS-005` | scaffolded | Normalize cross-OS workstation session stack | `WS-001`, `WS-002` | `workstation_session_stack` models display managers, desktop environments, and window managers with OS-family task aliases for Gentoo, Debian/Devuan, FreeBSD, and Solaris-family systems. Package mutation is gated until each OS repository policy is finalized. |
| `WS-006` | active | Validate GMKtek K10 bare-metal Stage5 install before X12AGAIN | `WS-004`, K10 EFI handoff validation | K10 is on CSS326 `ge16`; PXE NIC slot `04:00:00`, MAC `84:47:09:5F:21:64`, static lease `172.16.99.156`. Native HTTPBoot stalled after DHCP, but generated PXE IPv4 with option 67 `k10-ipxe.efi`, `next-server=172.16.99.88`, OpenRC `netboot-tftp`, embedded iPXE, and `workstation-validation.ipxe` now validates through kernel `6.18.28-gentoo-dist`, RTL8125B firmware, promoted `g/rootfs.img`, SSH, and `aaa-domain-client` package presence after AP7901 outlet 6 reboot. Post-boot FreeIPA/SSSD enrollment passes; remaining durable Stage5 work is secure first-boot OTP bundle apply or disk-install enrollment, hostname/SSSD policy, final Portage/binpkg state, and disk-install validation. Do not treat `172.16.99.160` as K10 until the duplicate/unknown host state is resolved. |
| `WS-007` | active | Add netboot protocol-flow and boot-image manifest automation | `WS-006`, Jenkins build lane | Split netboot IP assignment mode from protocol flow. Model `ipxe-direct`, `pxe-to-ipxe`, `uefi-httpboot`, and `disabled`, with K10 set to `pxe-to-ipxe`. K10 now has a Jenkins-consumable boot-image manifest for kernel, dracut modules, firmware, command-line, rootfs URL, and future artifact hashes. |
| `WS-008` | pending | Resume Chonkers laptop iPXE/HTTPv4 validation after boot-media correction | `WS-007`, `PNR-030` | Chonkers is inventoried as `lap-sun99-chonkers.rfc1918.dev` on CSS326 `ge15`, AP7901 outlet 4, Realtek MAC `84:5C:31:A5:CF:51`. Current blocker is the installed NVMe hijacking boot; retry after blank/replacement NVMe or boot-order correction. |
| `WS-009` | planned | Reimage X12AGAIN as LOX workstation plus hypervisor host | `WS-006`, `AAA-009`, backup completion | Target profile includes workstation Xorg/NsCDE, AMDGPU policy, Optane PMEM driver/kmod/scripts, hypervisor overlay, NFS/RDMA storage clients, observability, rsyslog, AAA, and a backout plan from the preserved liveiso/off-host backups. |

## Medium-Term Work

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `MT-001` | pending | Normalize repo publication naming across all Stage4/Stage5 combinations | binpkg repo stable | Avoid mixing split-usr, merged-usr, CPU profile, or role-specific binpkgs. |
| `MT-002` | pending | Add repo-side automation for wiki publication | docs source stable | `docs/wiki/` remains source; `<repo>.wiki.git` is deployment target. |
| `MT-003` | pending | Add post-install assertion stages | installer stable | Cover ZFS pools, mounts, boot assets, SSH, and service state. |
| `MT-004` | pending | Aggregate multi-host control-flow logs | JSONL callback stable | Needed for concurrent VM and bare-metal provisioning. |
| `MT-005` | pending | Revisit OpenMP/toolchain policy after first image publish | `CP-006` | Current base image disables OpenMP pragmatically. |

## Completed Milestones

- Path B `container-services` VM profile and Podman runtime validation
- tmpfs-backed memory drive support for fast ephemeral VM work
- modular cloud-init definitions for VM and bare-metal profiles
- Stage4/Stage5 terminology normalized across profile/package layers
- merged-usr Stage4 variant for container rootfs work
- Jenkins and distcc builder-farm scaffolding
- FreeIPA, SSSD, and FreeRADIUS scaffolding
- observability, telemetry, SNMP, IPMI, and Redfish scaffolding
- Path B `vm-binpkg-repository` workflow
- live binpkg repository VM at `10.9.8.90`
- binpkg sync helper and watch-sync helper

## Rule for New TODO Items

A new TODO must include:

- action-oriented wording
- dependency or blocker reference
- current status
- clear removal condition
