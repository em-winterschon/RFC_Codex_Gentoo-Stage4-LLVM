# Fleet IPA And NFS Readiness

FreeIPA client readiness is mandatory fleet baseline. A host is not ready for
normal use until SSSD, NSS, PAM, SSH authorized key lookup, sudo policy lookup,
Kerberos, LDAP, and NFS client support are installed and validated.

FreeIPA admin CLI mutation capability is mandatory on admin hosts, not necessarily every Gentoo client.
The current Gentoo Portage tree does not expose a native FreeIPA admin CLI
package, so Gentoo clients must prove domain client behavior while FreeIPA
mutation runs from `ipa01` or another admin host with the `ipa` CLI.

## SSH Probe Syntax

The exact M70-to-IPA probe syntax is:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 -l verwalterin ipa01.rfc1918.host '<cmd>'
ssh -o BatchMode=yes -o ConnectTimeout=8 -l root ipa01.rfc1918.host '<cmd>'
```

Both currently fail before command execution if IPA-side SSH policy does not
allow that source/user/key path.

## Baseline Atoms

The Gentoo `stage5-base-minimal-nox` package layer includes the client-side
FreeIPA and NFS atoms required before a host is considered ready:

```text
sys-auth/sssd
app-crypt/mit-krb5
net-nds/openldap
app-misc/ca-certificates
net-fs/nfs-utils
net-nds/rpcbind
sys-apps/keyutils
```

RHEL-family hosts should install `freeipa-client`, `sssd`, `sssd-ipa`,
`krb5-workstation`, `openldap-clients`, and `nfs-utils`. Debian-family hosts
should install `freeipa-client`, `sssd-ipa`, `krb5-user`, `ldap-utils`, and
`nfs-common`.

## NFS Protocol Policy

NFSv4.2 with multipath is the default for LACP-capable hosts. In practice this
means NFSv4.2 with `nconnect` or pNFS where supported, not block-layer
`multipath-tools` semantics for a filesystem mount.

Do not assume Proxmox/Debian NFS clients provide OpenEuler-style NFS multipath.
The Proxmox forum thread on NFSv4.2 multipathing showed `nconnect` alone still
limited practical throughput to one 10G path in that test, and
`localaddrs`/`remoteaddrs` options failed because they depend on a
kernel/client implementation not present in that environment.

NFSv4.1 is the default for non-LACP hosts. NFSv3 remains a rescue/bootstrap
compatibility profile, not the normal fleet default.

NASA NFS boot mounts must use `nofail,soft`. The `nofail` option prevents a
failed boot when the network or export is unavailable. The `soft` option avoids
indefinite boot and login hangs; use service-specific hard mounts only after
the failure domain and recovery behavior are explicitly approved.

SUN99 QNAP can serve low-latency floating homes and sync with FMT2 NASA. That
should only be enabled after FreeIPA UID/GID parity and group memberships are
validated across the hosts that will consume the exported home directories.

## Audit

Run the read-only audit:

```bash
scripts/audit-fleet-ipa-nfs-readiness.sh --limit all
```

If `~/.ssh/vault/ANSIBLE_VARS.ENV` is readable, the wrapper automatically uses
`scripts/with-ansible-vault-env.sh` so encrypted inventory variables can be
decrypted before host checks run.

The audit checks:

- `sssctl config-check`
- `getent passwd verwalterin`
- `sss_ssh_authorizedkeys verwalterin`
- `/home` is mounted as NFS
- mount options include `nofail` and `soft`
- mount protocol is NFSv4.2 or NFSv4.1
