# Nexus Repository OSS

`vm-nexus-repository` defines a Stage5 VM profile for Sonatype Nexus Repository
OSS as an infrastructure repository proxy.

## Local Installer Source

Current pinned installer:

```text
/tmp/Nexus-Repo-OSS/sonatype-nexus-repo-oss_-3.90.1-01-linux-x86_64.tar.gz
```

Pinned checksum:

```text
6f3240f34bb46b99d93b2c512333651ea227b4c65248c8154ae275933c320556
```

The downloaded tarball includes bundled Temurin JDK `21.0.9+10`, so the initial
profile does not add an external Java runtime dependency.

## Role

Role path:

```text
roles/nexus_repo
```

The role:

- verifies the installer SHA256 before extraction
- extracts Nexus under `/opt`
- links `/opt/nexus` to the pinned extracted version
- renders OpenRC service state for `nexus`
- renders `nexus.vmoptions`
- renders Nexus runtime properties
- renders `/etc/nexus/proxy-intent.yml`

## Proxy Intent

Initial declarative proxy targets:

- Maven Central
- npmjs
- PyPI
- Docker Hub
- GHCR
- Gentoo distfiles

The role does not yet create repositories through the Nexus API. API automation
is intentionally deferred until admin credentials, TLS, and bootstrap readiness
are vaulted.

## VM Sizing

Initial profile memory settings are conservative: `4 GiB` JVM heap plus
`4 GiB` direct memory. Production use should attach a large persistent data disk
under `/var/lib/nexus` before repository proxy traffic is enabled.
