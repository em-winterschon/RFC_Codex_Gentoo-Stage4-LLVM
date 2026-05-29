# Forge Workers FreeIPA + QNAP Floating Homes

This runbook defines the SUN99 Forge worker target state:
`forge1` through `forge6` are FreeIPA users with preserved legacy UID/GID
values and QNAP NFSv4.1 floating home directories with nconnect multipath.

## Source of Truth

The repo identity source defines the accounts, primary groups, supplemental
Forge groups, SSH public-key vault variable names, and per-user floating home
metadata:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml
```

The legacy Forge ID range is explicit so FreeIPA, SSSD, and NFSv4 ownership all
agree before any host uses the homes.

## Storage Target

SUN99 Forge homes live on the QNAP archive host over QNAP NFSv4.1 with nconnect on the CRS354
10 GbE LACP path:

```text
lagg-10k-nas7f281b-qnap.rfc1918.host:/share/CACHEDEV2_DATA/rfc1918-floating-homes/forgeN
```

Clients mount each worker home at `/home/forgeN`. The QNAP export must preserve
numeric UID/GID ownership and use the RFC1918 NFS idmap domain.

## Authentication Contract

SSH access must come from FreeIPA SSH public-key attributes resolved by SSSD, not
host-local `authorized_keys` as the authority. Host-local files may exist only as
migration evidence or emergency fallback until SSSD validation is green.

## Validation

After applying FreeIPA and QNAP changes, run:

```bash
ansible-playbook -i inventories/local-network/hosts.yml \
  playbooks/forge-floating-home-validate.yml
```

The validation checks NSS user resolution, `sss_ssh_authorizedkeys`, NFS mount
metadata, NFS protocol version, ownership visibility, and write access as each
Forge worker.

## Live protocol note

The SUN99 QNAP export validated with NFSv4.1 and `nconnect=4`; an NFSv4.2 mount attempt returned protocol-not-supported on the current QTS/NFS server build, so the committed live baseline is `vers=4.1` until QNAP server support changes.
