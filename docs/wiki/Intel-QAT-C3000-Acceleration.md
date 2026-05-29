# Intel C3000 QAT Acceleration Plan

## Scope

The M70 nodes use Intel Atom C3000 processors with on-die Intel QuickAssist
Technology. The first validated node exposes:

- PCI device: `01:00.0 Intel Atom Processor C3000 Series QuickAssist Technology`
- PCI ID: `8086:19e2`
- observed driver: `c3xxx`
- kernel modules: `intel_qat`, `qat_c3xxx`
- firmware names reported by `modinfo qat_c3xxx`: `qat_c3xxx.bin`,
  `qat_c3xxx_mmp.bin`

The platform profile now includes `sys-firmware/intel-microcode` and
`sys-kernel/linux-firmware` through the reusable
`stage5-metal-intel-platform` package layer. This layer should be attached to
Intel bare-metal profiles by default and kept out of non-Intel hardware roles.
It is currently referenced by the M70 Forge automation-admin profile, the M70
builder-farm node profile, the X12AGAIN workstation/hypervisor profile, and the
generic Xen/QEMU/Libvirt hypervisor profile.

For C3000 M70 service roles, QAT is most valuable first as a TLS and compression
offload path: OpenSSL consumers such as HAProxy and Nginx can be benchmarked for
request-per-second gains before any production listener is switched. Treat
operator-observed 1.5x-2x TLS RPS improvements as a hypothesis until this
infrastructure has local before/after measurements with the exact kernel,
OpenSSL, QAT, cipher-suite, and HAProxy or Nginx versions in use.

## Current State

M70 QAT is kernel-ready, not application-enabled. Live validation showed the
running Gentoo kernel already has:

- `CONFIG_CRYPTO_DEV_QAT_C3XXX=m`
- `CONFIG_CRYPTO_DEV_QAT_C3XXXVF=m`

The `metal-forge-automation-admin` profile loads `intel_qat` and `qat_c3xxx`.
Consumer acceleration stays disabled until explicit benchmark and rollback gates
are built for each workload.

## Consumer Enablement Order

1. Kernel and firmware readiness: validate PCI device, kernel module, firmware
   files, service state, and dmesg without enabling production consumers.
2. OpenSSL: validate provider or engine wiring with repeatable `openssl speed`
   baselines before HAProxy or Nginx changes.
3. HAProxy TLS: benchmark local TLS requests per second against the same cipher
   suites with QAT disabled and enabled.
4. Nginx TLS: repeat the same TLS and latency baseline if Nginx terminates
   service traffic directly.
5. OpenZFS+QAT: build in a dedicated CI/CD lane only. Do not mutate the normal
   `sys-fs/zfs` profile until a reproducible package, kernel compatibility
   matrix, and rollback path exist.

## OpenZFS Policy

OpenZFS+QAT is a separate artifact lane because Gentoo bug 718026 records that
QAT support for ZFS is not a normal out-of-box ebuild path and has historically
required external QAT source/package handling and compatibility work. The
private CI lane must produce:

- exact kernel, QAT, and OpenZFS versions
- applied patches and source provenance
- binpkg and build logs
- module-load and service-order policy
- benchmark artifacts for compression, encryption, and checksum workloads
- rollback command path to stock OpenZFS packages

## Validation Commands

```sh
lspci -nnk | grep -i -A5 'quickassist\|qat'
modinfo qat_c3xxx
lsmod | grep -E 'intel_qat|qat_c3xxx'
dmesg | grep -i qat
grep -E 'CONFIG_CRYPTO_DEV_QAT(_C3XXX|_C3XXXVF)?=' /boot/config-$(uname -r)
```

## References

- Local Intel release notes:
  `/tmp/docs/intel/Intel-QAT-Latest-8960-C3000.pdf`
- Local Intel network-edge reference architecture:
  `/tmp/docs/intel/Intel-Network-Edge-Container-Metal-Reference-Systems-Architecture-User-Guide.1706608508.pdf`
- OpenZFS QAT overview:
  `https://openzfs.org/wiki/ZFS_Hardware_Acceleration_with_QAT`
- Gentoo QAT/ZFS enhancement tracker:
  `https://bugs.gentoo.org/718026`
- Experimental Gentoo OpenZFS+QAT overlay reference:
  `https://github.com/bugalo/ZFS-QAT-gentoo`
