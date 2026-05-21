# M70/X12 Distcc and NASA Binpkg Contract

## Purpose

This is the P0 durable build-cache contract for M70 Forge builds that use
X12AGAIN as a compile offload worker and NASA as the durable Gentoo binary
package repository.

The live proof point on 2026-05-21 was:

- M70 built `app-misc/hello-2.12.3` through Portage with `FEATURES=distcc`.
- X12AGAIN `distccd` logged `COMPILE_OK` clang jobs from M70 `172.16.99.70`.
- M70 kept `COMMON_FLAGS="-O2 -pipe"` so the produced binpkgs were generic,
  not M70-tuned.

X12AGAIN is a distcc worker only for this path. M70 owns the Portage graph,
profile, USE flags, CPU flags, local `PKGDIR`, and final publish step.

## Current Live Roles

M70:

- host: `admin-sun99-forge-099070.rfc1918.host`
- management IP: `172.16.99.70`
- local `PKGDIR`: `/srv/build-cache/binpkgs`
- NASA NFS mount: `/mnt/nasa`
- default publish root: `/mnt/nasa/forge/gentoo-binpkgs`
- default contract: `baseline-portable-openrc-llvm`

X12AGAIN:

- host: `x12again.rfc1918.host`
- worker IP: `172.16.99.108`
- `distccd` port: `3632`
- allowed client: `172.16.99.70/32`
- worker jobs: `48`

Guardrail: X12AGAIN must compile for the requesting client's explicit target
flags. Never use `-march=native` for M70-targeted builds on X12AGAIN.

## Repository Layout

Do not build directly into NFS. Build locally first, then publish with
`rsync` and regenerate binhost metadata.

Durable NASA layout:

```text
/mnt/nasa/forge/gentoo-binpkgs/
  contracts/
    x86_64-pc-linux-gnu/
      baseline-portable-openrc-llvm/
      m70-goldmont-openrc-llvm/
      k10-raptorlake-openrc-llvm/
      x12-icelake-server-openrc-llvm/
      r630-broadwell-openrc-llvm/
    aarch64/
    ppc64le/
```

The first implementation target is:

```text
/mnt/nasa/forge/gentoo-binpkgs/contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm
```

The Portage consumer URI should eventually be exposed over HTTP. Until HAProxy
or nginx fronts the repository, a local M70 validation can point directly at a
file path or use the NFS-backed publish path as a staging primitive.

Example future consumer setting:

```bash
PORTAGE_BINHOST="http://binpkgs.rfc1918.host/contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm"
```

## Compatibility Classes

Compatibility is not just `CHOST`. It is the combination of:

- `CHOST`
- Gentoo profile
- USE flags
- `CPU_FLAGS_X86`
- compiler/runtime ABI
- libc
- Python/Lua/Rust target state
- package masks, keywords, and accepted licenses

Baseline packages:

- contract: `baseline-portable-openrc-llvm`
- flags: `-O2 -pipe`
- intent: broad x86_64 reuse across heterogeneous RFC1918 hosts
- avoid CPU assumptions: `intel_sha`, `avx`, `avx2`, `avx512`

Host-tuned package classes:

- `m70-goldmont-openrc-llvm`: Atom C3758/Goldmont, M70 only unless proven compatible.
- `k10-raptorlake-openrc-llvm`: 13th-gen Intel Core/Raptor Lake K10 class.
- `x12-icelake-server-openrc-llvm`: Xeon Platinum 8370C/Ice Lake server class.
- `r630-broadwell-openrc-llvm`: Dell R630 E5-2600v4/Broadwell class.

Broadwell R630 hosts must not consume M70 packages that require Intel SHA. The
baseline repository must therefore stay conservative, and any CPU-tuned
repository must be opt-in by host class.

## Publish Command

Publish M70 local generic packages into the baseline contract:

```bash
scripts/sync-binpkgs-to-repo.sh \
  --pkgdir /srv/build-cache/binpkgs \
  --repo-id contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm \
  --local-root /mnt/nasa/forge/gentoo-binpkgs
```

After publishing, ensure metadata exists:

```bash
PKGDIR=/mnt/nasa/forge/gentoo-binpkgs/contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm \
  emaint binhost --fix
```

The helper already runs `emaint binhost --fix` for local publishes when
`emaint` is available. The explicit command above is the manual repair path.

## Distcc Operations

M70 client settings:

```text
/etc/distcc/hosts:
172.16.99.108/48,lzo
localhost/2
```

M70 Portage policy:

```text
FEATURES="buildpkg parallel-fetch distcc"
MAKEOPTS="-j16 -l12"
PKGDIR="/srv/build-cache/binpkgs"
```

X12AGAIN worker policy:

```text
listen_address: 172.16.99.108
allowed_client_cidrs:
  - 172.16.99.70/32
jobs: 48
service_user: distcc
```

If compile failures appear, first check:

```bash
ssh forge 'cat /etc/distcc/hosts'
rc-service distccd status
tail -n 100 /var/log/distccd.log
```

## Next Automation Steps

1. Apply the repo inventory settings for M70 and X12AGAIN via Ansible after
   confirming the live values still match.
2. Publish the first baseline snapshot from M70 to NASA.
3. Add an HTTP frontend for NASA binpkgs through HAProxy/nginx.
4. Add a binhost consumer config for M70 that prefers the baseline contract and
   only opts into host-tuned contracts when explicitly selected.
5. Add log rotation for X12AGAIN `/var/log/distccd.log`.
