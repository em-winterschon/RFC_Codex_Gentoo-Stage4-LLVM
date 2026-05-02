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
| `ST-012` | completed | Live-validate generated Podman service wrappers on the container-services VM | `ST-011` | Initial chroot/live validation passed for `rsyslog-collector`, `nginx`, `ntfy`, and `haproxy`. Post-outage installed-disk redeploy currently validates `rsyslog-collector`, `nginx`, and `haproxy`; `ntfy` is blocked on upstream image acquisition. |
| `ST-013` | completed | Validate post-outage installed-disk container-services redeploy | `ST-012` | Host-side checks passed for `10.9.8.89:8080`, `10.9.8.89:80`, `10.9.8.89:514/tcp`, and `10.9.8.92:9200`. |
| `ST-014` | pending | Replace `ntfy` upstream-image dependency | `ST-013` | Build a package-backed Stage5 image or add a controlled archive preload path so redeploys do not depend on Docker Hub availability. |
| `ST-015` | completed | Add explicit image pull/preload policy to runtime app profiles | `ST-013` | Generated Podman wrappers emit `--pull`; package-backed GHCR profiles default to `missing`, and the live Path B `ntfy` override uses `never` while the upstream-image path is blocked. |

## Proxmox, NetBox, And RouterOS

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `PNR-001` | active | Bootstrap Codex SSH access to Proxmox, NetBox jail host, and CCR2004 RouterOS | operator-provided addresses and credentials | Proxmox SSH/API token and CRS354 vaulting are complete; Hasslehoff inventory validates through Ansible. NetBox API root is reachable at `172.16.99.62`; CCR2004 auth remains next. |
| `PNR-002` | completed | Confirm management subnet and NetBox API access | `PNR-001` | Management subnet is tracked as `172.16.99.0/24`; replacement Stage4 VM `1062` serves NetBox `v4.5.9` at `172.16.99.62`. |
| `PNR-003` | completed | Import draft Path B, VIP, container, OOB, and builder prefixes into NetBox | `PNR-008` | `scripts/netbox_seed_local_network.py` created `42` conservative fabric objects from the local network fabric inventory. |
| `PNR-007` | completed | Deploy NetBox `v4.5.9` on Stage4 VM `1062` | `PNR-002` | NetBox is live under OpenRC with PostgreSQL, Redis, gunicorn, RQ worker, nginx, and API token validation. |
| `PNR-008` | completed | Install essential NetBox operational integrations before writes | `PNR-007` | `pynetbox`, `netbox-agent`, `netbox-sync`, `netbox-tools`, `devicetype-library`, and `Device-Type-Library-Import` are isolated under `/opt/netbox-essentials`; the initial device-type import loaded `1924` device types. |
| `PNR-009` | active | Inventory additional clusters and datacenters into NetBox | `PNR-010` | Local structured intake is live; next work should add one site/cluster at a time and validate with NetBox dry-run/apply playbooks before writing. |
| `PNR-010` | completed | Add structured NetBox inventory intake and apply workflow | `PNR-003` | Validator, dry-run/apply script, Ansible wrappers, local baseline file, live apply, idempotence pass, and post-apply snapshot are complete. |
| `PNR-004` | planned | Export current QEMU RouterOS Path B config as rollback | `PNR-001` | Must happen before CCR2004 mutations. |
| `PNR-005` | planned | Apply CCR2004 management-only baseline | `PNR-004` | Routing migration waits until management access is repeatable. |
| `PNR-006` | planned | Move Path B gateway functions to CCR2004 | `PNR-005` | Validate DNS, internet egress, binpkg access, and HAProxy VIP ingress before retiring QEMU RouterOS. |

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
| `AAA-004` | active | Map RBAC policy to SSH keys, VPN users, switches, smartcards | `AAA-001` | Initial `codex-admin`, `linux-admin`, `network-readonly`, and RADIUS validation mappings exist; next step is enrolling real devices and hosts. |

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

### LLM API And RAG Services

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `LLM-001` | planned | Reserve VLAN, VIP, and NetBox model space for LLM/RAG service traffic | network fabric source of truth | Track Ollama, OpenWebUI, vLLM, SourceBot, API proxy, provider pools, GPU hosts, and RAG data paths without blocking current fabric work. |
| `LLM-002` | pending | Scaffold LLM API proxy service role | `LLM-001`, container-services stable | Proxy must route across local vLLM providers and external APIs such as OpenAI. |
| `LLM-003` | pending | Scaffold OpenWebUI and Ollama service definitions | `LLM-001`, GPU service inventory access | Operator already has separate deployment automation; import only after Codex access is available. |
| `LLM-004` | pending | Scaffold RAG ingestion, embedding, and retrieval pipeline roles | `LLM-002`, `LLM-003` | Keep metrics, logs, provider routing, and service VIPs explicit. |

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
