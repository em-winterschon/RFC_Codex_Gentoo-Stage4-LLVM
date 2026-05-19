# FMT2 R630 OFED, OpenStack, and RoCEv2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision `kvm-sfo200-pri-9922` as the first Gentoo stage4 OpenStack-capable hypervisor with separated X710 front-end and ConnectX-4 RoCEv2 back-end fabrics, while keeping `kvm-sfo200-ter-9924` as the storage anchor.

**Architecture:** Stop treating the Rocky 8.9 ELRepo `6.3.8` MLNX_OFED build as the production path after the iSER kernel API mismatch. Keep that builder as diagnostic evidence only, and move production work to a repo-defined Gentoo stage4 profile using `=sys-kernel/gentoo-kernel-6.18.18`, kernel fragments for NFS/iSER/NVMe-RDMA/RoCEv2/ZFS, and explicit fabric admission gates. Treat OpenStack as a staged workload on top of the Gentoo hypervisor substrate, not as a first-pass replacement for the host provisioning baseline.

**Tech Stack:** Gentoo stage4, `sys-kernel/gentoo-kernel`, OpenRC, ZFS, QEMU/libvirt, Open vSwitch, FreeIPA/SSSD, NFSv3/v4/RDMA, iSER, NVMe-RDMA, Dell iDRAC Redfish/IPMI, Arista EOS, Prometheus/VictoriaMetrics/Grafana, rsyslog, Check_MK.

---

## File Map

- `scripts/fmt2-build-mlnx-ofed-rhel-kernel.sh`: Safe, gated diagnostic builder for MLNX_OFED kernel RPMs against an active RHEL-like host kernel.
- `tests/shell/test_fmt2_mlnx_ofed_rhel_kernel_builder.sh`: Static regression checks for the diagnostic OFED builder gates and documentation anchors.
- `tests/shell/test_fmt2_r630_gentoo_stage4_roce_profile.sh`: Profile contract for the Gentoo stage4 R630 OpenStack/RoCE target.
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/metal-fmt2-r630-openstack-roce.yml`: Production Gentoo R630 profile for `pri`/future `sec`.
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/metal-fmt2-r630-openstack-roce.metadata.yml`: Profile metadata and acceptance gates.
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/kernel-config/fragments/storage/rdma-storage-fabric.config`: RDMA/iSER kernel fragment.
- `docs/FMT2-R630-HCI-STAGED-REBUILD.md`: Live FMT2 R630 storage, fabric, OFED, and staged rebuild state.
- `docs/RDMA-STORAGE-FABRIC-PLAN.md`: RDMA protocol and host admission policy.
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/fmt2.yml`: Inventory metadata for `pri`, `sec`, `ter`, Arista 7060, and fabric roles.
- `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nvidia_doca_ofed/defaults/main.yml`: Cross-platform policy that marks in-kernel `mlx5` as discovery-only.

## Task 1: Record the `ter` OFED Builder as Diagnostic-Only Evidence

**Files:**
- Create: `scripts/fmt2-build-mlnx-ofed-rhel-kernel.sh`
- Create: `tests/shell/test_fmt2_mlnx_ofed_rhel_kernel_builder.sh`
- Modify: `docs/FMT2-R630-HCI-STAGED-REBUILD.md`
- Modify: `docs/RDMA-STORAGE-FABRIC-PLAN.md`

- [ ] **Step 1: Verify the source bundle and active kernel on `ter`**

Run from X12AGAIN through M70:

```bash
ssh forge 'ssh kvm-sfo200-ter-9924 "sha256sum /var/tmp/MLNX_OFED_SRC-24.10-4.1.4.0.tgz; uname -r; readlink -f /lib/modules/$(uname -r)/build"'
```

Expected: SHA256 is `6401c0e49f12da0bceb1b03037e39eed2b11e3624dcba139485d2e1631ce5682`, kernel is `6.3.8-1.el8.elrepo.x86_64`, and the kernel build tree resolves under `/usr/src/kernels/6.3.8-1.el8.elrepo.x86_64`.

- [ ] **Step 2: Create the isolated buildroot**

Run on `ter`:

```bash
sudo APPLY_CREATE_BUILDROOT=1 /path/to/scripts/fmt2-build-mlnx-ofed-rhel-kernel.sh create-buildroot
```

Expected: the command installs the build toolchain under `/srv/stage/mlnx-ofed-buildroot` and does not upgrade live host packages.

- [ ] **Step 3: Capture the failed full build as root-cause evidence**

Run on `ter`:

```bash
grep -R "struct scsi_cmnd.*request" /srv/stage/mlnx-ofed-builds/24.10-4.1.4.0/6.3.8-1.el8.elrepo.x86_64 -n
```

Expected: evidence points to the MLNX_OFED iSER source incompatibility with the active `6.3.8` kernel API. No live host package mutation follows from this diagnostic path.

- [ ] **Step 4: Refuse the stock-kernel prebuilt kmod path**

Run on `ter`:

```bash
rpm -qpl /tmp/kmod-mlnx-ofa_kernel-24.10-OFED.24.10.4.1.4.1.rhel8u9.x86_64.rpm | grep '^/lib/modules/' | head
```

Expected: output shows `/lib/modules/4.18.0-513.5.1.el8_9/`, proving it is not valid for the active `6.3.8-1.el8.elrepo.x86_64` kernel.

- [ ] **Step 5: Commit the builder and docs**

Run:

```bash
tests/shell/test_fmt2_mlnx_ofed_rhel_kernel_builder.sh
git add scripts/fmt2-build-mlnx-ofed-rhel-kernel.sh tests/shell/test_fmt2_mlnx_ofed_rhel_kernel_builder.sh docs/FMT2-R630-HCI-STAGED-REBUILD.md docs/RDMA-STORAGE-FABRIC-PLAN.md docs/superpowers/plans/2026-05-19-fmt2-r630-ofed-openstack-roce.md
git commit -m "Document FMT2 R630 OFED diagnostic path"
```

Expected: shell test prints `PASS: test_fmt2_mlnx_ofed_rhel_kernel_builder.sh` and docs label this path diagnostic-only.

## Task 2: Define the Gentoo Stage4 R630 OpenStack/RoCE Profile

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/metal-fmt2-r630-openstack-roce.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/metal-fmt2-r630-openstack-roce.metadata.yml`
- Create: `tests/shell/test_fmt2_r630_gentoo_stage4_roce_profile.sh`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/kernel-config/fragments/storage/rdma-storage-fabric.config`
- Modify: `docs/FMT2-R630-HCI-STAGED-REBUILD.md`
- Modify: `docs/RDMA-STORAGE-FABRIC-PLAN.md`

- [ ] **Step 1: Verify the profile contract fails before implementation**

Run:

```bash
bash tests/shell/test_fmt2_r630_gentoo_stage4_roce_profile.sh
```

Expected: FAIL before the profile exists or before required profile fragments are documented.

- [ ] **Step 2: Create the profile and metadata**

Expected profile contract:

```text
profile_id: metal-fmt2-r630-openstack-roce
kernel_strategy: gentoo-kernel
kernel_package_atom_override: =sys-kernel/gentoo-kernel-6.18.18
package layers: base-minimal-nox, metal-intel-platform, qemu/libvirt hypervisor, NFS client, AAA, observability
kernel fragments: metal-host, hypervisor-qemu-libvirt, roce-v2-host, rdma-storage-fabric, nvmeof-initiator, nfs-client, zfs-host
modules: mlx5_core, mlx5_ib, ib_iser, nvme-rdma, rpcrdma, openvswitch, zfs
mutation gate: fmt2_r630_reimage_apply_required
```

- [ ] **Step 3: Re-run the profile contract**

Run:

```bash
bash tests/shell/test_fmt2_r630_gentoo_stage4_roce_profile.sh
```

Expected: `PASS: test_fmt2_r630_gentoo_stage4_roce_profile.sh`.

## Task 3: Snapshot and Model Arista 7060 Fabric Before Mutation

**Files:**
- Modify: `docs/FMT2-R630-HCI-STAGED-REBUILD.md`
- Modify: `docs/RDMA-STORAGE-FABRIC-PLAN.md`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/fmt2.yml`

- [ ] **Step 1: Save read-only switch evidence through CheckMK**

Run from X12AGAIN:

```bash
ssh forge 'ssh 7060 "show hostname; show version; show interfaces status; show lldp neighbors; show port-channel summary; show vlan; show running-config"'
```

Expected: command completes through the `checkmk` ProxyJump as `verwalterin`. Save the full output outside normal logs and encrypt large full configs before committing them.

- [ ] **Step 2: Record current R630 port map**

Expected live map:

```text
pri X710: Et3/1-Et3/4
sec X710: Et4/1-Et4/4
ter X710: Et5/1-Et5/4
sec ConnectX-4: Et7/1, Et7/3
ter ConnectX-4: Et8/1, Et8/3
```

- [ ] **Step 3: Define first-pass fabric policy**

Expected policy:

```text
eno1+eno2: host management LACP bond
eno3+eno4: VM front-end LACP bond feeding OVS and X710 SR-IOV VFs where firmware exposes VFs
enp130s0f0np0/enp130s0f1np1: independent 50GbE RoCEv2 paths with jumbo MTU and storage-only lossless class
```

- [ ] **Step 4: Do not configure PFC globally**

Expected: any EOS mutation plan scopes PFC only to the storage class/ports/VLANs and includes explicit rollback commands.

## Task 4: Provision `pri` as the First Rebuilt Hypervisor

**Files:**
- Modify: `docs/FMT2-R630-HCI-STAGED-REBUILD.md`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/fmt2.yml`

- [ ] **Step 1: Confirm iDRAC access and destructive gate**

Run:

```bash
ssh forge 'ipmitool -I lanplus -H 172.18.20.122 chassis status'
```

Expected: iDRAC responds. Do not wipe `pri` until the boot method and rollback path are written into the issue and docs.

- [ ] **Step 2: Validate netboot or virtual media path**

Expected: iDRAC can boot an approved Gentoo stage4 installer profile from PXE/iPXE or virtual media without relying on `ter`'s OS RAID1 disks.

- [ ] **Step 3: Install hypervisor substrate first**

Expected host baseline:

```text
Gentoo stage4, =sys-kernel/gentoo-kernel-6.18.18, OpenRC, ZFS, QEMU/libvirt, OVS, FreeIPA/SSSD, rsyslog, node exporter, collectd, Check_MK agent, iDRAC inventory hooks, R630 RDMA/NFS/NVMe-oF fragments
```

- [ ] **Step 4: Stage OpenStack single-node after substrate validation**

Expected: OpenStack is admitted only after the Gentoo hypervisor can boot, authenticate, emit metrics/logs, expose OVS bridges, and pass network/storage conformance.

## Task 5: Validate RDMA Before Advertising Capacity

**Files:**
- Modify: `docs/RDMA-STORAGE-FABRIC-PLAN.md`

- [ ] **Step 1: Verify vendor OFED marker**

Run on each admitted host:

```bash
ofed_info -s
ibv_devinfo
rdma link show
```

Expected: `ofed_info -s` reports the selected vendor OFED line. In-kernel-only `mlx5_core` remains discovery-only and fails admission.

- [ ] **Step 2: Run pairwise RDMA smoke tests**

Expected: `ter` and `pri` can run pairwise RDMA tests on both ConnectX-4 links before any NVMe-oF, iSER, NFS-RDMA, SLURM, OpenStack, or storage workload depends on the fabric.

- [ ] **Step 3: Run one-path-failure validation**

Expected: one ConnectX path can fail without corrupting or wedging the test workload. Multipath policy is protocol-layer first, not Linux LACP first.
