# NFS Storage Client

The `nfs-storage-client` Stage5 overlay defines the baseline NFS client policy
for bare-metal and VM systems. Containers do not inherit this profile by default.

Roadmap tracking:

- Issue #117: `RDMA-002`, host RDMA storage client baseline.
- Issue #111: `RDMA-003`, DOCA/OFED deployment consumes this baseline after
  fabric and client policy are ready.
- The RDMA promotion readiness gate is
  `docs/workflows/rdma-fabric-promotion-readiness.yml`; it marks this baseline
  defined while keeping NFS-RDMA live use blocked until the shared RDMA/FMT2
  production admission gates pass.

NFSv4.2 over TCP with nconnect is the default for LACP-capable hosts.
NFSv4.1 over TCP is the default for hosts without LACP links. NFSv3 over TCP
remains a rescue and early bootstrap compatibility profile.

NFSv4 requires centralized AAA, SSSD, and consistent UID/GID mapping from the
`aaa-domain-client` overlay. NFS-RDMA is opt-in and requires validated RDMA/RoCE
fabric readiness.

Primary files:

- `profile-definitions/nfs-storage-client.yml`
- `profile-package-lists/stage5-storage-nfs-client.packages`
- `roles/nfs_storage_client`

Primary atoms:

- `net-fs/nfs-utils`
- `net-nds/rpcbind`
- `sys-cluster/rdma-core`
- `sys-fs/multipath-tools`

Use `nconnect` or pNFS for NFS-side multi-path behavior where supported. Keep
`multipath-tools` for block storage paths such as iSCSI, FC, and NVMe-oF.
