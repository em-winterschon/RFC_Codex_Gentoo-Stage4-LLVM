# QNAP SUN99 Floating Homes And MCP Assistant Assessment

## Decision

Use site-local storage for floating home directories:

- **FMT2/SFO200 hosts:** NASA NFSv4.2, because NASA is the local 1 PB ZFS-backed
  storage service in FMT2.
- **SUN99 hosts:** QNAP TS-435XeU NFSv4.2 on the CRS354 10 GbE LACP path, because
  it is local to SUN99 and avoids dragging normal home-directory IO over the
  FMT2 transit path.
- **Replication:** keep QNAP and NASA home datasets consistent only after
  FreeIPA UID/GID parity is proven and each site has a tested server-side
  snapshot/backup path.

This fits the existing `fleet_ipa_nfs_baseline.floating_home_policy` shape:
FreeIPA owns identities and UID/GID policy; storage exports home directories;
Linux clients consume them through SSSD/NFSv4.

## Source handling

Operator-private notes identify the QNAP access path, LDAP parameters, and
existing credentials. Those notes must remain operator-private. This repository
should carry only non-secret topology, validation evidence, and planned variable
names. Do not copy QNAP admin passwords, LDAP bind passwords, RADIUS secrets, or
SSH key material into repo docs, tests, PR bodies, CI logs, or Ansible stdout.

The QNAP LDAP bind should use a dedicated least-privilege FreeIPA service
account for NAS directory lookups. Reusing an existing RADIUS bind account is
acceptable only as a short-lived bootstrap expedient and should be replaced by a
NAS-specific bind DN before production home-directory service depends on it.

## Live read-only evidence captured from M70

Captured on 2026-05-29 from `admin-sun99-forge-099070` using key-based SSH to
`qnap` / `lagg-10k-nas7f281b-qnap.rfc1918.host`.

### Host and network

- Hostname: `NAS7F281B-QNAP`.
- Firmware/model evidence: QTS `5.2.4`, model family `TS-X35EU`.
- Kernel: `Linux 5.10.60-qnap` on `aarch64`.
- SSH user: `forge`, UID `1000`, primary group `everyone`.
- `bond0`: `172.16.99.28/24`, active-backup over two 1 GbE links.
- `bond1`: `172.16.254.28/24`, IEEE 802.3ad over two 10 GbE links.
- `bond1` member state:
  - `eth0`: up, 10 Gb/s, full duplex, aggregator ID `1`.
  - `eth1`: up, 10 Gb/s, full duplex, aggregator ID `1`.
  - transmit hash policy: `layer2+3`.
  - LACP rate: slow.
- M70 reaches `172.16.254.28` via `172.16.99.1 dev bond0`; end-to-end NFS
  multipath benefit from M70 therefore still needs live flow-distribution
  validation. QNAP-to-CRS354 LACP is up, but that alone does not prove a SUN99
  client can use both QNAP links for one home-directory workload.

### NFS state

- NFS daemons are running and listening on `2049/tcp` and `2049/udp`.
- `rpcinfo -p 172.16.254.28` reports NFS program versions `2`, `3`, and `4`.
- `/etc/idmapd.conf` has `Domain = rfc1918.host`.
- `/etc/exports` is currently empty.
- `/proc/fs/nfsd/exports` is currently empty.
- `showmount -e 172.16.254.28` returns an empty export list.
- Existing relevant QNAP shares include:
  - `/share/CACHEDEV1_DATA/homes`;
  - `/share/CACHEDEV2_DATA/nfs-rfc99-sysinfra-genstore`;
  - `/share/CACHEDEV2_DATA/nfs-for-assholes`.
- `nfs-rfc99-sysinfra-genstore` is encrypted via eCryptfs.

Conclusion: the QNAP is reachable and NFS-capable, but it is **not yet serving**
a usable NFS floating-home export.

## NFSv4.2 multipath interpretation

For this environment, "NFS multipath" should mean **NFSv4.2 over TCP with
multiple client connections and validated LACP flow distribution**, not block
multipath. The repo already models this as `nfsv4_2_tcp_multipath` with
`nconnect` in the client profile.

Controls:

- Use `nconnect=8` only on hosts with validated multi-link paths to the QNAP.
- Use `nconnect=4` or a single-path profile where the host lacks LACP or the
  route traverses a single bottleneck.
- Validate flow distribution on the client and CRS354/QNAP bond members; LACP
  usually hashes flows and does not split one TCP flow across links.
- Keep `sec=sys` transitional. Target `sec=krb5p` once QNAP LDAP/Kerberos/NFSv4
  behavior is proven against FreeIPA.

## Proposed SUN99 export model

Create a dedicated QNAP shared folder for FreeIPA-backed homes rather than
reusing QNAP's local-user `homes` feature:

```text
/share/CACHEDEV2_DATA/rfc1918-floating-homes
```

Candidate NFS export policy:

```text
source: 172.16.254.28:/rfc1918-floating-homes
mountpoint: /home
protocol: NFSv4.2 over TCP
security bootstrap: sec=sys
security target: sec=krb5p
SUN99 LACP clients: vers=4.2,proto=tcp,nconnect=8,hard,_netdev,nofail,soft
SUN99 non-LACP clients: vers=4.1 or 4.2,proto=tcp,nconnect=1-4,hard,_netdev,nofail,soft
```

Before export creation, confirm QNAP's UI/CLI maps NFSv4 pseudo-root paths in a
stable way. The export path seen by Linux clients may be a QNAP share name rather
than the raw `/share/CACHEDEV*_DATA/...` path.

## Client rollout gates

A SUN99 host can consume QNAP floating homes only after all of these pass:

1. FreeIPA user/group exists with stable UID/GID.
2. Host is enrolled as an SSSD IPA client.
3. `getent passwd <user>` and `id <user>` return FreeIPA values.
4. `sss_ssh_authorizedkeys <user>` returns the FreeIPA SSH keys.
5. `sudo -l -U <user>` matches the intended FreeIPA sudo policy.
6. QNAP resolves the same UID/GID or accepts numeric ownership consistently.
7. NFSv4 idmap domain is `rfc1918.host` on server and client.
8. `/home/<user>` ownership on the QNAP matches the FreeIPA UID/GID.
9. Mount, write, fsync, read, delete, and unmount tests pass from a canary.
10. For `nfsv4_2_tcp_multipath`, multiple TCP connections and both QNAP 10 GbE
    links are observed during load.

## MCP Assistant assessment

The QNAP has the QNAP MCP Assistant package installed:

- QPKG name: `qmcp`.
- Display name: `MCP Assistant`.
- Version: `0.10.0.797`.
- Build date in QPKG metadata: `20251017`.
- Daemon: `./qmcp daemon --daemonize --loglevel info`.
- Unix socket health check: `/var/run/qmcp.sock` returns `{"status":"ok"}`.
- Authenticated REST calls require a token; unauthenticated system API calls
  return `401`.
- Logs show listeners on `0.0.0.0:8442` and `0.0.0.0:8443`, plus a QTS Apache
  proxy under `/qmcp/` through the Unix socket.

The package registers MCP/NAS tools in these provider groups:

| Provider | Observed tool count | Usefulness |
| --- | ---: | --- |
| `nasstatus` | 7 | Useful for read-only NAS health, logs, load, process, package, and storage checks. |
| `sharedfolder` | 4 | Useful for controlled shared-folder inventory; write tools are risky. |
| `usergroup` | 9 | Not recommended for autonomous identity mutation; FreeIPA must stay authoritative. |
| `filestation` | 3 | Potentially useful for read-only dataset/file discovery. |
| `qsirch` | 1 | Potentially useful for local indexed file search/RAG discovery if Qsirch has the right corpus. |

### Assessment for inference infrastructure

MCP Assistant is **not** an inference runtime, vector database, scheduler, or
model-serving component. It may be useful as a **NAS control-plane and retrieval
adjunct** if constrained to read-only operations:

- inventory QNAP storage and share state for operators;
- expose NAS health into an agent dashboard;
- search curated datasets through Qsirch before ingestion into a real RAG index;
- help agents locate files under approved shares without granting shell access.

It should **not** be trusted for autonomous infrastructure mutation yet:

- it has write-capable shared-folder and user/group tools;
- it is listening on all interfaces;
- local logs show broad CORS headers;
- authentication, token lifecycle, TLS trust, audit retention, and network ACLs
  have not been validated;
- FreeIPA must remain authoritative for accounts, groups, sudo, and SSH keys.

Recommendation: keep MCP Assistant installed but treat it as experimental. If we
use it, create a dedicated read-only MCP client credential, restrict access to
M70/Atlas control hosts, disable or avoid write tools, pin TLS trust, and record
every tool call in the Forge audit log. Do not put it in the production
inference path until it passes a security review.

## Implementation plan

### Phase 1 - repo-only modeling

1. Add a `qnap_archive_ts435xeu` storage-service record with non-secret fields:
   hostname, service IPs, intended share name, NFS protocol, and LDAP variable
   names.
2. Add a SUN99 floating-home profile that selects QNAP as primary and NASA as
   replication/off-site peer.
3. Extend readiness checks so SUN99 hosts fail if QNAP has no matching export or
   if `showmount`/NFSv4 probe cannot see the selected path.
4. Keep FMT2 hosts pointed at NASA in site policy.

### Phase 2 - QNAP canary configuration

1. Create or select a dedicated QNAP shared folder for FreeIPA-backed homes.
2. Configure QNAP LDAP/LDAPS against FreeIPA using vault-backed secrets.
3. Enable NFSv4/NFSv4.2 export for the canary source network only.
4. Create one canary home directory with exact FreeIPA UID/GID ownership.
5. Validate from M70 with a non-root FreeIPA user before broadening.

### Phase 3 - SUN99 rollout

1. Mount QNAP homes on one canary host with `nconnect=8` only if the client path
   has validated LACP/multi-flow capacity.
2. Use a non-LACP profile for hosts that route through a single bottleneck.
3. Add Thor and M70 host-class profiles after canary evidence is attached.
4. Add QNAP-to-NASA replication only after UID/GID parity and snapshot behavior
   are validated.

## Immediate blockers

- QNAP NFS has no exports configured yet.
- M70 reaches QNAP `172.16.254.28` through the gateway, so the current M70 path
  does not by itself prove end-to-end multipath.
- LDAP bind secret handling must move to vault-backed, NAS-specific variables.
- QNAP MCP Assistant is useful to evaluate, but not safe as an autonomous write
  surface yet.
