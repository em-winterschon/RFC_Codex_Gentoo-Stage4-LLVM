# RFC1918 Infrastructure Control Plane

## Purpose

This document defines the first repo-safe control-plane contract for the RFC1918
infrastructure lane. The target is a single source-controlled path that ties
Jenkins, SLURM, DistCC, Nexus OSS, CA package publication, and NetBox-driven DNS
propagation together without allowing ad-hoc local package builds or untracked
DNS mutation.

Tracked work:

- #215 - P0 PR conflict and merge-readiness burn-down.
- #216 - RFC99 internal CA packages and repository publication pipeline.
- #217 - Nexus OSS internal repository host and repo definitions.
- #218 - NetBox-to-Hetzner-to-CoreDNS split-horizon DNS propagation controls.
- #220 - Standardized Ansible Vault loading for live infra workflows.

## Non-negotiable controls

1. **NetBox remains authoritative** for hostnames, IPs, and service ownership.
2. **The repository main branch must not drift** from NetBox before live DNS or
   host mutation runs. A workflow may produce drift reports, but it must not
   silently apply over drift.
3. **Vault must be loaded through the repo wrapper** (`scripts/with-ansible-vault-env.sh`)
   before any playbook consumes live credentials.
4. **Jenkins owns repeatable package builds.** Operator shells can dry-run and
   debug, but publication into Nexus must be CI-produced and traceable to a
   commit.
5. **SLURM owns concurrent execution.** Jenkins schedules build and rollout work
   through SLURM workers; local shell fan-out is an emergency/debug path only.
6. **DistCC is build acceleration, not source-of-truth.** Jenkins records which
   DistCC manifest was used, but package/version authority remains in git and
   published repository metadata.
7. **Nexus is the publication surface** for internal Gentoo overlay/binpkg/raw
   artifacts and RPM/Yum packages.

## Control-plane artifacts

| Artifact | Purpose |
| --- | --- |
| `docs/workflows/rfc1918-infra-control-plane.json` | Human/agent readable workflow stages for repo, vault, Jenkins, SLURM, Nexus, CA package, and DNS dry-run gates. |
| `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/vars/rfc1918_infra_control_plane.yml` | Declarative contract consumed by tests and future Jenkins/Ansible automation. |
| `roles/jenkins_controller/templates/rfc1918-infra-job-seed.yml.j2` | Repo-safe Jenkins seed manifest rendered on the controller. It does not create jobs until a reviewed seed job consumes it. |
| `profile-definitions/vm-jenkins-controller.yml` | Enables the RFC1918 job seed contract on the Jenkins controller profile. |

## Gentoo repository and CA package target

The internal Gentoo path has two related outputs:

1. `rfc99-gentoo-overlay`: an `eselect repository` compatible overlay for
   ebuild metadata, initially including `app-misc/rfc99-atlasforge-ca-certs`.
2. `rfc99-gentoo-binpkg`: Portage binary package artifacts and indexes produced
   by Jenkins/SLURM/DistCC builders.

The CA package installs public CA certificate material only. Private CA keys,
PKCS#12 passwords, LDAP bind secrets, and Nexus credentials stay in Vault and
must never be committed. The Gentoo trust anchor target remains aligned with the
existing `rfc1918_ca_trust` role: `/usr/local/share/ca-certificates`, followed by
`update-ca-certificates`.

Client intent:

```bash
eselect repository add rfc99-atlasforge git https://nexus.rfc1918.host/repository/rfc99-gentoo-overlay.git
eselect repository enable rfc99-atlasforge
emerge -av1 app-misc/rfc99-atlasforge-ca-certs
```

The exact transport can be raw HTTPS, git-over-HTTPS, or a signed snapshot; the
Nexus issue (#217) owns the final hosted-repository shape.

## Rocky/RHEL repository and CA package target

Rocky/RHEL clients receive equivalent trust anchors through an RPM named
`rfc99-atlasforge-ca-certs` published to a Nexus-hosted Yum repository. The
package installs public CA certificate material under
`/etc/pki/ca-trust/source/anchors` and refreshes trust with `update-ca-trust`.

The repo currently has a DOCA-specific Yum lane; this control-plane contract
requires a generic hosted Yum lane for RFC99 packages so CA distribution is not
coupled to the DOCA/RDMA workflow.

## DNS propagation model

Desired path:

```text
NetBox change
  -> repo/source-of-truth drift gate
  -> Hetzner DNS plan/apply artifact
  -> CoreDNS split-horizon render/reload artifact
  -> validation report
```

Zones in scope:

- `rfc1918.host`
- `rfc1918.dev`
- `rfc1918.ai`
- `rfc1918.io`
- `rfc1918.sh`
- `rfc1918.systems`
- `rfc1918.org`
- `vernetzen.io`
- `yukon.systems`

NetBox webhooks should enqueue a controlled workflow rather than mutate DNS
directly. The workflow must prove repo/NetBox consistency first, then produce a
Hetzner plan, apply public DNS only through the guarded Hetzner script, render
CoreDNS local zones, reload CoreDNS, and validate authoritative and local answers.

## Immediate implementation slice

This branch intentionally implements the safe first slice only:

- render a Jenkins seed-manifest contract;
- add the missing generic `slurm_cluster` preflight profile resolution;
- document the CA package and Nexus/DNS control-plane path;
- add tests that assert the contract exists without invoking live mutation.

Live Nexus repository creation, CA package build scripts, NetBox webhook
receivers, and CoreDNS auto-reload hooks remain gated follow-up work tracked in
issues #216, #217, #218, and #220.
