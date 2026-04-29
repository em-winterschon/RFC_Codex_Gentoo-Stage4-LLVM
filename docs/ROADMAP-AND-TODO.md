# Roadmap and TODO

This page tracks concrete next work, dependencies, and current blockers.

## Critical Path

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `CP-001` | blocked | Fix `sys-apps/coreutils-9.10-r1` overlay patch failure | current failed build logs | `coreutils-9.5-skip-readutmp-test.patch` no longer applies in `src_prepare`. |
| `CP-002` | pending | Validate `coreutils` in isolation | `CP-001` | Run a narrow emerge/ebuild prepare test before another full base-container rerun. |
| `CP-003` | pending | Restart base-container build against the binpkg repo | `CP-002` | Use the repository at `10.9.8.90:8088` and keep binpkg publication enabled. |
| `CP-004` | pending | Keep successful packages synced during the rerun | `CP-003` | Prefer `--binpkg-sync-remote`; otherwise use `watch-sync-binpkgs-to-repo.sh --watch-pid`. |
| `CP-005` | pending | Validate finished local image and tarball | `CP-003` | Target image: `localhost/gentoo-stage4-llvm-clang-hardened:latest`. |
| `CP-006` | pending | Push validated image to GHCR | `CP-005` | Token source exists on-host at `~/.ssh/codex.d/tokens/GHCR_TOKEN`. |

## Active Infrastructure State

### Binpkg Repository

Current repo:

- ID:
  - `stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`
- VM:
  - `binpkg-repository`
- address:
  - `10.9.8.90`
- HTTP endpoint:
  - `http://10.9.8.90:8088/stage4-hardened-llvm-merged_usr__stage5-service_container-gentoo_stage4_llvm_clang_hardened__amd64__x86_64_v2_generic`
- last observed package index:
  - `256` package records
  - `258` files

Dependency:

- base-container reruns should use this binhost before building from source.

### Container-Services Builder

Current state:

- VM:
  - `container-services`
- address:
  - `10.9.8.89`
- last build state:
  - failed at `248 / 471`
  - failing atom: `sys-apps/coreutils-9.10-r1::gentoo-stage4-image-fixes`
- synced build artifacts:
  - final watch-sync completed after failure

Dependency:

- no new full rerun should start until `CP-001` and `CP-002` are complete.

## Short-Term Work

| ID | Status | Task | Depends On | Notes |
| --- | --- | --- | --- | --- |
| `ST-001` | pending | Add a repo-native mounted-target builder launcher | `CP-003` | Should enforce high-performance defaults and binpkg sync by default. |
| `ST-002` | pending | Reduce base-container closure | `CP-005` | Move from "mini system build" toward runtime-only image once the first image exists. |
| `ST-003` | pending | Add explicit binpkg cleanup/retention policy | binpkg VM stable | Decide retention by repo ID, profile generation, and disk pressure. |
| `ST-004` | pending | Validate GHCR publish workflow end-to-end | `CP-006` | Include token auth, labels, and image promotion policy. |
| `ST-005` | pending | Add build metrics as CI artifacts | `CP-003` | Use `scripts/export_build_metrics.py` output in Jenkins later. |

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
