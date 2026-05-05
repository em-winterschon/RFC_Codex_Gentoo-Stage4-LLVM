# Package Version Pinning

Stage4 and Stage5 profiles now track application version locks in:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/app-version-locks/stage5-service-apps.yml
```

The current policy is:

- Gentoo package atoms remain authoritative for OS packages.
- Service applications outside the Gentoo tree must have explicit upstream
  version and checksum locks.
- Metadata files must include `package_pins` so each profile declares its
  tracked atoms, upstream service pin, or known pin gap.
- `pin_gaps` are explicit debt items, not hidden assumptions.

Current explicit locks include:

- Sonatype Nexus Repository OSS `3.90.1-01`
- NetBox `v4.5.9`
- Elasticsearch `9.3.1`

Current pin gaps are for Portage-resolved services where the exact installed
version should be written back after the VM/binpkg build:

- Jenkins
- Grafana
- Prometheus stack
