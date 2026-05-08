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
  - direct nginx ingress on `10.9.8.89:8080` and HAProxy ingress on
    `10.9.8.89:80` return HTTP `200`
  - rsyslog TCP receive on `10.9.8.89:514` works
  - HAProxy Elasticsearch test VIP on `10.9.8.92:9200` reaches the test
    Elasticsearch backend

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
| `ST-013` | completed | Validate post-outage installed-disk container-services redeploy | `ST-012` | Host-side checks passed for `10.9.8.89:8080`, `10.9.8.89:80`, `10.9.8.89:514/tcp`, and `10.9.8.92:9200`. |
| `ST-014` | pending | Replace `ntfy` upstream-image dependency | `ST-013` | Build a package-backed Stage5 image or add a controlled archive preload path so redeploys do not depend on Docker Hub availability. |
| `ST-015` | completed | Add explicit image pull/preload policy to runtime app profiles | `ST-013` | Generated Podman wrappers emit `--pull`; package-backed GHCR profiles default to `missing`, and the live Path B `ntfy` override uses `never` while the upstream-image path is blocked. |
| `ST-016` | active | Safe-move container-services workload to Hasslehoff Stage4 VM | `PNR-014`, `ST-013` | Staging VM `svc-container-services-safe-move-01` is live at `172.16.99.89`; Podman/Buildah/Skopeo bootstrap completed; rsyslog, nginx, HAProxy, and ntfy are running. ntfy is exposed on service VIP `172.16.99.96` as `msg-sun99-ntfysys-099096.rfc1918.host` with RouterOS, Hetzner, and NetBox tracking. Elasticsearch backend dependency remains blocked by missing routing from `172.16.99.89` to the `10.9.8.91` / `10.9.8.92` path. |

## Proxmox, NetBox, And RouterOS

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `PNR-001` | active | Bootstrap Codex SSH access to Proxmox, NetBox jail host, and CCR2004 RouterOS | operator-provided addresses and credentials | Proxmox SSH/API token and CRS354 vaulting are complete; Hasslehoff inventory validates through Ansible. NetBox API root is reachable at `172.16.99.62`; CCR2004 auth remains next. |
| `PNR-002` | completed | Confirm management subnet and NetBox API access | `PNR-001` | Management subnet is tracked as `172.16.99.0/24`; replacement Stage4 VM `1062` serves NetBox `v4.5.9` at `172.16.99.62`. |
| `PNR-003` | completed | Import draft Path B, VIP, container, OOB, and builder prefixes into NetBox | `PNR-008` | `scripts/netbox_seed_local_network.py` created `42` conservative fabric objects from the local network fabric inventory. |
| `PNR-007` | completed | Deploy NetBox `v4.5.9` on Stage4 VM `1062` | `PNR-002` | NetBox is live under OpenRC with PostgreSQL, Redis, gunicorn, RQ worker, nginx, and API token validation. |
| `PNR-008` | completed | Install essential NetBox operational integrations before writes | `PNR-007` | `pynetbox`, `netbox-agent`, `netbox-sync`, `netbox-tools`, `devicetype-library`, and `Device-Type-Library-Import` are isolated under `/opt/netbox-essentials`; the initial device-type import loaded `1924` device types. |
| `PNR-009` | completed | Inventory additional clusters and datacenters into NetBox | `PNR-010` | RFC99, SUN99, YKS99, and FMT2 structured intake applied live with pre/post snapshots and idempotence validation. |
| `PNR-010` | completed | Add structured NetBox inventory intake and apply workflow | `PNR-003` | Validator, dry-run/apply script, Ansible wrappers, local baseline file, live apply, idempotence pass, and post-apply snapshot are complete. |
| `PNR-011` | completed | Convert RFC99/SUN99/FMT2 host/IP/MAC source file into structured NetBox intake | `PNR-010` | `/tmp/rfc99-sun99-host-networking.md` is archived under operator-private storage; sanitized `rfc99`, `sun99`, `yks99`, and `fmt2` intake files validate locally and were applied live on 2026-05-03. |
| `PNR-013` | active | Use NetBox to drive provisioning inventory and IPAM maps | `PNR-011`, `DNS-003` | Action plan and exporter are in place. Current live unfiltered export produces `7` standalone IP bootstrap hosts from `12` NetBox IP records; VM/device primary-IP ownership tags remain next. |
| `PNR-014` | active | Prepare generic Proxmox Stage4 service VM creation path | `PNR-013` | Dry-run-first VM creator is added for Hasslehoff service VMs; live apply requires `PROXMOX_APPLY=1` and existing VM replacement requires `PROXMOX_REPLACE=1`. |
| `PNR-015` | active | Track temporary Hasslehoff staging VMs in NetBox before live cutover | `PNR-014` | `svc_container_services_safe_move_01` is in NetBox/IPAM as planned with DNS name `svc-container-services-safe-move-01.rfc1918.host` and IP `172.16.99.89/24`; DNS plan is dry-run only. |
| `PNR-012` | completed | Replace failed OPNsense path with RouterOS after NetBox staging | `PNR-011` | CCR2004 is the active gateway on RouterOS package and RouterBOARD firmware `7.22.2`; WAN DHCP, default route, DNS, NAT, HTTPS/API-SSL management, hardened surface, and remote syslog validated after upgrade. |
| `PNR-017` | active | Rebuild CRS309 as RouterOS 10GbE spine aggregation switch | `PNR-012` | CRS309 is live on RouterOS package and RouterBOARD firmware `7.22.2`; port conflict normalized by assigning CRS354 LACP to CRS309 `sfp-sfpplus2/3`, Hasslehoff QLogic QL41232HOCU LACP to CRS309 `sfp-sfpplus4/5`, CSS326 to `sfp-sfpplus8`, and CCR2004 gateway uplink to `sfp-sfpplus1`. Remaining work is cabling/validating CSS326 `sfp1` to CRS309 `sfp-sfpplus8` and the Hasslehoff QLogic LACP pair. |
| `PNR-018` | completed | Standardize CRS354 distribution-switch inventory and CRS309 LACP uplink | `PNR-017` | Live CRS354 snapshot archived under `/root/operator-private/routeros/crs354/20260504T194533Z`; CRS309/CRS354 LACP validated active on 2026-05-04 with both members at `10Gbps`; NetBox intake models management on `ether49`, CRS309 LACP on `sfp-sfpplus1/2`, QNAP TS435XEU DAC LACP on `sfp-sfpplus3/4`, and disconnected QSFP RoCE-v2 reservations. |
| `PNR-019` | completed | Normalize CSS326 SwOS access-switch state and backup collection | `PNR-017` | CSS326 is reachable at `172.16.99.6`, identity `sw-mgmt-mkcss326`, latest SwOS `2.18.1751448030`, SNMP enabled, and Hasslehoff LACP active on `ge5/ge6`; `scripts/collect-mikrotik-swos-state.py` captures SwOS state and `backup.swb` to operator-private storage. SwOS has no observed syslog destination support, so monitoring is SNMP plus snapshots. |
| `PNR-020` | active | Convert RouterOS spine/distribution changes into idempotent Ansible roles | `PNR-017`, `PNR-018` | Render-only role and playbook now emit CRS309/CRS354 RSC plus manifest for LACP and stale-state cleanup. Read-only RouterOS SSH snapshot automation is in place and validated for CRS309. Remaining work is fixture-backed RouterOS render tests, serial-backed CRS354 collection, and explicit serial-gated apply handling. |
| `PNR-021` | completed | Apply latest local fabric intake to live NetBox | `PNR-019`, `PNR-020` | Snapshot `nb-pre-fabric-refresh-20260504` was created before write. NetBox fabric refresh created CRS309 spine, QNAP archive storage, and CCR2004 gateway objects, then idempotence completed with `0` creates and `0` updates before snapshot `nb-post-fabric-refresh-20260504`. |
| `PNR-022` | pending | Deep-model NetBox interfaces, LAGs, optics, and cables | `PNR-021` | Current intake covers devices, prefixes, management IPs, clusters, and VIPs. Next DCIM step is interface-level records for CRS309/CRS354/CSS326/Hasslehoff/QNAP with cable and optic metadata. |
| `PNR-023` | pending | Add Hasslehoff IPMI and Redfish credentials to Ansible Vault | `PNR-016`, vault workflow | Operator provided temporary credential source at `/tmp/hasslehoff-ipmi-creds.tmp`; import into encrypted local-network vault as `vault_hasslehoff_ipmi_*` / `vault_hasslehoff_redfish_*`, validate Redfish auth against `https://ipmi-verwalterin.rfc1918.host/redfish/v1/`, then remove the plaintext temp file. |
| `PNR-024` | scaffolded | Add Redfish and Dell iDRAC BMC control-plane roles | `PNR-023` for live Hasslehoff validation | `bmc_redfish` and `bmc_idrac` roles are scaffolded with read-only defaults and explicit mutation gates for power, boot override, and virtual media workflows. Live Dell R630/R730xd and IBM LC922 validation waits for SD-WAN/L2 reachability and vaulted BMC credentials. |
| `PNR-025` | active | Track Hasslehoff GPU compute and passthrough host policy | workstation VM profile | Hasslehoff is in `gpu_compute`; the `gpu_host_policy` role renders `nouveau`, `nvidiafb`, and Hasslehoff-specific `snd_hda_intel` blacklist controls, vfio-pci K1200 ID binding, a GRUB drop-in, and optional Proxmox `/etc/kernel/cmdline` handling. |
| `PNR-026` | scaffolded | Add gated Proxmox host maintenance upgrade workflow | `PNR-016` | `proxmox_host_upgrade` is plan-only by default, validates the PVE8/bookworm lane, and creates pre/post recursive ZFS snapshots around apt maintenance when explicitly applied. |
| `PNR-027` | scaffolded | Add gated NVIDIA DOCA/OFED host-driver workflow | `PNR-026`, RoCE fabric | `nvidia_doca_ofed` requires explicit repo package input, matching kernel headers, and a custom-kernel acknowledgement before installing on a Proxmox kernel. |
| `PNR-028` | active | Bring up Hasslehoff QLogic LACP and workstation VM high-speed network test | `PNR-020`, `PNR-025` | CRS309 `bond-hasslehoff-qlogic`, Hasslehoff `bond-qlogic0`, and `vmbr-qlogic0` are live. SR-IOV is blocked because the QLogic functions expose no SR-IOV capability; workstation VM `1094` uses tagged virtio NICs on `vmbr-qlogic0` as the fallback. |
| `PNR-029` | completed | Normalize RouterOS serial command automation for CRS309 | `PNR-020` | Added `scripts/routeros-serial-command.py` with VT100/ANSI answerback handling for RouterOS `ESC Z` terminal-identification probes; live read-only CRS309 identity command validated. |
| `PNR-030` | active | Promote K10 and AP7901 PDU operational discoveries into NetBox | `PNR-010`, `WS-006`, PDU vault import | Live NetBox API is reachable at `172.16.99.62`, but K10 `172.16.99.156` and AP7901 `172.16.99.241` returned zero device/IP matches before this intake update. Repo-safe local intake now includes K10 device/interface/IPAM/switchport metadata and AP7901 non-secret inventory/outlet mapping; live NetBox apply remains intentionally pending. |
| `PNR-031` | pending | Add NetBox power-chain modeling for PDU outlet to host relationships | `PNR-030`, power-device model support confirmed | Track AP7901 outlet 6 label `host_gmktec_k10` to the K10 power target without storing SNMP secrets in NetBox. |
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

### MCP And Project Management Control Plane

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `MCP-001` | active | Audit MCP server/tool/plugin candidates before installation | MCP control-plane registry | First audit pass ranks Context7, NetBox, Grafana read-only, Hugging Face, Trac, Jenkins, Kubernetes/OpenShift, and Proxmox. Removal condition: first smoke-test candidates have pinned versions, read-only credentials, and recorded outputs. |
| `MCP-002` | pending | Run read-only MCP smoke tests for low-risk candidates | `MCP-001`, vault token availability | Start with Context7, NetBox read-only token, Grafana `--disable-write`, and Hugging Face. Removal condition: smoke-test logs and allowed tool lists are stored in docs or Trac. |
| `MCP-003` | pending | Build or fork-gate a read-only Trac MCP wrapper | `PM-001`, Trac service live | `nerpatech/trac-mcp-server` exposes delete and batch mutation tools. Removal condition: agent-visible Trac MCP tool list excludes `ticket_delete`, `ticket_batch_delete`, `wiki_delete`, `milestone_delete`, and all write tools until promoted. |
| `PM-001` | active | Evaluate Trac as the Kanban, change-control, wiki, and issue plane | Trac service scaffold, MCP audit | Current decision: proceed with Trac service design but keep MCP read-only. Removal condition: Trac VM/container profile, HAProxy/TLS path, backup policy, workflow fields, and read-only MCP smoke-test plan exist. |
| `PM-002` | pending | Define GitHub-to-Codeberg mirror and future repo rename plan | PR/branch state stable, vault tokens | Track candidate repo name such as `rfc1918-platform-fabric`, remote names, branch protections, wiki sync, token vaulting, and rollback. |

### Morning SITREP 2026-05-08 Execution

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `MORN-001` | active | Promote NetBox-driven inventory as the provisioning source of truth | NetBox API, DNS report, inventory intake | Removal condition: NetBox export can generate host bootstrap inventory, DNS targets, and service validation targets without manual copy/paste. |
| `MORN-002` | active | Define common base system services for all hosts, VMs, and containers | Stage5 profile taxonomy | Removal condition: base profile declares rsyslog, node exporter, ntfy alerting, SSSD/AAA client, NTP/chrony, TLS trust, package repo, and health-check policy. |
| `MORN-003` | pending | Define service-role overlay service contracts | `MORN-002` | Removal condition: each service profile declares packages, ports, SLO checks, HAProxy entries, logs, metrics, backup policy, and dependencies. |
| `MORN-004` | active | Advance centralized AAA to eliminate SSH key sprawl | FreeIPA/SSSD/RADIUS baseline | Removal condition: non-root SSH auth is centralized, network devices use RADIUS where possible, and TACACS+ is explicitly deferred or scoped. |
| `MORN-005` | active | Evaluate Trac control-plane rollout | `PM-001`, `MCP-003` | Removal condition: Trac can receive MCP read-only context safely and hold Kanban/change-control state. |
| `MORN-006` | pending | Plan GitHub-to-Codeberg mirror and repo rename | `PM-002` | Removal condition: mirror sync and rollback plan are documented with vaulted token references. |
| `MORN-007` | active | Keep MCP tools read-only until promoted | `MCP-001` | Removal condition: control-plane registry, audit, and smoke-test results exist for each candidate before any write-capable credential is issued. |
| `MORN-008` | pending | Prepare FMT2 discovery once BigNetwork L2 is active | BigNetwork transport | Removal condition: FMT2 devices and prefixes are discovered, evidence-tagged, and staged for NetBox apply. |

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
| `AAA-004` | active | Map RBAC policy to SSH keys, VPN users, switches, smartcards | `AAA-001` | Initial `codex-admin`, `linux-admin`, `network-readonly`, and RADIUS validation mappings exist; next step is enrolling real devices and hosts. |
| `AAA-005` | active | Enroll APC PDUs, APC ATS, and UPS management cards into central RADIUS auth | `AAA-002`, `OBS-004`, power-device inventory | Scope includes APC AP7901/AP7902 PDUs, AP4450 ATS, AP9631/AP9641 UPS cards, and any compatible CyberPower/Eaton management modules. First target is the AP7901 at `172.16.99.241` after non-secret NetBox inventory exists. Preserve local break-glass accounts, test one low-risk device first, and document vendor-specific RADIUS attributes before bulk rollout. |

### Observability, Logs, And Telemetry

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `OBS-001` | scaffolded | Validate baseline `node_exporter` on machine/VM/container profiles | VM roles stable | Should be common across Stage5 profile types. |
| `OBS-002` | scaffolded | Validate Prometheus and Grafana VM profiles | `OBS-001` | Prometheus scrape config intentionally remains raw/flexible. |
| `OBS-003` | scaffolded | Validate IPMI and Redfish exporter containers | container-services stable | Needed for builder farm and chassis telemetry. |
| `OBS-004` | scaffolded | Validate SNMP modules for UPS, ATS, PDU, and OOB devices | observability network access | Start conservative, then tune vendor OIDs per device. |
| `OBS-005` | pending | Add service-specific dashboards and alert thresholds | `OBS-002`, `OBS-003`, `OBS-004` | Avoid fake thresholds before real device walks. |

### Logging And Search

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `LOG-001` | scaffolded | Validate rsyslog client templating everywhere | base profiles stable | Base rsyslog role now supports remote forwarding. |
| `LOG-002` | active | Validate centralized rsyslog receiver container | container-services stable | Live TCP receive is validated on `10.9.8.89`; HAProxy exposes the Elasticsearch test VIP at `10.9.8.92:9200`; end-to-end rsyslog-to-index validation remains pending. |
| `LOG-003` | pending | Validate 3-node Elasticsearch VM profile | VM provisioning stable | Must include load-balanced access path. |
| `LOG-004` | pending | Validate Kibana VM profile | `LOG-003` | Connect to Elasticsearch VIP. |
| `LOG-005` | pending | Validate APM container profile | `LOG-003`, container-services stable | Feed traces into Elasticsearch cluster. |

### FMT2 / SFO-200 Recovery

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `FMT2-001` | completed | Capture legacy FMT2/SFO-200 wiki as evidence | old wiki clone available | Evidence index lives in `docs/FMT2-INFRA-UPGRADE-PLANNING.md`; source repo is `/opt/repos/remote/blumens/wikis-mkdocs/blumen-arch.wiki` at observed commit `bd5b71b`. |
| `FMT2-002` | active | Validate FMT2 transport path from RFC99/SUN99 | BigNetwork SDN or compatibility OpenVPN VM | BigNetwork is the first implementation path. Devuan smoke-test netboot assets and `bignetwork_edge` role scaffolding exist; Forge/Codexian BigNetwork token import is vaulted. Preferred steady-state is re-onboarding the local NanoPi R6S Edge Lite as a transparent L2 bridge; removal condition is repeatable bidirectional reachability to one FMT2 management prefix plus DNS resolution for legacy monitoring names. |
| `FMT2-003` | pending | Promote verified FMT2 prefixes, racks, and devices into NetBox | `FMT2-001`, `FMT2-002` | Import prefixes and racks first, then routers/switches, then hosts/BMCs, then services. All records should be tagged to the old wiki source commit until independently verified. |
| `FMT2-004` | pending | Reconnect FMT2 Check_MK to managed observability | `FMT2-002`, `FMT2-003` | Confirm `app-sfo200-monitoring-9927.vernetzen.io`, `/vernetzen/`, API endpoint, agents path, and return routing before adding targets or alert dependencies. |

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

### Platform Service Profiles

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `PSP-001` | planned | Add single-node OpenShift VM profile and `openshift-service-profile` | Proxmox service VM factory, NetBox IPAM, storage/network plan | Treat Gentoo/OpenRC as the hypervisor and automation fabric. Use vendor-supported OpenShift/OKD node OS expectations inside the VM unless a supported Gentoo path is proven. Removal condition: profile, VM manifest, DNS/IPAM model, install plan, SLO checks, and backout plan exist. |
| `PSP-002` | planned | Add single-node OpenStack VM profile and `openstack-service-profile` | Proxmox service VM factory, storage backend plan, identity and TLS policy | Review whether native Gentoo/OpenRC OpenStack service management is maintainable. If not, run OpenStack as an appliance VM while our fabric manages network, storage, DNS, TLS, auth, logs, metrics, and backups. Removal condition: feasibility decision, service inventory, VM profile, and install/backout plan exist. |
| `PSP-003` | planned | Review Red Hat oriented platform assumptions against Gentoo/OpenRC policy | `PSP-001`, `PSP-002`, package and service research | Document required adaptations for systemd-heavy components, service supervision, SELinux/podman/cri-o expectations, kernel modules, networking, storage classes, TLS, AAA, and observability. Removal condition: design doc decides supported path for each platform. |

### Workstation VM Profiles

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `WS-001` | scaffolded | Define Stage5 workstation VM overlay | stable Stage4 VM base | `vm-workstation-nscde` profile, metadata, package list, host vars, SPICE QEMU wrapper, and source-install role are scaffolded on the workstation branch. |
| `WS-002` | active | Decide NsCDE packaging strategy | `WS-001`, upstream install review | First path is a controlled source-install role pinned to upstream tag `2.3`; a local overlay ebuild remains the preferred follow-up after live validation. |
| `WS-003` | completed | Build and validate workstation on on-host QEMU before Hasslehoff | `WS-001`, `WS-002` | Bootable NsCDE workstation QCOW was built on the on-host system and copied to Hasslehoff as `/var/lib/vz/template/cache/vm-workstation-nscde.qcow2`. |
| `WS-004` | active | Validate Hasslehoff GPU workstation VM | `WS-003`, `PNR-025`, `PNR-028` | VM `1094` is running at `172.16.99.94` with K1200 passthrough and serial console. NVIDIA R580 plus CUDA 12.9.1 are validated with `nvidia-smi` and `nvcc`; PiKVM Direct H.264 is validated through the managed `1280x720@60` NVIDIA Xorg display policy. Intel workstation support is now display-only by default, and the live VM completed the display-only package run with `xf86-video-intel`, Mesa, libdrm, libva, Vulkan, SLiM, NFS utils, and firmware installed. Stale Intel compute packages were depcleaned. |
| `WS-005` | scaffolded | Normalize cross-OS workstation session stack | `WS-001`, `WS-002` | `workstation_session_stack` models display managers, desktop environments, and window managers with OS-family task aliases for Gentoo, Debian/Devuan, FreeBSD, and Solaris-family systems. Package mutation is gated until each OS repository policy is finalized. |
| `WS-006` | active | Validate GMKtek K10 bare-metal Stage5 install before X12AGAIN | `WS-004`, K10 EFI handoff validation | K10 is on CSS326 `ge16`; PXE NIC slot `04:00:00`, MAC `84:47:09:5F:21:64`, static lease `172.16.99.156`. Native HTTPBoot stalled after DHCP, but PXE IPv4 with option 67 `k10-ipxe.efi`, `next-server=172.16.99.108`, and TFTP root `/var/lib/netboot/path-b` now reaches iPXE, loads the kernel and patched RTL8125B initramfs via `initrd=initrd.magic`, fetches `g/rootfs.img` using static dracut IP, mounts `LiveOS_rootfs`, and reaches the Gentoo login prompt. Next removal condition is running the Stage5 workstation installer workflow and recording final Portage/binpkg state. Do not treat `172.16.99.160` as K10 until the duplicate/unknown host state is resolved. |
| `WS-007` | active | Add netboot protocol-flow and boot-image manifest automation | `WS-006`, Jenkins build lane | Split netboot IP assignment mode from protocol flow. Model `ipxe-direct`, `pxe-to-ipxe`, `uefi-httpboot`, and `disabled`, with K10 set to `pxe-to-ipxe`. K10 now has a Jenkins-consumable boot-image manifest for kernel, dracut modules, firmware, command-line, rootfs URL, and future artifact hashes. |

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
