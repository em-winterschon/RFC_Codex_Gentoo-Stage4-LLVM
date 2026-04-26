# Workflows

## Operator Workflow Families

This repository currently has six main workflow families:

- host validation and CI
- Path A VM build and launch
- Path A staged installer execution
- Path B iPXE asset publication and fleet bootstrapping
- Path B RouterOS CHR lab configuration
- notification and approval visibility

## 1. Validate the Repository

Run before host or VM operations:

```bash
pre-commit run --all-files
bash tests/shell/run-tests.sh
```

Relevant CI workflows:

- `.github/workflows/validate.yml`
- `.github/workflows/notify.yml`

## 2. Build the Stage3 QCOW

Preferred path:

```bash
SSH_AUTHORIZED_KEY_FILE=$HOME/.ssh/id_ed25519.pub \
bash gentoo-virt-qemu/build-stage3-qcow.sh
```

This produces:

- `/opt/gentoo-virt-qemu/stage3/images/gentoo-stage4-testvm.qcow2`

## 3. Launch the Installer VM

Default user-mode networking:

```bash
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

Alias mode:

```bash
QEMU_NETWORK_MODE=alias \
bash gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

## 4. Watch Long-Running Install Control Flow

Start the sequence:

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence storage-foundation \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.storage.jsonl
```

Watch it:

```bash
python3 scripts/watch-control-flow.py \
  --path /tmp/ansible-control-flow/target-system-remote.storage.jsonl \
  --follow
```

## 5. Full VM Validation Flow

High-level order:

1. build the QCOW
2. launch installer VM
3. run `storage-foundation`
4. run `chroot-bootstrap`
5. run `target-integration`
6. shut down installer-QCOW boot
7. relaunch with `QEMU_BOOT_SOURCE=target-disks`
8. verify installed target boot, SSH, and ZFS state

Machine-readable version:

- `docs/workflows/stage4-vm-install-and-boot.json`

## 6. Path B iPXE Asset Publication

Render the Path B asset tree:

```bash
ansible-playbook \
  -i inventories/examples/hosts.yml \
  playbooks/netboot-path-b.yml \
  -l netboot_control_local
```

This produces:

- `bootstrap.ipxe`
- `menu.ipxe`
- `roles/*.ipxe`
- `hosts/*.ipxe`
- `manifests/path-b-netboot.json`

Operational intent:

- use DHCP/TFTP or UEFI HTTP only to reach iPXE
- use iPXE plus HTTP/HTTPS to fetch the provisioning kernel/initramfs/rootfs
- keep Path A available for hosts that cannot join the iPXE network

Machine-readable version:

- `docs/workflows/stage4-netboot-path-b.json`

## 7. Destination Host Staged Install Flow

Recommended order:

1. `storage-foundation`
2. `chroot-bootstrap`
3. `target-integration`
4. optional `repair-boot`
5. optional `repair-services`

Machine-readable version:

- `docs/workflows/stage4-destination-install-sequences.json`

## 8. Path B RouterOS CHR Role

Render the RouterOS Path B intent locally:

```bash
ansible-playbook \
  -i inventories/examples/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/routeros-path-b.yml \
  -l routeros_pathb_primary
```

Optional live apply:

```bash
ansible-playbook \
  -i inventories/examples/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/routeros-path-b.yml \
  -l routeros_pathb_primary \
  -e routeros_pathb_apply=true
```

Important current constraints:

- UEFI only
- CHR lab architecture treated as RouterOS `x86`
- `container` support is valid on `x86`
- `zerotier` is not documented by MikroTik for `x86`
- HTTP is disabled rather than redirected
- RouterOS does not provide the full desired local UDP+TCP syslog-server role natively

Machine-readable version:

- `docs/workflows/stage4-routeros-pathb-deployment.json`

## 9. Persistent Codex Approval Visibility

Install:

```bash
bash scripts/install_codex_approval_watcher_service.sh
```

Verify:

```bash
rc-service codex-approval-watcher status
```

This watches Codex TUI logs and emits ntfy alerts for sandbox approval dialogs.

Machine-readable version:

- `docs/workflows/codex-approval-watcher-service.json`

## 10. Release and Merge Discipline

Operational rule:

- no merges if validation fails

Recommended GitHub protection:

- require PRs
- require status checks:
  - `Validate / pre-commit`
  - `Validate / shell-tests`
- require up-to-date branches before merge
- restrict direct pushes to `main`

## 11. Expected Return Codes

Normal success:

- `0`

Failure conditions should be surfaced at one of these layers:

- shell validator
- Ansible stage failure
- QEMU launch preflight
- SSH readiness checks
- workflow JSONL final stats

## 12. Artifacts Worth Watching

- `/tmp/ansible-control-flow/*.jsonl`
- `/opt/gentoo-virt-qemu/stage3/state/*.serial.log`
- `/tmp/qemu-launch-stage3-vm.sh.*.log`
- `/tmp/validate-llvm-qcow-builder.sh.*.log`
