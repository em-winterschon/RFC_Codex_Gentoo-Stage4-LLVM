# NFS Storage Client

The `nfs-storage-client` Stage5 overlay defines the baseline NFS client policy
for bare-metal and VM systems. Containers do not inherit this profile by default
because mounting NFS inside containers adds host namespace, credential, and
restart-order problems; container workloads should consume host-mounted volumes
unless there is a service-specific exception.

Roadmap tracking:

- Issue #117: `RDMA-002`, host RDMA storage client baseline.
- Issue #111: `RDMA-003`, DOCA/OFED deployment consumes this baseline after
  fabric and client policy are ready.
- The RDMA promotion readiness gate is
  `docs/workflows/rdma-fabric-promotion-readiness.yml`; it marks this baseline
  defined while keeping NFS-RDMA live use blocked until the shared RDMA/FMT2
  production admission gates pass.

## Protocol Policy

NFSv4.2 over TCP with nconnect is the default for LACP-capable bare-metal and VM
hosts once FreeIPA/SSSD enrollment is validated. NFSv4.1 over TCP is the default for hosts without LACP links.
NFSv3 over TCP remains a rescue and early bootstrap compatibility profile, not
the normal fleet default.

NFSv4 requires centralized AAA, SSSD, and consistent UID/GID mapping from the
`aaa-domain-client` overlay. Floating home directories must not be enabled until
FreeIPA UID/GID parity is validated against the NFS server dataset ownership.

NFS-RDMA is supported as an opt-in protocol class for RoCE/RDMA-attached hosts.
Enable it only where the NIC driver, RDMA userspace, fabric MTU, PFC/ECN policy,
and kernel modules are already validated.

NFS multipath is tracked as a client policy, not as a block-storage substitute.
For NFS, prefer pNFS or NFSv4.1+ `nconnect` where supported. The overlay also
installs `multipath-tools` because the same bare-metal and VM storage clients
often need iSCSI, FC, or NVMe-oF block multipath.

## Gentoo Enablement

Profile:

- `profile-definitions/nfs-storage-client.yml`

Package list:

- `profile-package-lists/stage5-storage-nfs-client.packages`

Primary atoms:

- `net-fs/nfs-utils`
- `net-nds/rpcbind`
- `sys-cluster/rdma-core`
- `sys-fs/multipath-tools`

The profile declares kernel config intent for `CONFIG_NFS_FS`, `CONFIG_NFS_V3`,
`CONFIG_NFS_V4`, `CONFIG_NFS_V4_1`, `CONFIG_NFS_V4_2`,
`CONFIG_SUNRPC_XPRT_RDMA`, and `CONFIG_DM_MULTIPATH`.

## Ansible Role

Role:

- `roles/nfs_storage_client`

The role renders:

- `/etc/idmapd.conf`
- `/etc/nfs.conf.d/90-stage5-client.conf`
- `/etc/modprobe.d/nfs-rdma.conf` when RDMA is enabled

It also adds OpenRC service intent for `rpcbind` and `nfsmount`.
Generated `/etc/fstab` entries include `nofail,soft` by default so boot and
login paths do not hang indefinitely when an NFS endpoint is unavailable.

## Usage Pattern

For a normal VM client:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/hardened-llvm-stage4-merged-usr.yml"
  - "{{ playbook_dir }}/../profile-definitions/aaa-domain-client.yml"
  - "{{ playbook_dir }}/../profile-definitions/nfs-storage-client.yml"
```

For an early bootstrap or rescue VM without domain enrollment, use the
`nfsv3_tcp_rescue` mount defaults and avoid Kerberos-backed NFSv4 mounts until
AAA is online.

For RDMA:

```yaml
nfs_storage_client:
  enabled: true
  protocol_default: nfs_rdma
  enable_rdma: true
```

RDMA enablement should be paired with host-level RoCE validation and explicit
fabric documentation.
