# M70 LLVM/Clang Portage Optimization Analysis

## Scope

This analysis reviews the M70 Forge Portage notes from:

- `/root/operator-private/ephemeral-notes/2026-0528/CRITICAL-PATH/2026-0528_m70-forge-portage.make.conf_optimize.md`
- `/root/operator-private/ephemeral-notes/2026-0528/CRITICAL-PATH/2026-0528_m70-forge-portage.system-packages.shx`

The goal is to convert the notes into a safe M70 canary validation plan for
LLVM/Clang `make.conf`, `/etc/portage` fragments, package USE policy, and the
additional system package set. The source scripts are intentionally not copied
as runnable shell scripts; the repo should own profile data and Ansible-rendered
Portage controls, not ad hoc host-local commands.

## Current repo baseline

The existing M70 automation-admin baseline already has the right integration
points:

- `profile-definitions/metal-forge-automation-admin.yml` owns package lists,
  `make_conf_append`, `package_use_files`, extra Portage config files, kernel
  modules, OpenRC service enables, telemetry, and automation-admin metadata.
- `profile-package-lists/stage5-metal-forge-automation-admin.packages` owns the
  current M70 operator package set.
- `roles/portage/templates/make.conf.j2` generates an LLVM/Clang-oriented
  `make.conf` with `CC=clang`, `CXX=clang++`, LLVM binutils, `LDFLAGS` using
  `lld`, `RUSTFLAGS`, `CPU_FLAGS_X86`, binpkg controls, and rendered USE flags.
- `vars/cpu_profiles.yml` is the authoritative place for CPU profile names and
  `-march`/`-mtune` choices.
- `inventories/local-network/host_vars/admin_sun99_forge_099070.yml` already
  enables M70 build-cache behavior: `buildpkg`, `getbinpkg`, `usepkg`,
  `/srv/build-cache/binpkgs`, `distcc`, `MAKEOPTS` equivalent `16 -l12`, and
  NASA binpkg publishing paths.
- `docs/M70-X12-DISTCC-NASA-BINPKG.md` explicitly separates portable baseline
  binpkgs from M70-host-tuned binpkgs.

That means the implementation should be profile-data changes plus a canary
runbook, not a direct transplant of the one-off `make.conf` draft.

## Review of proposed `make.conf` notes

| Proposed setting | Assessment | Recommended handling |
| --- | --- | --- |
| `COMMON_FLAGS="-O3 -march=native -mtune=native -pipe -flto=thin ..."` | Too aggressive for the shared baseline. `-march=native` breaks reusable binpkg contracts and can miscompile when X12AGAIN performs distcc work for M70-targeted packages. Global ThinLTO and `-O3` will increase failure surface and memory pressure on an 8-core/31 GiB/no-swap host. | Keep `baseline-portable-openrc-llvm` at conservative `-O2 -pipe`. Add a separate M70-only profile after canary validation, preferably `-O2 -pipe -march=goldmont -mtune=goldmont`, then evaluate ThinLTO through package-scoped `package.env` allowlists. |
| `WARNING_FLAGS="-Werror=odr -Werror=strict-aliasing"` | Dangerous globally. Turning warnings into errors across Gentoo packages makes unrelated upstream warnings block OS rebuilds. | Do not set globally. Use package-scoped env only for packages being actively debugged. |
| `CC=clang`, `CXX=clang++`, `LD=ld.lld` | Directionally correct; repo template already sets `CC`, `CXX`, LLVM binutils, and lld linker flags. | Prefer the existing template path; add `LD`, `STRIP`, `OBJCOPY`, `OBJDUMP`, and `READELF` only after lint/render tests prove parse-safe output. |
| `AR=llvm-ar`, `NM=llvm-nm`, `RANLIB=llvm-ranlib` | Already in repo template. | Keep. |
| `LDFLAGS="... -fuse-ld=lld"` | Already effectively present in repo template. | Keep in template, do not duplicate in host-local append unless a package-specific override is needed. |
| `ACCEPT_KEYWORDS="~amd64"` | Not acceptable as a global fleet baseline. It widens the entire OS to unstable keywords and makes canary results hard to interpret. | Use `package.accept_keywords` fragments only for specific package atoms that require `~amd64`. |
| `USE="lto"` globally | High risk. Many packages need package-specific LTO exclusions. | Add a `thin-lto.conf` env fragment and package allowlist after canary evidence. |
| `PYTHON_TARGETS="python3_12 python3_13 python3_14"` and `PYTHON_SINGLE_TARGET="python3_14"` | Too far ahead without a package graph. Could force unstable Python slots or unsatisfied dependencies. | Keep current profile defaults until `emerge -pvDN @world` proves the exact target set. |
| `RUSTFLAGS="-C target-cpu=native ... -Clinker-plugin-lto"` | Host-native Rust plus linker-plugin-LTO is risky for generic packages and distcc/binpkg reuse. | Keep template `RUSTFLAGS="-C target-cpu={{ selected_cpu_profile.rust_target_cpu }}"`. Evaluate DT_RELR separately if the toolchain/binutils/glibc path supports it. |
| `MAKEOPTS="-j16 -l12"` with `EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=12 ..."` | Reasonable only with distcc and careful memory monitoring. Local C++/Rust/LTO spikes can exceed memory. | Keep as M70 canary start point, but record load, memory, swap absence, and failed package classes. |
| `FEATURES="buildpkg parallel-fetch distcc"` | Matches existing M70 host intent. | Keep. Consider `parallel-install` only after package-manager stability is confirmed. |
| `DISTDIR`/`PKGDIR` under `/srv/build-cache` | Matches existing M70 local-build-first policy. | Keep. Do not build directly into NASA NFS. |
| `PORTAGE_BINPKG_FORMAT=tar`, `BINPKG_COMPRESS=zstd`, `-2` | Matches existing template defaults. | Keep. |
| M70 `CPU_FLAGS_X86` captured from hardware | Good and necessary. | Store as `cpu_flags_x86_override` after recapturing on the canary with the current microcode/profile. |

## CPU and binpkg profile decision

M70 is an Intel Atom C3758 / Goldmont-class host. The repo currently has no
explicit `intel_atom_c3758_goldmont` profile in `vars/cpu_profiles.yml`, and
the generic install defaults use `x86_64_v2_generic` unless a host override is
set.

Recommended profile split:

1. **Portable baseline contract**: keep `baseline-portable-openrc-llvm` on
   conservative flags suitable for heterogeneous x86_64 consumers. Do not use
   M70 native flags here.
2. **M70-only contract**: add `m70-goldmont-openrc-llvm` after canary testing.
   Candidate compile flags:
   - `COMMON_FLAGS="-O2 -pipe -march=goldmont -mtune=goldmont"`
   - `RUSTFLAGS="-C target-cpu=goldmont"` only after Rust validates that target
     name in the installed toolchain.
   - M70 CPU flags from live `cpuid2cpuflags`, expected to remain in the
     no-AVX Goldmont shape captured in the notes.
3. **Experimental LTO lane**: package-scoped ThinLTO only. Do not combine
   global `-O3`, global ThinLTO, and global unstable keywords in the first
   overnight rebuild.

The X12AGAIN distcc worker must continue compiling for the requesting M70
flags. Never let `-march=native` leak to X12AGAIN for M70-targeted builds.

## Distcc worker expansion from FCP note

The 2026-05-25 Forge control-plane distcc note adds one validated FMT2 worker
next to X12AGAIN. The approved canary host string is:

```text
DISTCC_HOSTS="10.200.99.23/24,lzo 172.16.99.108/48,lzo localhost/2"
MAKEOPTS="-j16 -l12"
```

Validated worker facts from the note:

| Worker | Address | Service shape | Capacity | Recommended M70 slots | Caveat |
| --- | --- | --- | ---: | ---: | --- |
| `kvm-sfo200-sec-9923.rfc1918.host` | `10.200.99.23:3632` | Podman/OCI `distccd`, host networking | `jobs=56` | `24` | Fallback-disabled smoke passed from M70, but durable managed Podman/OCI service persistence still needs validation before assuming reboot survival. |
| `x12again.rfc1918.host` | `172.16.99.108:3632` | OpenRC `distccd` | `jobs=48` | `48` | Existing M70/X12 worker; still must compile for M70-requested flags, never worker-native flags. |

Canary validation should test each worker independently before using the combined
`DISTCC_HOSTS` string. Capture `distccmon-text`, worker logs, and
fallback-disabled compile smoke evidence before starting large `@system` or
`@world` rebuild stages.

## Review of additional system packages

The package notes ask for:

```text
app-admin/su-exec
dev-libs/jemalloc
dev-util/marksman
net-analyzer/slurm
net-misc/axel
sys-process/bashtop
sys-process/ctop
sys-process/gotop
sys-process/iotop
sys-process/lsof
sys-process/memwatch
sys-process/nmon
sys-process/numactl
sys-process/numad
sys-process/nvtop
sys-process/prll
sys-process/procenv
sys-process/procps
sys-process/procs
sys-process/psinfo
sys-process/psmisc
sys-process/rtirq
sys-process/schedtool
sys-process/supervise-scripts
sys-process/time
sys-process/tiptop
sys-process/wait_on_pid
```

Comparison against the current M70 package list:

- Already present or represented: `sys-process/lsof` is present; process and
  monitoring tooling already includes `htop`, `psmisc`, `nut`, `smartmontools`,
  and core operator packages.
- Strong candidates for M70 automation-admin: `dev-libs/jemalloc`,
  `net-misc/axel`, `sys-process/iotop`, `sys-process/numactl`,
  `sys-process/numad`, `sys-process/nmon`, `sys-process/procps`,
  `sys-process/rtirq`, `sys-process/schedtool`, `sys-process/time`.
- Slurm-specific: `net-analyzer/slurm` belongs in Slurm controller/worker
  profiles unless the M70 canary is explicitly acting as a Slurm host.
- UI/operator preference tools: `bashtop`, `ctop`, `gotop`, `procs`, `tiptop`,
  `psinfo`, `procenv`, `memwatch`, `prll`, `supervise-scripts`, `wait_on_pid`,
  `marksman`, `su-exec`, and `nvtop` need repo availability and keyword checks
  before baseline inclusion.
- `nvtop` should not be a required M70 baseline unless GPU telemetry is useful
  on that host class.

Implementation should add packages to the profile package list only after a
canary `emerge -pv` proves package availability and required keyword/USE
fragments. Do not set global `ACCEPT_KEYWORDS=~amd64` to force this list.

## Candidate `/etc/portage` controls

The notes should become profile fragments under `metal-forge-automation-admin`
or a new M70 canary profile extension:

### `make_conf_append`

Keep M70-specific additions minimal:

```conf
# M70 build-cache directories and binpkg settings are rendered by inventory.
# Do not put -march=native, global -O3, or global ThinLTO here.
```

Most current settings should remain rendered from inventory variables and
`roles/portage/templates/make.conf.j2`.

### `package.use`

Potential canary-only fragments:

```text
# LLVM/lld defaults, if exposed by selected Gentoo packages.
sys-devel/clang default-lld
llvm-core/clang default-lld

# NFS and identity are already present in the profile but should remain explicit.
net-fs/nfs-utils kerberos nfsv4 nfsv41
sys-auth/sssd ssh sudo
```

The exact atoms must be verified against the M70 Portage tree before commit.

### `env` and `package.env`

Use package-scoped ThinLTO only:

```conf
# /etc/portage/env/clang-thinlto.conf
CFLAGS="${CFLAGS} -flto=thin"
CXXFLAGS="${CXXFLAGS} -flto=thin"
LDFLAGS="${LDFLAGS} -Wl,-O2"
```

Then attach it only to packages that pass canary rebuilds:

```text
# /etc/portage/package.env/90-m70-thinlto
# category/package clang-thinlto.conf
```

### `package.accept_keywords`

Only add explicit atoms after `emerge -pv` identifies keyword masks. Avoid a
catch-all `*/* ~amd64` or global `ACCEPT_KEYWORDS=~amd64`.

## M70 canary overnight validation plan

The canary rebuild should be executed in stages and leave enough evidence to
revise the profile safely.

### Stage 0 - preflight and snapshot

1. Confirm the target is the intended M70 canary, not the production
   automation-admin host unless explicitly selected.
2. Capture:
   - `emerge --info`;
   - `clang --version`, `ld.lld --version`, `rustc -Vv` if installed;
   - `cpuid2cpuflags`;
   - `free -h`, `swapon --show`, `nproc`, `lscpu`;
   - `/etc/portage` tarball;
   - current `world` file;
   - current binpkg repo and Portage logs.
3. Confirm OOB/power backout is available and root break-glass still works.

### Stage 1 - render candidate profile without mutation

Run the Ansible render/syntax path first. Expected repo-side commands:

```bash
python3 scripts/lint_portage_profiles.py
ansible-playbook --syntax-check \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/install.yml
```

Then run a canary-limited check/diff apply of Portage configuration before any
rebuild.

### Stage 2 - conservative M70 build baseline

Use the existing LLVM/Clang profile style, with M70 CPU flags captured but no
global LTO or `-O3`:

```text
COMMON_FLAGS="-O2 -pipe -march=goldmont -mtune=goldmont"
FEATURES="buildpkg parallel-fetch distcc"
MAKEOPTS="-j16 -l12"
EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=12 --buildpkg=y --getbinpkg=y --usepkg=y --with-bdeps=y --complete-graph=y --binpkg-respect-use=y --binpkg-changed-deps=y --verbose-conflicts"
```

Validation commands on the canary:

```bash
emerge -pvDN @system
emerge -pvDN @world
emerge -e --keep-going --jobs=2 @system
```

Only move to `@world` after `@system` is clean and the package list pretend
output is reviewed.

### Stage 3 - package-list validation

For the package list from the notes:

```bash
emerge -pv --oneshot \
  app-admin/su-exec dev-libs/jemalloc dev-util/marksman net-analyzer/slurm \
  net-misc/axel sys-process/bashtop sys-process/ctop sys-process/gotop \
  sys-process/iotop sys-process/lsof sys-process/memwatch sys-process/nmon \
  sys-process/numactl sys-process/numad sys-process/nvtop sys-process/prll \
  sys-process/procenv sys-process/procps sys-process/procs sys-process/psinfo \
  sys-process/psmisc sys-process/rtirq sys-process/schedtool \
  sys-process/supervise-scripts sys-process/time sys-process/tiptop \
  sys-process/wait_on_pid
```

Record which atoms are unavailable, keyword-masked, require USE changes, or are
role-specific rather than baseline M70 packages.

### Stage 4 - experimental ThinLTO lane

After conservative rebuild evidence exists:

1. Select a small package allowlist.
2. Apply `package.env` ThinLTO only for that allowlist.
3. Rebuild with `--oneshot --buildpkg=y`.
4. Run package smoke tests and `revdep-rebuild`/`preserved-rebuild` checks.
5. Promote only successful package-specific settings.

Do not run global ThinLTO overnight as the first experiment.

## Acceptance criteria for the next implementation branch

The next implementation branch should land only repo-side, testable changes:

1. Add `intel_atom_c3758_goldmont` to `vars/cpu_profiles.yml` after verifying
   compiler target support.
2. Set the M70 canary host to that CPU profile and captured
   `CPU_FLAGS_X86` only if live recapture agrees with the notes.
3. Add a canary profile extension or profile metadata for the package-list
   candidates that passed `emerge -pv`.
4. Add package-specific `package.use`, `package.accept_keywords`, `env`, and
   `package.env` fragments only for proven needs.
5. Update `docs/M70-X12-DISTCC-NASA-BINPKG.md` so the portable and M70-tuned
   contracts remain separate.
6. Add/extend shell tests for:
   - M70 CPU profile presence;
   - no global `ACCEPT_KEYWORDS=~amd64` in M70 profile data;
   - no global `-march=native`, `-O3`, `-flto=thin`, or `-Werror` in the M70
     baseline;
   - package-list additions are tracked by profile data, not `.shx` scripts.

## Backout and safety notes

- Keep `/etc/portage` backup and the previous `make.conf` available on the
  canary.
- Keep local root SSH and OOB/PDU control available before rebuilding PAM,
  OpenSSH, SSSD, sudo, kernels, or OpenRC.
- Do not publish M70-tuned binpkgs into `baseline-portable-openrc-llvm`.
- Do not run global unstable keywording to make the package list succeed.
- Do not run `emerge -e @world` on the production automation-admin host without
  first proving the same settings on the M70 canary.

## Open questions for live validation evidence

- What inventory key represents the M70 canary distinct from
  `admin_sun99_forge_099070`?
- Does the installed M70 Clang accept `-march=goldmont` and does Rust accept
  `target-cpu=goldmont`?
- Which package atoms from the `.shx` package list are absent or keyword-masked
  in the current Gentoo tree?
- Is M70 using the active-backup management bond only, or has the canary host
  validated multiple LACP links for NFS/build-cache traffic?
- How much memory headroom remains during large Rust/LLVM/C++ packages with
  `--jobs=2`, `MAKEOPTS=-j16 -l12`, no swap, and distcc enabled?
