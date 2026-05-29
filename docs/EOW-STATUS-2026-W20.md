# EOW Status 2026-W20

## Week Summary

The week moved the infrastructure from recovery mode back into controlled
execution. The main operational achievement is that Forge now has a viable M70
automation-admin platform, with persistent ZFS root, FreeIPA/SSSD enrollment,
GitHub CLI continuity, X12AGAIN SoL reachability, local monitoring packages,
LACP staging links, and a validated OpenVPN path to FMT2 NASA storage.

The second major achievement is backup path hardening. Hasslehoff has a
scheduled config/state backup wrapper, local ntfy reporting hooks, and a tested
off-site storage route through M70 to NASA NFS. X12AGAIN remains online and
protected while M70 and the future X11SCL-iF platform absorb automation-admin
responsibilities.

## Completed This Week

- Recovered repo/session continuity after the Codex state loss by inspecting
  commits, PRs, local docs, and active project-board work.
- Provisioned and validated the first M70 as
  `admin-sun99-forge-099070.rfc1918.host`, including SATADOM iPXE chainload,
  mirrored NVMe ZFS root, FreeIPA enrollment, persistent hostname, SSSD, and
  central `codex-admin` SSH behavior.
- Restored selected Forge continuity paths from off-host X12AGAIN backup to the
  M70 while deferring the full `/opt` import due current storage capacity.
- Modeled the X11SCL-iF as the preferred long-term Forge automation-admin host
  and kept the M70 as the near-term bridge and rollback node.
- Advanced FMT2 access: BigNetwork route work identified the return-path gap,
  and the compatible OpenVPN path brought NASA SSH/NFS into reach from M70.
- Added Hasslehoff scheduled backup wrapper coverage with manifest, lockfile,
  optional mirror target, checksum verification, and ntfy notifications.
- Validated NASA NFS mount and write path from M70 over OpenVPN using dedicated
  UID/GID `8888` directories.
- Continued netboot expansion with X1 Gen8 inventory, DHCP/DNS, and by-MAC
  iPXE dispatch work.
- Improved M70 operator baseline packages and profile-owned eix behavior.
- Added local mounted-root binpkg sync support for NFS-backed package publishing.

## Remaining Critical Path

- Import M70 SSH connection profiles, M70-to-NASA keys, host passwords, and
  service credentials into Ansible Vault without exposing private key material.
- Make the M70 NASA mount durable enough for scheduled backup jobs: explicit
  mountpoint, timeout/retry policy, stale-mount handling, free-space checks, and
  restore validation.
- Complete Forge continuity acceptance from M70 before any X12AGAIN reimage:
  Codex runtime, vault, GitHub, NetBox, FreeIPA, Hasslehoff, CCR2004, ntfy,
  NASA storage, and X12AGAIN SoL.
- Bring the X11SCL-iF online once hardware is ready, then treat it as the final
  automation-admin platform and keep M70 as edge/SLURM/SD-WAN helper capacity.
- Resume SLURM pilot work with M70/X11 candidates and keep X12AGAIN out of the
  scheduler until E2ET and backup gates are satisfied.
- Promote RBAC/AAA into usable daily operations: FreeIPA Web UI, `ipa` CLI,
  `ldapvi`, Ansible sync, SSSD SSH key lookup, hostgroups, HBAC, and sudo rules.

## Risk Register

- X12AGAIN still contains critical live state. Reimaging it before Forge
  continuity and external backup validation would create avoidable recovery
  risk.
- NASA NFS is usable but currently relies on the M70 OpenVPN tunnel and
  squashed UID/GID write directories. That is acceptable for first durable
  backup, but it needs monitoring and stale-mount recovery before unattended
  retention jobs.
- M70 storage and RAM are bridge-grade, not final control-plane capacity. The
  X11SCL-iF remains the preferred long-term Forge host.
- Manual SSH key copying is now a process smell. FreeIPA and Ansible Vault need
  to become the daily identity path before additional hosts are enrolled.
