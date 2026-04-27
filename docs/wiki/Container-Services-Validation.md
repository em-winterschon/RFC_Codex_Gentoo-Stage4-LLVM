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

Important fixes that made this possible:

- generic VM CPU profile support
- rebuilt `maturin` under the correct guest CPU policy
- scoped `package.unmask` support
- scoped GCC compatibility env so fallback packages do not inherit LLVM-only
  `-flto=thin`
- temporary upstream and DNS fix for the Path B lab

## Next Validation Goals

1. finish `target-integration`
2. verify Podman runtime and supporting container roles on the installed VM
3. verify `container_app_ntfy`, `container_app_nginx`, `container_app_haproxy`,
   `container_net_policy`, and `container_service_segments`
4. build the first reusable `gentoo-stage4-llvm-clang-hardened` container image
5. publish the validated image to `GHCR`
