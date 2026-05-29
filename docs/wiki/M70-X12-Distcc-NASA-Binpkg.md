# M70/X12 Distcc and NASA Binpkg Contract

## Purpose

This is the P0 durable build-cache contract for M70 Forge builds that use
X12AGAIN as a compile offload worker and NASA as the durable Gentoo binary
package repository.

X12AGAIN is a distcc worker only for this path. M70 owns the Portage graph,
profile, USE flags, CPU flags, local `PKGDIR`, and final publish step.

## Repository Layout

Do not build directly into NFS. Build locally first, then publish with
`rsync` and regenerate binhost metadata.

Durable NASA layout:

```text
/mnt/nasa/forge/gentoo-binpkgs/contracts/x86_64-pc-linux-gnu/
  baseline-portable-openrc-llvm/
  m70-goldmont-openrc-llvm/
  k10-raptorlake-openrc-llvm/
  x12-icelake-server-openrc-llvm/
  r630-broadwell-openrc-llvm/
```

## Compatibility

Baseline packages use `-O2 -pipe` and avoid CPU assumptions such as
`intel_sha`, `avx`, `avx2`, and `avx512`.

Broadwell R630 hosts must not consume M70 packages that require Intel SHA. Any
CPU-tuned repository must be opt-in by host class.

## Publish Command

```bash
scripts/sync-binpkgs-to-repo.sh \
  --pkgdir /srv/build-cache/binpkgs \
  --repo-id contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm \
  --local-root /mnt/nasa/forge/gentoo-binpkgs
```

Manual metadata repair:

```bash
PKGDIR=/mnt/nasa/forge/gentoo-binpkgs/contracts/x86_64-pc-linux-gnu/baseline-portable-openrc-llvm \
  emaint binhost --fix
```

## Distcc

M70 client:

```text
172.16.99.108/48,lzo
localhost/2
```

X12AGAIN worker:

```text
listen_address: 172.16.99.108
allowed_client_cidrs:
  - 172.16.99.70/32
jobs: 48
```
