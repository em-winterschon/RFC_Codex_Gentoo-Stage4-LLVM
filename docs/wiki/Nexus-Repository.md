# Nexus Repository OSS

`vm-nexus-repository` defines a Stage5 VM profile for Sonatype Nexus Repository
OSS as an infrastructure repository proxy.

Current pinned installer:

```text
/tmp/Nexus-Repo-OSS/sonatype-nexus-repo-oss_-3.90.1-01-linux-x86_64.tar.gz
```

The role verifies the pinned SHA256, extracts Nexus under `/opt`, links
`/opt/nexus`, renders OpenRC service state, renders JVM/runtime properties, and
emits `/etc/nexus/proxy-intent.yml`.

Initial declarative proxy targets are Maven Central, npmjs, PyPI, Docker Hub,
GHCR, and Gentoo distfiles. Nexus API repository creation is deferred until
admin credentials, TLS, and bootstrap readiness are vaulted.
