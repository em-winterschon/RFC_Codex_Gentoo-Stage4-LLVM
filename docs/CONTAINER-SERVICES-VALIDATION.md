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

### Current Path B upstream workaround

For the live `10.9.8.0/24` lab, the current temporary upstream path is:

- guest default route override to `10.9.8.108`
- explicit `resolv.conf` population in the provisioner and target
- host-side IPv4 forwarding and NAT on the Gentoo control host

This is a temporary lab workaround. The long-term fix is a proper upstream
route or second WAN-facing NIC on the RouterOS Path B gateway.

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

Important fixes that made this possible:

- generic VM CPU profile support
- rebuilt `maturin` under the correct guest CPU policy
- scoped `package.unmask` support
- scoped GCC compatibility env so fallback packages do not inherit LLVM-only
  `-flto=thin`
- temporary upstream and DNS fix for the Path B lab
- netavark-safe network bootstrap helper without forced `interface_name`
- explicit `ntfy` runtime data directory provisioning
- explicit `nginx` cache/temp directory provisioning
- target-side `iptables` frontend selection to `xtables-nft-multi`
- app-specific capability overrides for hardened containers:
  - `nginx`: `CHOWN`, `SETGID`, `SETUID`

## Remaining Known Issue

- the OpenRC `nftables` service currently conflicts with netavark-managed rules
  when it reloads `/var/lib/nftables/rules-save`
- containers still start and serve traffic correctly, but the site firewall and
  netavark rules need cleaner ownership boundaries before this is considered
  production-clean

## Next Validation Goals

1. resolve the `nftables` vs netavark ruleset ownership conflict cleanly
2. validate the same container-services stack on the installed target boot, not
   only in the provisioner chroot
3. build the first reusable `gentoo-stage4-llvm-clang-hardened` container image
4. publish the validated image to `GHCR`
