# gentoo-virt-qemu

Host-side helper files for bringing up Gentoo QEMU/KVM test VMs for the Stage4 install workflow.

Preferred workflow:
- use the official Gentoo `di-amd64-cloudinit` QCOW2 image instead of the minimal ISO
- inject instance configuration through a NoCloud seed ISO
- attach the four host disks intended for the eventual `bpool` and `rpool`
- boot headless, wait for SSH, and run the Ansible validation flow without touching GRUB or a local console

Contents:
- `gentoo-install-qemu-edk2.sh`: installs the host package set for QEMU, EDK2, cloud-image download, and seed ISO creation
- `generate-cloud-init-seed.sh`: renders `meta-data`, `user-data`, and optional `network-config`, then builds a NoCloud seed ISO labeled `cidata`
- `qemu-launch-cloudinit-vm.sh`: downloads or reuses the official Gentoo cloud-init QCOW2, creates a writable overlay, attaches the four target disks, and boots the VM headlessly with SSH forwarded to the host
- `qemu-pci-remap.sh`: binds selected host PCI devices to `vfio-pci` for passthrough
- `qemu-launch-minimal-vm.sh`: legacy manual ISO launcher kept for comparison and debugging, not the recommended unattended path
- `etc_portage_make.conf`: host-side `make.conf` snippet tuned for the QEMU/EDK2 workflow used here

Recommended USE flags:
- `app-emulation/qemu`: `X gtk sdl slirp spice vnc`
  Why: `slirp` keeps `-netdev user` available for the unattended SSH-forwarded path, while the display flags remain available for optional local debugging.
- `app-emulation/virt-viewer`: `libvirt spice vnc`
  Why: useful if you still want graphics experiments, but the unattended validation path does not depend on it.

The prep script writes those flags into `${PACKAGE_USE_FILE:-/etc/portage/package.use/codex-qemu}` before the initial `emerge`.

Host packages installed by `gentoo-install-qemu-edk2.sh`:
- `sys-firmware/edk2-bin`
- `app-emulation/qemu`
- `app-cdr/cdrtools`
- `net-dialup/minicom`
- `net-misc/curl`
- optional `app-emulation/virt-viewer`
- optional `app-emulation/libvirt`

Why the cloud-image path is now preferred:
- no GRUB editing or kernel command line surgery is needed just to get a usable guest
- no dependency on SPICE or VNC behaving correctly with the Gentoo installer framebuffer
- no human race to connect a serial console before the bootloader continues
- the VM can be launched headlessly and reached over SSH with a key injected by cloud-init
- this fits the actual validation goal: run Ansible against a disposable VM that exposes the target disk topology

Official Gentoo cloud-image context:
- Gentoo publishes weekly bootable QCOW2 images, including `cloud-init` variants for amd64
- the launcher resolves the latest amd64 cloud-init image from `latest-di-amd64-cloudinit.txt` unless you override `CLOUD_IMAGE_URL` or `CLOUD_IMAGE_PATH`
- the image source is the official Gentoo distfiles mirror, not an ad-hoc external image

Exact unattended launch flow:
1. Install the host dependencies:
   `bash gentoo-virt-qemu/gentoo-install-qemu-edk2.sh`
2. Launch the VM with an SSH key for cloud-init:
   `SSH_AUTHORIZED_KEY_FILE=$HOME/.ssh/id_ed25519.pub bash gentoo-virt-qemu/qemu-launch-cloudinit-vm.sh`
3. Connect after the script reports completion:
   `ssh -o StrictHostKeyChecking=no -p 2222 root@127.0.0.1`

What `qemu-launch-cloudinit-vm.sh` does:
- downloads the latest official `di-amd64-cloudinit` QCOW2 if it is not already cached locally
- creates a writable QCOW2 overlay so the cached base image stays immutable
- calls `generate-cloud-init-seed.sh` to build a NoCloud seed ISO with your SSH public key
- attaches the seed ISO and the four host disks
- configures user-mode networking with `hostfwd=tcp:127.0.0.1:2222-:22`
- boots QEMU headlessly by default and waits for SSH readiness

Default disk topology exposed to the guest:
- `BPOOL_DISK0` and `BPOOL_DISK1` for the mirrored SATADOM boot pool
- `RPOOL_DISK0` and `RPOOL_DISK1` for the mirrored SATA root pool
- the cloud image itself is a separate boot disk used only to start the disposable validation VM

Important defaults in the cloud-image launcher:
- `QEMU_DISPLAY_MODE=none`
- `QEMU_SERIAL_MODE=file`
- `QEMU_DAEMONIZE=1`
- `WAIT_FOR_SSH=1`
- `SSH_FORWARD_HOST=127.0.0.1`
- `SSH_FORWARD_PORT=2222`

Useful overrides:
- pin a specific image URL:
  `CLOUD_IMAGE_URL=https://distfiles.gentoo.org/releases/amd64/autobuilds/20260419T164601Z/di-amd64-cloudinit-20260419T164601Z.qcow2`
- reuse a pre-downloaded image:
  `CLOUD_IMAGE_PATH=/var/cache/gentoo-vm/di-amd64-cloudinit.qcow2`
- recreate the writable overlay from scratch:
  `RECREATE_OVERLAY=1`
- keep serial output on the terminal instead of a file:
  `QEMU_SERIAL_MODE=stdio QEMU_DAEMONIZE=0 WAIT_FOR_SSH=0`
- use an alternate SSH key file:
  `SSH_AUTHORIZED_KEY_FILE=/path/to/key.pub`
- set an explicit password hash in cloud-init as a fallback:
  `CLOUD_INIT_PASSWORD_HASH='${6}$examplehash' CLOUD_INIT_LOCK_PASSWD=0`
- disable generated network-config if you want the image defaults only:
  `CREATE_NETWORK_CONFIG=0`

Raw unattended example with local serial logs:
`SSH_AUTHORIZED_KEY_FILE=$HOME/.ssh/id_ed25519.pub QEMU_SERIAL_MODE=file QEMU_DAEMONIZE=1 WAIT_FOR_SSH=1 bash gentoo-virt-qemu/qemu-launch-cloudinit-vm.sh`

After boot, the serial log lives at:
- `${STATE_DIR}/${INSTANCE_NAME}.serial.log` by default

Cloud-init seed notes:
- `generate-cloud-init-seed.sh` requires an SSH public key through `SSH_AUTHORIZED_KEY`, `SSH_AUTHORIZED_KEY_FILE`, or a default key under `$HOME/.ssh/`
- it writes:
  - `meta-data`
  - `user-data`
  - optional `network-config`
- it builds the seed ISO with `mkisofs` from `app-cdr/cdrtools`, falling back to `xorriso` if available

About libvirt:
- `app-emulation/libvirt` remains optional
- the current unattended implementation is raw QEMU, because that is enough to validate the guest boot and Ansible workflow without adding another management layer
- if you later want libvirt-managed domains, the same cloud-init seed content and QCOW2 image approach still apply

Legacy ISO path:
- `qemu-launch-minimal-vm.sh` is still in the tree for manual experiments
- it is no longer the recommended validation route because it requires installer-console workarounds that do not fit unattended execution

Validation and debugging:
- `bash tests/shell/test_generate_cloud_init_seed.sh` runs the unit tests for `generate-cloud-init-seed.sh`
- `bash tests/shell/test_qemu_launch_cloudinit_vm.sh` runs the unit tests for `qemu-launch-cloudinit-vm.sh`
- `bash tests/shell/test_qemu_launch_minimal_vm.sh` runs the unit tests for the legacy ISO launcher
- `bash tests/shell/test_qemu_pci_remap.sh` runs the unit tests for `qemu-pci-remap.sh`
- `bash tests/shell/run-tests.sh` runs the shell validation sequence used in CI
- `bash tests/shell/debug-qemu-launch-minimal-vm.sh` still exists for debugging the legacy launcher

Sources:
- Gentoo news: bootable QCOW2 images, including cloud-init variants: https://www.gentoo.org/news/2025/02/20/gentoo-qcow2-images.html
- Gentoo distfiles amd64 autobuilds index, including `current-di-amd64-cloudinit`: https://distfiles.gentoo.org/releases/amd64/autobuilds/
- Gentoo `app-emulation/cloud-init`: https://packages.gentoo.org/packages/app-emulation/cloud-init
- Gentoo `app-emulation/qemu`: https://packages.gentoo.org/packages/app-emulation/qemu
- Gentoo `app-emulation/libvirt`: https://packages.gentoo.org/packages/app-emulation/libvirt
- Gentoo `app-cdr/cdrtools`: https://packages.gentoo.org/packages/app-cdr/cdrtools
