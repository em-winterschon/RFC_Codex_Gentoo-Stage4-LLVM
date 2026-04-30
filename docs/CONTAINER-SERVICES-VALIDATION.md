# Container-Services Validation

## Current Scope

This document tracks the first end-to-end validation of the `vm-container-services`
Stage 5 overlay on top of the Stage 4 Gentoo LLVM/Clang hardened baseline.

Current validation path:

- Path B UEFI/iPXE provisioner boot
- QEMU VM target
- single-disk ZFS target layout for the container-services test VM
- Podman/container stack install through the staged Ansible workflow

## Validated Decisions

### CPU tuning for generic VMs

For generic virtual guests and container builders, prefer:

- `x86_64_v2_generic`
- `x86_64_v3_generic`

Do not use host-specific microarchitecture profiles such as `znver4` or
specific cloud Xeon targets for generic guest images unless the guest fleet is
known to match that CPU contract.

Reason:

- Python/Rust build helpers such as `maturin` may be compiled early in the
  provisioning process.
- If they are compiled for a CPU that does not match the target VM, later wheel
  builds can fail with `invalid opcode` traps even when Portage itself looks
  correct.

## Current Feature Usage

### Stage language

- `Stage 4`
  - shared LLVM/Clang, OpenRC, hardening, and Portage policy baseline
- `Stage 5`
  - host or service role overlay

The container host uses:

- Stage 4 baseline
- `cloud-init-vm` overlay
- `vm-guest-simple-ipxe` overlay
- `vm-container-services` overlay

### Container host policy

- default repo stance remains `without-systemd`
- a narrow `sys-apps/systemd-utils` exception is allowed only where the
  Podman/netavark stack requires it
- the exception must remain package-scoped and must not become a system-wide
  dependency policy

### Hypervisor-side memory drives

The container-services VM can consume tmpfs-backed ephemeral disks prepared on
the QEMU host. This is intended for:

- Portage scratch and cache acceleration
- temporary container/image storage
- faster ephemeral validation cycles on high-memory build hosts

### Current Path B upstream

For the live `10.9.8.0/24` lab, the current upstream path is:

- RouterOS Path B gateway at `10.9.8.1`
- RouterOS WAN address `192.168.1.222/24` on `pathb-wan`
- upstream gateway `192.168.1.254`
- DNS via RouterOS remote requests to `9.9.9.9` and `8.8.8.8`
- LAN-to-WAN masquerade for `10.9.8.0/24`

## Current Validation Progress

Validated so far:

- Path B UEFI boot via embedded `ipxe.efi`
- provisioner SSH reachability
- `storage-foundation` pass on the container-services VM
- `chroot-bootstrap` pass on the container-services VM
- `target-integration` moved past the earlier blockers:
  - `dev-python/rpds-py`
  - `dev-python/cryptography`
  - `app-containers/buildah`
  - `app-containers/skopeo`
- package transaction advanced into later system and container-host packages
- Podman runtime validation inside the target chroot:
  - `nginx` container up on `0.0.0.0:8080`
  - `ntfy` container up on the internal `apps` segment
  - `haproxy` container up on `0.0.0.0:80` and `0.0.0.0:443`
  - `curl -I http://127.0.0.1:8080/` returns `200 OK`
  - `curl -I http://127.0.0.1:80/` returns `200 OK` through haproxy
  - `rc-service nftables restart` succeeds without clobbering the running
    netavark-managed container rules

Important fixes that made this possible:

- generic VM CPU profile support
- rebuilt `maturin` under the correct guest CPU policy
- scoped `package.unmask` support
- scoped GCC compatibility env so fallback packages do not inherit LLVM-only
  `-flto=thin`
- RouterOS-backed upstream and DNS for the Path B lab
- phased container rootfs build bootstrap for compiler/runtime sysroot
  prerequisites before the main image graph
- clang sysroot ABI checks for both C and C++ before entering the long
  package closure
- netavark-safe network bootstrap helper without forced `interface_name`
- explicit `ntfy` runtime data directory provisioning
- explicit `nginx` cache/temp directory provisioning
- target-side `iptables` frontend selection to `xtables-nft-multi`
- OpenRC `nftables` service pinned to the managed static `/etc/nftables.conf`
  instead of saving and reloading dynamic netavark state
- app-specific capability overrides for hardened containers:
  - `nginx`: `CHOWN`, `SETGID`, `SETUID`

## Next Validation Goals

1. validate the same container-services stack on the installed target boot, not
   only in the provisioner chroot
2. build the first reusable `gentoo-stage4-llvm-clang-hardened` container image
3. publish the validated image to `GHCR`

## Build Graph Control

The rootfs container builder now supports `--bootstrap-runtime-seed auto`.
The live container profile uses this as the first bootstrap path. It copies the
host Clang runtime library/linker-script chains into the target rootfs before
Portage enters the long dependency graph:

- `libunwind.so`
- `libc++.so`
- `libc++_shared.so`
- `libc++abi.so`

This avoids pulling `llvm-core/llvm` into a separate bootstrap emerge. That
earlier package-bootstrap path fixed the missing `libunwind` symptom but
created a larger failure surface by compiling full LLVM before the main graph.

After seeding, the builder verifies default clang C and C++ links against the
target rootfs before starting the main graph. The normal Portage transaction
still installs the real `llvm-runtimes/*` packages and produces binpkgs, so the
seed is only a sysroot continuity bridge. While runtime seeding is enabled, the
builder disables `collision-protect` for the controlled rootfs seed files so
Portage can replace them with package-owned runtime files.

`--bootstrap-package-list` remains available as an explicit fallback or
diagnostic path, but it should not be the default for this profile because it
can drag the full LLVM build into the bootstrap phase.
