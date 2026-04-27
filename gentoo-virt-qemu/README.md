# gentoo-virt-qemu

Host-side helper files for bringing up Gentoo QEMU/KVM test VMs for the Stage4 install workflow.

Preferred workflow:
- build a custom QCOW image from an official Gentoo OpenRC stage3 instead of using the official `cloud-init` QCOW image
- default to the LLVM/Clang OpenRC stage3 for `amd64`
- attach the four host disks intended for the eventual `bpool` and `rpool`
- boot only from the explicit QCOW boot disk by default, with PXE and fallback device boot disabled
- keep both network SSH access and serial-console access available
- support safe host-local VM networking before moving to bridge-backed external connectivity

Why this path is now preferred:
- the official Gentoo `cloud-init` QCOW images are `systemd` based, which does not match this infrastructure
- the repo already treats `llvm-openrc` as the stage3 source of truth for installs
- the QCOW builder can enforce upstream stage3 target enums instead of letting callers request non-existent images
- the stage3 launcher can expose a serial transport suitable for either TCP or a local PTY that tools like `minicom` can attach to

Contents:
- `gentoo-install-qemu-edk2.sh`
  installs the host package set for QEMU, EDK2, image download, ISO creation, and filesystem tooling
- `build-stage3-qcow.sh`
  downloads a supported OpenRC stage3, validates the enum target, creates a QCOW image, and prepares a bootstrap plan to turn that stage3 into a bootable VM image
- `qemu-launch-stage3-vm.sh`
  launches the custom stage3 QCOW image with the four target disks attached, strict UEFI boot, SSH forwarding, and selectable serial-console transport
- `validate-llvm-qcow-builder.sh`
  runs repeatable builder and launcher validation sequences for iterative host-side development
- `qemu-launch-cloudinit-vm.sh`
  legacy reference workflow for the official Gentoo `cloud-init` image; kept for comparison, not the preferred path
- `qemu-launch-minimal-vm.sh`
  legacy manual ISO launcher kept for comparison and debugging
- `qemu-pci-remap.sh`
  binds selected host PCI devices to `vfio-pci` for passthrough experiments
- `etc_portage_make.conf`
  host-side `make.conf` snippet tuned for the QEMU workflow used here

Recommended USE flags:
- `app-emulation/qemu`: `X gtk sdl slirp spice vnc`
  `slirp` keeps `-netdev user` available, while the display flags stay available for optional debugging
- `app-emulation/virt-viewer`: `libvirt spice vnc`
  still useful for graphics experiments, but no longer required for the preferred path

The prep script writes those flags into `${PACKAGE_USE_FILE:-/etc/portage/package.use/codex-qemu}` before `emerge`.

Host packages installed by `gentoo-install-qemu-edk2.sh`:
- `sys-firmware/edk2-bin`
- `app-emulation/qemu`
- `app-cdr/cdrtools`
- `net-dialup/minicom`
- `net-misc/curl`
- `sys-fs/dosfstools`
- optional `app-emulation/virt-viewer`
- optional `app-emulation/libvirt`

## Stage3 Builder

`build-stage3-qcow.sh` validates `STAGE3_TARGET` as an enum. Supported values are:
- `amd64-llvm-openrc`
- `arm64-llvm-openrc`
- `power9le-openrc`

The builder rejects any other value before it tries to request upstream stage3 resources.

Current target mapping:
- `amd64-llvm-openrc`
  upstream directory: `releases/amd64/autobuilds/current-stage3-amd64-llvm-openrc`
- `arm64-llvm-openrc`
  upstream directory: `releases/arm64/autobuilds/current-stage3-arm64-llvm-openrc`
- `power9le-openrc`
  upstream directory: `releases/ppc/autobuilds/current-stage3-power9le-openrc`

Important constraint:
- non-dry-run QCOW assembly is currently guarded to same-arch hosts only
- on the current x86_64 host, the builder is operational for `amd64-llvm-openrc`
- the `arm64` and `power9le-openrc` enum values are wired for valid upstream discovery and future expansion, but not yet cross-bootstrapped on this host

Builder defaults:
- `STAGE3_TARGET=amd64-llvm-openrc`
- `QCOW_IMAGE=/opt/gentoo-virt-qemu/stage3/images/gentoo-stage4-testvm.qcow2`
- `QCOW_SIZE_GIB=24`
- `PORTAGE_SYNC_COMMAND=emerge-webrsync`
- `STAGE3_KERNEL_PACKAGE=sys-kernel/gentoo-kernel-bin`
- `STAGE3_BOOTLOADER_PACKAGE=sys-boot/grub`
- `STAGE3_NETWORK_PACKAGE=net-misc/dhcpcd`
- `STAGE3_SSH_PACKAGE=net-misc/openssh`

Builder example:
```bash
bash gentoo-virt-qemu/build-stage3-qcow.sh
```

Dry-run example:
```bash
QEMU_STAGE3_BUILD_DRY_RUN=1 \
SSH_AUTHORIZED_KEY_FILE=$HOME/.ssh/id_ed25519.pub \
bash gentoo-virt-qemu/build-stage3-qcow.sh
```

The builder writes an OpenRC-oriented bootstrap plan that:
- keeps `clang`/`clang++`/`ld.lld` in guest `make.conf`
- enables a serial `ttyS0` login
- installs a kernel, GRUB, `dhcpcd`, and `openssh`
- prepares an EFI boot path and a serial-friendly GRUB config

## Stage3 Launcher

`qemu-launch-stage3-vm.sh` is the preferred launcher for the custom stage3 QCOW image.

What it does:
- boots the explicit QCOW boot disk as `virtio-blk-pci`
- attaches the four target disks for `bpool` and `rpool`
- can attach additional tmpfs-backed ephemeral development disks from a JSON manifest
- can boot directly from the target `bpool`/`rpool` disks after the installer has populated the ESP and ZFS datasets
- runs QEMU with `-boot strict=on` by default so OVMF does not wander into SATADOM, PXE, or HTTP boot
- forwards guest SSH to `127.0.0.1:2222` by default
- supports serial transport via `file`, `tcp`, `pty`, `stdio`, or `none`
- can log launcher activity to `/tmp/${script}.${PPID}-${PID}.$(date ...).log`

Important launcher defaults:
- `QEMU_BOOT_SOURCE=qcow`
- `QEMU_BOOT_STRICT=1`
- `QEMU_DISPLAY_MODE=none`
- `QEMU_SERIAL_MODE=file`
- `QEMU_SERIAL_FILE=/opt/gentoo-virt-qemu/stage3/state/gentoo-stage4-testvm.serial.log`
- `QEMU_NETWORK_MODE=user`
- `QEMU_NETDEV_BACKEND=user,hostfwd=tcp:127.0.0.1:2222-:22`
- `WAIT_FOR_SSH=1`
- `SSH_READY_PROBE=banner`
- `LAUNCHER_LOG_ENABLE=1`
- `QEMU_MEMORY_DRIVES_FILE=''`

Preferred launch sequence:
1. Build the QCOW image:
   `SSH_AUTHORIZED_KEY_FILE=$HOME/.ssh/id_ed25519.pub bash gentoo-virt-qemu/build-stage3-qcow.sh`
2. Launch the VM:
   `bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh`
3. Connect with SSH after the banner check passes:
   `ssh -o StrictHostKeyChecking=no -p 2222 root@127.0.0.1`

Network modes:
- `QEMU_NETWORK_MODE=user`
  current default; QEMU slirp user-mode networking with localhost SSH forwarding
- `QEMU_NETWORK_MODE=alias`
  safe host-local test mode; adds `QEMU_NET_ALIAS_CIDR` to `QEMU_NET_ALIAS_DEV` and uses
  slirp DHCP on `QEMU_NET_ALIAS_SUBNET`, starting guest allocation at `QEMU_NET_ALIAS_GUEST_IPV4`
- `QEMU_NETWORK_MODE=tap`
  creates and brings up `QEMU_TAP_IFNAME`, optionally assigning `QEMU_TAP_HOST_CIDR`
- `QEMU_NETWORK_MODE=bridge`
  same tap setup as `tap`, then enslaves the tap interface into `QEMU_BRIDGE_IFNAME`

Alias-mode defaults:
- `QEMU_NET_ALIAS_DEV=lo`
- `QEMU_NET_ALIAS_CIDR=10.9.8.108/24`
- `QEMU_NET_ALIAS_SUBNET=10.9.8.0/24`
- `QEMU_NET_ALIAS_GUEST_IPV4=10.9.8.7`

Alias-mode test example:
```bash
QEMU_NETWORK_MODE=alias \
QEMU_SERIAL_MODE=file \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh

ssh -o StrictHostKeyChecking=no -p 2222 root@10.9.8.108
```

Tap-mode example:
```bash
QEMU_NETWORK_MODE=tap \
QEMU_TAP_IFNAME=tap-stage4 \
QEMU_TAP_HOST_CIDR=10.9.8.108/24 \
WAIT_FOR_SSH=0 \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

Bridge-mode example:
```bash
QEMU_NETWORK_MODE=bridge \
QEMU_TAP_IFNAME=tap-stage4 \
QEMU_BRIDGE_IFNAME=br0 \
WAIT_FOR_SSH=0 \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

Tmpfs-backed ephemeral memory-drive example:
```bash
ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/examples/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/qemu-memory-drives.yml \
  -l qemu_control_local \
  -e qemu_memory_drives_enabled=true \
  -e qemu_memory_drives_instance_name=stage4-devvm

QEMU_MEMORY_DRIVES_FILE=/dev/shm/qemu-memory-drives/stage4-devvm/memory-drives.json \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

The manifest-driven disks are meant for:
- Portage caches
- build scratch space
- ephemeral container/image storage
- other development-time data that should not be written to the persistent validation disks

Boot-source modes:
- `QEMU_BOOT_SOURCE=qcow`
  boots the disposable stage3 QCOW image and attaches the four target disks for installation work
- `QEMU_BOOT_SOURCE=target-disks`
  skips the QCOW image entirely and boots directly from the target disks, prioritizing `BPOOL_DISK0`
  so OVMF loads `EFI/BOOT/BOOTX64.EFI` from the installed ESP

Direct target-disk boot example:
```bash
QEMU_BOOT_SOURCE=target-disks \
QEMU_SERIAL_MODE=stdio \
QEMU_DAEMONIZE=0 \
WAIT_FOR_SSH=0 \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

This mode is intended for post-install validation once the installer has created:
- the ESP on the first `bpool` disk
- `EFI/BOOT/BOOTX64.EFI` for ZFSBootMenu
- `bpool/BOOT/gentoo`
- `rpool/ROOT/gentoo`

Serial transport options:
- `QEMU_SERIAL_MODE=file`
  writes the guest serial console to `QEMU_SERIAL_FILE`
- `QEMU_SERIAL_MODE=tcp`
  exports the guest serial console at `QEMU_SERIAL_TCP`, default:
  `127.0.0.1:4555,server=on,wait=off,telnet=on`
- `QEMU_SERIAL_MODE=pty`
  asks QEMU to allocate a local PTY for the guest serial port, which is the path intended for `minicom`-style local attachment
- `QEMU_SERIAL_MODE=stdio`
  keeps the guest serial console on the invoking terminal and requires `QEMU_DAEMONIZE=0`

Minicom-style local serial example:
```bash
QEMU_SERIAL_MODE=pty \
WAIT_FOR_SSH=0 \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

TCP serial example:
```bash
QEMU_SERIAL_MODE=tcp \
QEMU_SERIAL_TCP='127.0.0.1:4555,server=on,wait=off,telnet=on' \
WAIT_FOR_SSH=0 \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

Launcher log naming:
- default path:
  `/tmp/qemu-launch-stage3-vm.sh.${PPID}-${PID}.$(date +'%Y-%m%d-%H%M_%s.UTC%z').log`
- override with:
  `LAUNCHER_LOG_FILE=/tmp/custom-stage3-vm.log`

Useful overrides:
- disable strict boot fallback scanning:
  `QEMU_BOOT_STRICT=0`
- skip SSH readiness checks entirely:
  `WAIT_FOR_SSH=0`
- wait only for the TCP listener, not the SSH banner:
  `SSH_READY_PROBE=tcp-port`
- disable launcher log file setup:
  `LAUNCHER_LOG_ENABLE=0`

## Iterative Validation

`validate-llvm-qcow-builder.sh` is the host-side sequence runner for this workflow. It is intended as the base for broader integration validation while keeping the existing shell test suite fast.

Supported modes:
- `build-dry-run`
  dry-runs `build-stage3-qcow.sh`
- `build`
  performs the real stage3 QCOW build
- `launch`
  launches the stage3 VM from an existing QCOW image
- `full`
  runs dry-run builder, real builder, then launcher
- `suite`
  alias for `build-dry-run`

Examples:
```bash
bash gentoo-virt-qemu/validate-llvm-qcow-builder.sh --mode build-dry-run
```

```bash
bash gentoo-virt-qemu/validate-llvm-qcow-builder.sh \
  --mode full \
  --ssh-pubkey /root/.ssh/id_ed25519.pub \
  --serial-mode pty \
  --wait-for-ssh 0
```

The validator writes its own log file to:
- `/tmp/validate-llvm-qcow-builder.sh.${PPID}-${PID}.$(date +'%Y-%m%d-%H%M_%s.UTC%z').log`

Actionable next tasks are tracked in the validator source so they can be promoted into the broader pre-merge validation path later.

## Workflow Manifests

Machine-readable workflow definitions for this subtree live under:

- `/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-vm-install-and-boot.json`
- `/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/codex-approval-watcher-service.json`

Those manifests capture:

- stage ordering
- command arrays
- environment variables
- expected exit codes
- major artifacts and notes

## Legacy Paths

The cloud-image path is still in-tree for reference, but it is no longer the preferred route:
- the official Gentoo `cloud-init` QCOW images are `systemd` based
- that diverges from the repo’s `llvm-openrc` install target

`qemu-launch-minimal-vm.sh` also remains for manual experiments, but it is not the preferred validation route.

## Validation

- `bash tests/shell/test_build_stage3_qcow.sh`
  unit tests for `build-stage3-qcow.sh`
- `bash tests/shell/test_validate_llvm_qcow_builder.sh`
  unit tests for `validate-llvm-qcow-builder.sh`
- `bash tests/shell/test_qemu_launch_stage3_vm.sh`
  unit tests for `qemu-launch-stage3-vm.sh`
- `bash tests/shell/test_generate_cloud_init_seed.sh`
  unit tests for the legacy cloud-init seed helper
- `bash tests/shell/test_qemu_launch_cloudinit_vm.sh`
  unit tests for the legacy cloud-init launcher
- `bash tests/shell/test_qemu_launch_minimal_vm.sh`
  unit tests for the legacy ISO launcher
- `bash tests/shell/test_qemu_pci_remap.sh`
  unit tests for `qemu-pci-remap.sh`
- `bash tests/shell/run-tests.sh`
  the shell validation sequence used in CI

Sources:
- Gentoo `current-stage3-amd64-llvm-openrc`: https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-llvm-openrc/
- Gentoo `current-stage3-arm64-llvm-openrc`: https://distfiles.gentoo.org/releases/arm64/autobuilds/current-stage3-arm64-llvm-openrc/
- Gentoo `current-stage3-power9le-openrc`: https://distfiles.gentoo.org/releases/ppc/autobuilds/current-stage3-power9le-openrc/
- Gentoo downloads page showing the official QCOW `cloud-init` image track separately from stage3 archives: https://www.gentoo.org/downloads/?info=EXLINK
- Gentoo `app-emulation/qemu`: https://packages.gentoo.org/packages/app-emulation/qemu
- Gentoo `app-cdr/cdrtools`: https://packages.gentoo.org/packages/app-cdr/cdrtools
