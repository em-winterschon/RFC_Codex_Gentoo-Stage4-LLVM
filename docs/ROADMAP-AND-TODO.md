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

Dependency:

- next dependency is publishing validated service-layer images and finishing the
  `rsyslog_collector` service layer.

## Short-Term Work

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `ST-001` | pending | Add a repo-native mounted-target builder launcher | `CP-003` | Should enforce high-performance defaults and binpkg sync by default. |
| `ST-002` | active | Reduce base-container closure | `CP-005` | Active path now starts from official stage3 and layers only Stage5 service-container packages. |
| `ST-003` | pending | Add explicit binpkg cleanup/retention policy | binpkg VM stable | Decide retention by repo ID, profile generation, and disk pressure. |
| `ST-004` | completed | Validate GHCR publish workflow end-to-end | `CP-006` | Base image published to GHCR; VM-side Podman was too slow, so host-side `crane` pushed the docker archive and recorded the registry digest. |
| `ST-005` | pending | Add build metrics as CI artifacts | `CP-003` | Use `scripts/export_build_metrics.py` output in Jenkins later. |
| `ST-006` | active | Reduce dependency-tree failure blast radius | `CP-003` | Default to the standard stage3 base for the first image; keep hardened source-first work as a later, isolated track. |
| `ST-007` | pending | Add rsyslog as a service-container layer | `CP-005` | `rsyslog` is intentionally out of the first base image because its same-transaction `--root` build cannot see `libestr` through pkg-config. |
| `ST-008` | active | Wire service layers to the published base image | `CP-006` | `container-service-base-image.yml` defines GHCR base-image provenance and app build defaults; container hosts render `/etc/container-services/base-image.yml`; `service-layers.yml` tracks package-backed and upstream-image service candidates. |
| `ST-009` | completed | Add service-layer build automation | `ST-008` | `run-container-service-layer-build-pathb.sh` can build `nginx`, `haproxy`, and `rsyslog_collector` service images with per-service package lists and binpkg repo IDs. |
| `ST-010` | active | Validate package-backed service images | `ST-009` | `nginx` and `haproxy` images built, smoke-tested, published to GHCR, and synced to service binpkg repos; `rsyslog_collector` remains next. |

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
| `AAA-001` | scaffolded | Validate FreeIPA server/client roles on fresh VMs | basic VM provisioning stable | Keep SSSD client behavior compatible with Gentoo/OpenRC. |
| `AAA-002` | scaffolded | Validate FreeRADIUS against LDAP/FreeIPA backend | `AAA-001` | Required for switches, WAPs, routers, and firewalls. |
| `AAA-003` | pending | Define optional TACACS+ bridge | `AAA-002` | Only needed for Cisco devices if RADIUS is insufficient. |
| `AAA-004` | pending | Map RBAC policy to SSH keys, VPN users, switches, smartcards | `AAA-001` | Use domain policy as the source of truth. |

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
| `LOG-002` | pending | Validate centralized rsyslog receiver container | container-services stable | Should receive from VMs, metal hosts, and containers. |
| `LOG-003` | pending | Validate 3-node Elasticsearch VM profile | VM provisioning stable | Must include load-balanced access path. |
| `LOG-004` | pending | Validate Kibana VM profile | `LOG-003` | Connect to Elasticsearch VIP. |
| `LOG-005` | pending | Validate APM container profile | `LOG-003`, container-services stable | Feed traces into Elasticsearch cluster. |

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
