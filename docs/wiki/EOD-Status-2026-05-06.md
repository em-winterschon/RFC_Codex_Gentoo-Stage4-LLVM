# EOD Status 2026-05-06

## Completed

- Advanced the Stage5 workstation profile from QEMU-only validation into the
  Hasslehoff GPU validation path.
- Proxmox VM `1094`, `vm-workstation-nscde-gpu01`, is live at `172.16.99.94`
  with:
  - K1200 VGA/audio passthrough
  - serial console for boot visibility
  - management networking plus tagged `vmbr-qlogic0` fallback networking
  - NVIDIA R580 and CUDA 12.9.1 validated earlier with `nvidia-smi` and `nvcc`
- Validated the PiKVM video path enough for deterministic GPU output testing.
  The managed NVIDIA Xorg policy displays the K1200 test pattern correctly in
  Direct H.264 mode.
- Brought the local ntfy service online on Hasslehoff container-services:
  - long DNS name: `msg-sun99-ntfysys-099096.rfc1918.host`
  - CNAME: `msg-sun99-ntfysys.rfc1918.host`
  - VIP: `172.16.99.96`
  - LAN HTTP endpoint: `http://msg-sun99-ntfysys.rfc1918.host`
- Established current notification topics:
  - alerts: `codex-alerts-rfc99-sun99-3457621907`
  - replies: `codex-replies-rfc99-sun99-3457621907`
  - general: `rfc99-sun99-3457621907`
- Added and validated the GMKtek K10 as the next low-blast-radius bare-metal
  Stage5 workstation validation target in documentation and inventory intent.
- Confirmed the K10 physical discovery attempt is gated on firmware/boot-order
  work, not on continuing blind network polling.
- Updated the workstation profile Intel metrics patch so the next rerun removes
  upstream `-flto`, `-fPIE`, and linker `-pie` flags using context that matches
  the extracted Gentoo source.
- Queued a second guarded package-build rerun on the live workstation VM. It
  waits for the active `emerge` to exit, skips if the Intel stack finished, or
  reruns with the corrected Intel metrics patch and existing binpkgs.
- Draft PR `#20` remained green at commit
  `f61b75d8f0c686d4e82fcdaf6b72df88e580c973` before the EOD documentation
  update:
  - `pre-commit`: pass
  - `shell-tests`: pass
  - notification checks: pass

## Current Gates

- The workstation Intel/K10 package build is still in progress on
  `172.16.99.94`.
- Earlier package run status:
  - reached `25/42` completed before exiting unsuccessfully
  - `dev-libs/intel-metrics-library-1.0.209.1` failed in `src_prepare` because
    the previous user patch had stale context
  - `llvm-core/llvm-16.0.6-r5` also failed late in the previous run and needs
    post-current-run log review if it fails again
- Current rerun status observed near EOD:
  - active `emerge --jobs=2 --load-average=10`
  - reused early binpkgs through at least `5/28`
  - active work included `llvm-core/llvm-16.0.6-r5`
  - binpkg cache observed at `5.7G` and `437` files under `/var/cache/binpkgs`
- K10 is physically connected to CSS326 `ge16`, but no confirmed K10 DHCP/iPXE
  lease was observed.
- Address `172.16.99.160` is not safe to assume as K10. It showed conflicting
  ARP/MAC evidence and an existing OpenSSH/rpcbind host.
- PR `#20` should stay draft until the live workstation package gates are
  resolved and the EOD commit checks are green.

## Outstanding Actions

1. Let the active workstation `emerge` finish, then inspect the fixed-patch
   watcher log:
   `/var/log/stage5-gpu-intel-build-fixed-intel-metrics-patch-rerun.log`.
2. If `llvm-core/llvm-16.0.6-r5` fails again, inspect the fresh build log before
   choosing between a targeted USE policy change, binary reuse strategy, or
   reduced Intel/AMDGPU stack closure.
3. Connect K10 to a PiKVM or local display, enable UEFI PXE/iPXE boot, and
   capture the NIC MAC from firmware or first DHCP request.
4. Resolve the `172.16.99.160` duplicate/unknown host state before assigning a
   K10 reservation.
5. Add the K10 NetBox device/interface/IPAM/DNS records only after MAC and boot
   path are verified.
6. Complete SLiM/NsCDE live startup validation on VM `1094`.
7. Decide whether to keep the workstation Intel/AMD GPU universal package set
   as one closure or split it into profile-selected GPU overlays after the K10
   validation run.

## Backout Summary

The workstation package changes are non-destructive. To back out the Intel
metrics patch, remove
`/etc/portage/patches/dev-libs/intel-metrics-library/01-disable-upstream-release-lto.patch`
from the VM and revert the profile patch block before rerunning. Existing
binpkgs are reusable and should not be deleted unless package policy changes
make them invalid.

The K10 work did not modify the host. Backout is to leave the K10 powered off or
unplugged from CSS326 `ge16`, then remove any stale DHCP lease or NetBox intake
only after verifying it belongs to the K10.

## Next Work Block

1. Monitor the workstation package rerun and capture final package counts.
2. Fix any remaining `llvm-core` or Intel stack blocker using the newest build
   log, not old assumptions.
3. Get K10 firmware into PXE/iPXE mode and inventory its real NIC identity.
4. Run the K10 Stage5 workstation install as the bare-metal preflight before any
   X12AGAIN reimage.
5. Continue service-layer work once the workstation build lane is stable:
   centralized logs, Elasticsearch/Kibana/APM, HAProxy VIP patterns, and
   NetBox/IPAM-driven host rollout.
