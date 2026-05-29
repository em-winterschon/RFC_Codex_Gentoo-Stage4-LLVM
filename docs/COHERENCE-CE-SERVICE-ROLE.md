# Coherence-CE Service Role Plan

## Scope

Coherence-CE is treated as an experimental distributed cache/data-grid service
for agent-memory indexing experiments, not as the source of truth for memory.
The durable source of truth remains S3-compatible object storage with signed
append-only manifests.

Primary upstream references:

- Oracle Coherence Community Edition repository: <https://github.com/oracle/coherence>
- Oracle Coherence documentation index: <https://docs.oracle.com/en/middleware/standalone/coherence/>

## Target Roles

Initial service-role taxonomy:

- `vm-coherence-ce-node`: full VM profile for one Coherence member
- `container-coherence-ce-node`: future containerized member profile
- `service-coherence-ce-client`: app-side client library/runtime dependency

Current repo scaffolding:

- profile: `profile-definitions/vm-coherence-ce-node.yml`
- package list: `profile-package-lists/stage5-virtual-host-coherence-ce-node.packages`
- Ansible role: `roles/coherence_ce_service`
- service atom: `vm-coherence-ce-node`
- overlay placeholder: `dev-java/oracle-coherence-ce`
- default state: masked and mutation-gated

Initial package/build path:

- Prefer upstream source build through Jenkins until a repeatable Gentoo package
  or local overlay ebuild exists.
- Store built artifacts in the internal binpkg/repo layer or Nexus once that
  service is live.
- Version-pin Java runtime, Maven/Gradle toolchain, Coherence tag, and checksum.

## Jenkins Build Pipeline

Required stages:

1. Fetch upstream source at pinned tag or commit.
2. Verify checksum and license metadata.
3. Build with pinned Java and build tool versions.
4. Run upstream unit tests that are practical in local CI.
5. Produce a versioned artifact bundle.
6. Publish to the internal repository service.
7. Emit a service-readiness manifest consumed by Ansible.

## Service Readiness Gates

Minimum readiness checks:

- process is running under OpenRC or container supervisor
- management/listen port bound on expected interface
- cluster member joins expected cluster name
- health endpoint or CLI check returns node/member state
- rsyslog and metrics exporter are active
- no secret values are present in startup arguments or logs

## Open Decisions

- Confirm exact upstream release/tag and license compatibility before packaging.
- Decide whether first deployment is VM-only or container-first behind HAProxy.
- Decide whether Coherence stores only derived indexes or any operational state.
- Define metrics exporter path for Prometheus/VictoriaMetrics.
