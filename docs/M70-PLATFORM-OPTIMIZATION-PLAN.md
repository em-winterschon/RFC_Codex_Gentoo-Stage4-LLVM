# M70 Platform Optimization Plan

Captured from `admin-sun99-forge-099070.rfc1918.host` on 2026-05-21.

This note records the local M70 hardware/runtime facts and the optimization
queue for the six-node M70 pool intended for Forge, SLURM, Podman, VM, Kata,
and Firecracker workloads.

## Current Platform

| Area | Observed state |
| --- | --- |
| CPU | Intel Atom C3758, 8 cores, 8 threads, 2.2 GHz, single NUMA node |
| Memory | 31 GiB RAM, no swap, no persistent hugepages |
| Kernel | `6.18.28-gentoo-dist`, OpenRC, unified cgroup v2 |
| Virtualization | VT-x, EPT, `/dev/kvm`, `/dev/vhost-net`, `/dev/net/tun` present |
| IOMMU | Kernel has `CONFIG_INTEL_IOMMU=y`, but no IOMMU groups are exposed |
| QAT | Intel C3000 QAT present; `qat_c3xxx` starts 6 acceleration engines |
| Root storage | Mirrored 256 GB KIOXIA BG5 NVMe ZFS pool `zroot`, 4% used |
| Stage storage | 1.9 TB USB XFS disk at `/srv/forge-stage`, 3% used |
| Build cache | `/srv/build-cache` symlinked into `/srv/forge-stage/build-cache` |
| Network | `netboot0` 1G management, `bond0` 2x1G LACP with no IPv4 address |
| Toolchain | LLVM profile, GCC 15, clang/lld/LLVM 21, Rust bin 1.93 |
| Distcc | Client configured for `172.16.99.108/48,lzo` plus `localhost/2` |
| DNS | `172.16.99.1` primary, `9.9.9.9` fallback; do not use FreeIPA `.63` for DNS |

## High-Priority Fixes

1. Fix early microcode for Intel and keep AMD coverage.

   Evidence:

   - `dmesg` reports `x86/CPU: Running old microcode`.
   - CPU vulnerabilities report `Old microcode: Vulnerable` and
     `Register File Data Sampling: Vulnerable: No microcode`.
   - `/boot/intel-uc.img` and `/boot/amd-uc.img` exist.
   - The active initramfs contains `kernel/x86/microcode/AuthenticAMD.bin`,
     but no Intel microcode blob.
   - The active kernel command line uses `initrd=initrd.magic` and does not
     show `intel-uc.img` before the main initramfs.

   Corrective path:

   - Either republish the initramfs with both Intel and AMD early microcode, or
     publish `intel-uc.img` and `amd-uc.img` and make the iPXE role load them
     before the main initramfs.
   - Do not reboot immediately just for validation; stage the boot artifacts
     and verify the next planned reboot picks up Intel revision newer than
     `0x00000032`.

2. Enable IOMMU posture for VM/Kata/Firecracker work.

   Evidence:

   - `CONFIG_INTEL_IOMMU=y` is present.
   - ACPI DMAR is detected.
   - No `/sys/kernel/iommu_groups` entries are exposed.
   - The kernel command line lacks `intel_iommu=on`.

   Corrective path:

   - Add `intel_iommu=on iommu=pt` to the M70 boot profile after confirming
     the netboot/iPXE role owns the active kernel arguments.
   - Recheck IOMMU groups after the next planned reboot.
   - Keep VFIO passthrough optional; KVM and vhost-net are already present for
     normal VM and microVM runtime.

3. Finish container and VM runtime package policy.

   Observed gaps:

   - `podman`, `buildah`, `skopeo`, `containerd`, `runc`, `crun`, `qemu`, SLURM,
     MUNGE, Firecracker, and Kata runtime binaries are not installed locally.
   - `sys-cluster/slurm` is masked by `~amd64`.
   - MUNGE is `sys-auth/munge`, not `sys-cluster/munge`.
   - `app-emulation/firecracker-bin` exists but is masked.
   - No Kata Containers ebuild was found in the currently configured repos.
   - `skopeo`/containers-common wants `net-firewall/iptables[nftables]`.

   Corrective path:

   - Add a dedicated M70 package policy file for container/VM runtime USE and
     accept-keywords instead of mixing these into unrelated profile files.
   - Set `net-firewall/iptables nftables` before pulling in containers-common.
   - Accept keyword only the specific SLURM and Firecracker atoms chosen for the
     pilot.
   - Treat Kata as a separate overlay or binary-distribution decision; do not
     assume it is available from the current Gentoo repos.

4. Assign the workload network.

   Evidence:

   - `bond0` is healthy 802.3ad LACP over `enp3s0` and `eno1`, reports 2 Gbps,
     and is configured with `layer3+4` hashing.
   - `bond0` has no IPv4 address and no bridge attached.
   - `eno2`, `eno3`, and `eno4` are down and available for future workload or
     fabric roles.

   Corrective path:

   - Keep `netboot0` as stable management and rescue.
   - Put VM/container workload bridges or VLANs on `bond0` only after NetBox
     has the intended prefixes/VLANs/cables.
   - Decide whether the remaining X553 ports become additional LACP members,
     isolated storage fabric, or future tenant/workload networks.

5. Keep resolver configuration aligned with live DNS listeners.

   Evidence:

   - `172.16.99.63` is the FreeIPA identity controller, but TCP/UDP 53 is
     closed there as of 2026-05-22.
   - RouterOS DNS at `172.16.99.1` resolves internal `rfc1918.host` records and
     forwards external names.
   - The primary M70 had stale local resolver entries for `172.16.99.63` in
     `/etc/conf.d/net`, `/etc/kernel/cmdline`, and `/etc/resolv.conf`.

   Corrective path:

   - Use `172.16.99.1` as the first M70 resolver and `9.9.9.9` as fallback
     while FreeIPA DNS remains disabled.
   - Do not advertise `172.16.99.63` through netboot or static M70 profiles
     unless FreeIPA DNS is intentionally enabled and port 53 validates.
   - When boot artifacts are republished for microcode/IOMMU work, keep the
     kernel `nameserver=` argument aligned with this resolver policy.

## Build-Host Tuning

Current Portage posture is reasonable for an Atom build coordinator:

```text
MAKEOPTS="-j16 -l12"
EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=12 --getbinpkg=y --buildpkg=y --usepkg=y"
FEATURES="... buildpkg parallel-fetch distcc ..."
DISTDIR="/srv/build-cache/distfiles"
PKGDIR="/srv/build-cache/binpkgs"
```

Distcc is active as a client:

```text
172.16.99.108/48,lzo
localhost/2
```

A visible test compile was preprocessed on M70 and compiled remotely on
`172.16.99.108`. Keep this host as a scheduler/package-graph coordinator and
use X12 for heavy compile slots.

Recommended refinements:

- Keep generic `COMMON_FLAGS="-O2 -pipe"` for shared binpkgs.
- Add per-target optimized builds only through explicit profile/package policy.
- Keep `--jobs=2` unless memory pressure and link pressure remain low under real
  package builds.
- Add `FEATURES=distcc-pump` only after verifying pump mode with the active
  compiler wrappers and include paths.
- Consider moving `PORTAGE_TMPDIR` for heavy builds from ZFS root to the large
  stage disk or a dedicated dataset after measuring write amplification.

## Storage Tuning

Recommended:

- Keep ZFS root conservative and mirrored.
- Set `atime=off` on build/cache-heavy datasets after confirming no tooling
  depends on atime.
- Keep `zroot` autotrim enabled; it is already on.
- Create explicit datasets or directories for future VM images and container
  graph storage instead of placing them on `/`.
- Avoid placing high-write VM images on the USB XFS disk unless the workload is
  disposable or backed by external storage.

## Runtime Scheduler Direction

For the six M70 nodes, use roles instead of treating all nodes identically:

| Role | Suggested responsibility |
| --- | --- |
| Control-plane M70 | Forge memory, ntfy/FCP bridge, NetBox/automation clients |
| Build-coordinator M70 | Portage graph, binpkg signing/publishing, distcc client |
| Container-worker M70s | Podman/buildah/skopeo and image validation workloads |
| VM/microVM M70s | QEMU, Firecracker, bridge/VLAN validation, optional VFIO tests |
| SLURM worker M70s | Low-power always-on queue for orchestration and smoke jobs |

The C3758 is not the heavy compiler or AI compute target. Its value is stable
always-on orchestration, network-adjacent automation, low-power workers, and
distributed validation across six identical nodes.

## Canary Validation Lane

The second M70 should become the ring-0 canary for the M70 pool. It should use
the same baseline machine profile as the primary Forge M70, but with distinct
identity, NetBox records, serial path, runtime state, and workload assignment.

Approved network split:

- Intel i211 `netboot0`: primary management, iPXE, rescue, first boot.
- Intel i211 `enp3s0`: post-boot management backup.
- i211 management bond: active-backup, outside Open vSwitch.
- Intel X553 `eno1` through `eno4`: OVS-owned workload LACP trunk.
- OVS bridge `br-ovs0`: VM/container/Kata/Firecracker/QEMU/LXC workload
  networks.

Management remains the recovery path. The X553/OVS side is the intentional
blast-test area for workload networking. Promote changes from canary to primary
Forge M70 only after boot, management failover, X553 LACP, OVS, and
runtime-specific network gates pass.

Operator runbook:

- [`M70-CANARY-VALIDATION-LANE.md`](M70-CANARY-VALIDATION-LANE.md)
- [canary validation lane design](superpowers/specs/2026-05-21-m70-canary-validation-lane-design.md)

## Safe Next Actions

1. Stage the Intel+AMD microcode boot fix and verify artifact order without a
   reboot.
2. Bring the second M70 online as the ring-0 canary using the approved i211
   management and X553 OVS/LACP split.
3. Add the M70 runtime package policy for Podman/QEMU/SLURM/MUNGE and dry-run
   the merge plan on the canary first.
4. Add NetBox records for the canary workload intent before assigning OVS
   bridges, VLANs, or runtime networks.
5. Decide whether Firecracker comes from the masked Gentoo binary ebuild or a
   pinned upstream release artifact.
6. Decide whether Kata requires an overlay, binary package path, or deferral.
