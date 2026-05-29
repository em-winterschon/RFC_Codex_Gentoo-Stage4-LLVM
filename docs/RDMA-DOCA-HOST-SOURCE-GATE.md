# RDMA DOCA Host Source Gate

Issue #111 is now anchored on an explicit DOCA Host source-of-truth workflow:
`docs/workflows/doca-host-source-of-truth.yml`.

Two build lanes are required:

- DOCA 2.9.4 LTS is the ConnectX-4 lane. Target Rocky Linux 9.6 with kernel
  `5.14.0-570.12.1.el9_6.x86_64` unless a newer DOCA 2.x-supported kernel is
  verified.
- Rocky Linux 10 is the primary current DOCA host lane for BlueField-2 and
  ConnectX-5. The current target is DOCA Host `3.3.0` with the supported Rocky
  Linux 10 kernel `6.12.0-124.8.1.el10_1.x86_64`, matching `kernel-devel` and
  `kernel-headers`, and the NVIDIA RPM repository package installed through
  `dnf`.

The highest observed kernel lane in the official DOCA support matrix is
kernel.org 6.18, but that lane is `doca-ofed-only`. Treat it as a diagnostic or
future exception lane, not the first production RoCEv2 storage lane. NFS-RDMA,
NVMe-RDMA, and iSER remain blocked until the selected lane proves the required
DOCA/RDMA profile support.

## Device Policy

BlueField-2 and ConnectX-5 use the DOCA 3.3.x lane. ConnectX-4 uses the DOCA
2.9.x LTS lane because current DOCA Host branches removed ConnectX-4
adapter-family support. ConnectX-4 firmware must be updated before the DOCA 2.9.4 lane is evaluated so build or runtime failures are not caused by stale adapter firmware.

## Artifact Policy

Build and DKMS work must use local disk first. Publish finished artifacts to the
NASA-backed YUM repositories only after the build or apply step completes:

```bash
/opt/storage/nfs/nasa/nasa-yum-repo-doca-host/doca-2.9.4/el9/x86_64/
/opt/storage/nfs/nasa/nasa-yum-repo-doca-host/doca-3.3.0/el10/x86_64/
```

Required retained artifacts:

- NVIDIA DOCA Host repository package URL/path and checksum.
- Kernel NEVRAs and matching header/devel package evidence.
- DKMS or kernel-module build logs.
- `ofed_info -s`.
- `ibv_devinfo`.
- `rdma link show`.
- Perftest tool availability.
- `SHA256SUMS`.

## Apply Rule

The Ansible role remains blocked by default. Live mutation requires:

- `nvidia_doca_ofed_enabled=true`.
- `nvidia_doca_ofed_apply=true`.
- `nvidia_doca_ofed_repo_package_type=rpm` for Rocky/RHEL lanes.
- A DOCA Host RPM repository package URL or local path.
- Matching kernel build tree under `/lib/modules/<kernel>/build`.
- Explicit custom-kernel acknowledgement when the running kernel is not the
  approved lane.

## Build Host Rule

Use `kvm-sfo200-ter-9924` as the high-performance build host, but run builds in
a container, systemd-nspawn root, or VM. Do not install build dependencies into
the `ter` host OS unless a separate host-maintenance change approves it.

Use `scripts/fmt2-doca-repo-lane-build.sh` for lane staging and NASA repo
publication:

```bash
DOCA_LANE=doca-2.9.4-cx4-rocky9.6 scripts/fmt2-doca-repo-lane-build.sh plan
DOCA_LANE=doca-3.3.0-bf2-cx5-rocky10.1 scripts/fmt2-doca-repo-lane-build.sh plan
```

## References

- NVIDIA DOCA Host Installation and DKMS Management Guide:
  <https://docs.nvidia.com/doca/sdk/DOCA-Host-Installation-and-DKMS-Management-Guide/index.html>
- NVIDIA DOCA General Support:
  <https://docs.nvidia.com/doca/sdk/General-Support/index.html>
