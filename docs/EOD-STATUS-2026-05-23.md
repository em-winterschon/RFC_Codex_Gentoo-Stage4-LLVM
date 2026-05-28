# EOD Status 2026-05-23

## Completed

- Continued the M70 canary persistent Gentoo install on branch
  `m70-canary-validation-lane` and kept PR #144 as the active draft PR.
- Added `atmos-sun99-controller-020227` to NetBox/source-of-truth as a Hubitat
  C8 home automation controller at `172.16.20.227`.
- Validated M70 canary PDU control details:
  - PDU: `pdu-rfc99-corectrl-p08-099241.rfc1918.host`
  - address: `172.16.99.241`
  - outlet: `7`
  - outlet label: `m70_canary`
- Confirmed M70 canary firmware/network boot state:
  - UEFI PXE produced no DHCP traffic.
  - Legacy PXE with `Network:IBA GE Slot 0200 v1543` successfully reached the
    Gentoo live installer through the temporary iPXE shim.
  - Live installer SSH worked at `root@172.16.99.22`.
- Preserved the operator safety rule for storage:
  - install target is the mirrored KIOXIA NVMe pair
  - SATA-DOM boot media remains excluded
  - NVMe by-id paths use the padded EUI form discovered under Linux
- Completed the destructive storage foundation on the canary:
  - `rpool` mirrored over the two NVMe devices
  - first ESP mounted at `/mnt/gentoo/efi`
  - chroot bootstrap completed
- Added repo fixes needed by the canary installer:
  - ensure the target `/etc` exists before copying hostid during ZFS layout
  - include `sys-apps/gptfdisk` in the Stage5 base and K10 netboot build inputs
  - disable EFI NVRAM entry creation for the legacy-PXE installer path
  - pin the canary kernel to `=sys-kernel/gentoo-kernel-6.18.32_p2`
  - use `sys-kernel/linux-firmware` for AMD microcode coverage alongside
    `sys-firmware/intel-microcode`
- Implemented the approved compile policy:
  - canary Portage is configured for distcc client use through X12again
    `172.16.99.108/48,lzo,cpp`
  - `DISTCC_FALLBACK=0` is rendered into `make.conf`
  - `MAKEOPTS=-j48` comes from the distcc farm policy
  - local binpkg seed is published from the M70 shim at
    `http://172.16.99.70:8080/binpkgs`
  - `sys-devel/distcc` was installed from binpkg before compile-heavy work
- Removed `dev-util/ccache` from the canary bootstrap path and remaining
  build-oriented package metadata after configure/link probes showed it was not
  suitable for this stage without a matching binpkg or a separate policy.
- Removed NetworkManager from the canary lane:
  - masked `net-misc/networkmanager`
  - removed stale target package.use and configuration paths
  - removed the active installer package atom and renderer template
  - made the network role fail fast if NetworkManager is requested
- Added OpenRC networking renderers for the canary design:
  - netifrc `bond_mgmt` over `netboot0` and `enp3s0`
  - Open vSwitch `br_ovs0`
  - OVS LACP `ovs_workload0` over `eno1` through `eno4`
- Reapplied the no-compile Portage/distcc stage after policy changes.
- Started the `system_packages` stage only after distcc and no-ccache policy
  were validated.

## Verification

- `git diff --check`
  - result: pass
- YAML parse for the changed host vars, profile definitions, and netboot
  manifest
  - result: pass
- `ansible-playbook -i inventories/local-network/hosts.yml playbooks/install.yml --limit m70_canary --syntax-check`
  - result: pass
- M70 canary target Portage environment:
  - `DISTCC_HOSTS=172.16.99.108/48,lzo,cpp`
  - `DISTCC_FALLBACK=0`
  - `DISTCC_DIR=/var/cache/distcc`
  - `MAKEOPTS=-j48`
  - `FEATURES` includes `distcc`
- X12again distccd reachability:
  - M70 to `172.16.99.108:3632`: pass
  - M70 canary to `172.16.99.108:3632`: pass
- Distcc probe compiles with `DISTCC_FALLBACK=0`:
  - GCC remote compile: pass
  - Clang remote compile: pass
  - Clang hardened/LTO compile with `-c`: pass
- Target package state:
  - `sys-devel/distcc`: installed
  - `dev-util/ccache`: not installed
  - `/mnt/gentoo/var/cache/ccache`: absent
  - `/mnt/gentoo/var/tmp/portage-tmpfs/ccache-tmp`: absent
  - `/mnt/gentoo/etc/NetworkManager`: absent
  - `/mnt/gentoo/etc/portage/package.use/networkmanager`: absent
  - `net-misc/networkmanager`: masked
- `emerge --pretend --oneshot net-misc/networkmanager dev-util/ccache`
  - result: fails on the NetworkManager mask before any merge

## Current Gate

- The `system_packages` stage stopped before compiling because current Gentoo
  `net-misc/curl-8.19.0` has an unsatisfied `REQUIRED_USE` condition:
  `quic` was enabled while both `openssl` and `gnutls` were enabled.
- Root cause evidence:
  - global USE contains `gnutls`
  - the selected curl ebuild also enables `openssl`
  - curl requires exactly one TLS backend when `quic` is enabled
- No package compile was left running after this failure.
- The next fix should add an explicit curl package.use policy choosing one TLS
  backend before retrying `system_packages`.

## Active Runtime State

- Temporary RouterOS PXE/iPXE path remains pointed at the M70 shim for the
  canary lane until explicitly restored:
  - DHCP next-server: `172.16.99.70`
  - canary lease: `172.16.99.22`
  - canary boot file option: `m70-canary-undionly.kpxe`
- Temporary M70 shim services were intentionally left available for resume:
  - HTTP binpkg/iPXE shim on `172.16.99.70:8080`
  - TFTP shim on `172.16.99.70:69`
  - serial capture on the canary FT2232H path

## Outstanding Actions

1. Pin curl TLS policy, then rerun the selected `preflight,portage,distcc_farm`
   stage.
2. Retry selected `preflight,system_packages` with distcc fallback disabled.
3. After packages merge, apply boot, network, platform, and identity roles.
4. Reboot only the canary through the operator gate and validate local
   ZFSBootMenu boot.
5. Confirm `bond_mgmt` owns `172.16.99.22/24` after first local boot.
6. Restore RouterOS netboot defaults when the temporary shim is no longer
   needed.
7. Keep NetworkManager out of the M70 lane; OpenRC/netifrc and OVS are the
   approved network renderers.

## Backout Summary

- Repo changes are isolated on `m70-canary-validation-lane`.
- The canary storage work is destructive to the canary NVMe pair only; the
  SATA-DOM was excluded.
- NetworkManager remains blocked by package mask and removed installer paths.
- The temporary shim and RouterOS DHCP changes should be restored deliberately
  when canary install/resume work is complete.
