# SUN99 FreeIPA + QNAP Floating Homes

This runbook defines the SUN99 operator/Forge target state: `forge1` through
`forge6`, `ltcol-forge`, `toor`, `eva`, `robin`, `verwalterin`, `backups`, and
`codex-admin` are FreeIPA users with preserved M70 baseline UID/GID values and
QNAP NFSv4.2 floating home directories using `nconnect` on the CRS354/QNAP LACP
path.

## Source of Truth

The repo identity source defines the accounts, primary groups, supplemental
Forge/operator groups, SSH public-key vault variable names, host-local group
membership controls, and per-user floating home metadata:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml
```

The legacy low-ID, Forge-worker, and Robin ID ranges are explicit so FreeIPA,
SSSD, and NFSv4 ownership all agree before any host uses the homes.

## Storage Target

SUN99 floating homes live on the QNAP archive host over QNAP NFSv4.2 with
`nconnect=4` on the CRS354 10 GbE LACP path:

```text
lagg-10k-nas7f281b-qnap.rfc1918.host:/share/CACHEDEV2_DATA/rfc1918-floating-homes/<user>
```

Clients mount each home at `/home/<user>` through the NFSv4 pseudo-root path:

```text
172.16.254.28:/rfc1918-floating-homes/<user>
```

The QNAP export must preserve numeric UID/GID ownership and use the RFC1918 NFS
idmap domain.

## Authentication Contract

SSH access must come from FreeIPA SSH public-key attributes resolved by SSSD, not
host-local `authorized_keys` as the authority. Host-local key files under
`/home/<user>/.ssh/id_ed25519` are migration inputs only; the authoritative SSH
login path is FreeIPA -> SSSD -> `AuthorizedKeysCommand`.

The `toor` identity is a FreeBSD-style emergency superuser account with UID/GID
`32/32`, LtCol Forge-equivalent supplemental groups, and a generated ed25519 key
stored in its home before FreeIPA import.

Host-local `/etc/group` entries are still managed for compatibility. `root` and
`whee` must include `eva`, `robin`, `verwalterin`, `ltcol-forge`, and `toor`;
`wheel` also includes the Forge workers and backup/admin operators.

## Validation

After applying FreeIPA and QNAP changes, run:

```bash
ansible-playbook -i inventories/local-network/hosts.yml \
  playbooks/forge-floating-home-validate.yml
```

The validation checks NSS user resolution, `sss_ssh_authorizedkeys`, NFS mount
metadata, NFSv4.2 protocol, ownership visibility, host-local group membership,
and write access as each floating-home user.

## Live protocol note

The QNAP control panel reported NFSv4.2 support, but the live server initially
returned `protocol-not-supported` and `/proc/fs/nfsd/versions` showed `-4.2`.
The QNAP `/etc/init.d/nfs` script hard-disabled 4.2 with `NO_V42="-N 4.2"`.
The live NAS was patched to honor `NFS Enable_V42 TRUE`; after NFS restart,
`/proc/fs/nfsd/versions` showed `+4.2` and a client probe mounted the export with
`vers=4.2,nconnect=4`.

QMCP currently exposes useful health/statistics/admin-assist endpoints, but no
confirmed MCP/API provider for NFS protocol toggles. Treat QMCP as read-only
operator assistance for this path; use SSH/sudo plus explicit backups for QNAP
NFS service remediation.
