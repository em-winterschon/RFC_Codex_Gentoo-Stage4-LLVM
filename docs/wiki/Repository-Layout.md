# Repository Layout

## Top-Level Structure

```text
RFC_Codex_Gentoo-Stage4-LLVM
├── .github/
│   ├── scripts/
│   └── workflows/
├── docs/
│   └── workflows/
│       ├── ntfy-server-deployment.json
├── gentoo-virt-qemu/
├── gentoo_stage4_llvm_split-usr_no-multilib_hardened/
│   ├── gentoo-liveiso-ansible/
│   ├── repo-struct-tree.ascii.index
│   └── repo-struct-tree.ascii.json
├── openrc/
├── scripts/
├── tests/
│   └── shell/
├── README.md
├── AGENT_RULES.md
├── ntfy.env.example
├── pyproject.toml
└── requirements-dev.txt
```

## Top-Level File and Directory Roles

- `.github/workflows/`
  CI validation and repository ntfy notifications
- `docs/workflows/`
  machine-readable workflow manifests
- `gentoo-virt-qemu/`
  host-side VM build, launch, and validation tooling
- `gentoo-liveiso-ansible/`
  the installer system itself
- `openrc/`
  service templates for persistent host-side utilities
- `scripts/`
  shared notification, Codex, and operator helper scripts
- `tests/shell/`
  shell-based regression and portability tests

## Ansible Subtree

```text
gentoo-liveiso-ansible
├── action_plugins/
│   └── ntfy.py
├── callback_plugins/
│   ├── control_flow.py
│   └── ntfy.py
├── collections/
│   └── requirements.yml
├── inventories/
│   ├── examples/
│   │   ├── group_vars/install_targets.yml
│   │   ├── group_vars/ntfy_servers.yml
│   │   └── hosts.yml
│   ├── qemu-alias/
│   │   ├── group_vars/install_targets.yml
│   │   └── hosts.yml
│   └── vm-stage4/
│       ├── group_vars/
│       └── hosts.yml
├── playbooks/
│   ├── install.yml
│   ├── ntfy-server.yml
│   └── tasks/run_install_stage.yml
├── profile-definitions/
│   └── hardened-llvm-stage4.yml
├── roles/
│   ├── preflight/
│   ├── liveiso_prepare/
│   ├── storage/
│   ├── zfs/
│   ├── stage3/
│   ├── profile/
│   ├── portage/
│   ├── chroot_base/
│   ├── system_packages/
│   ├── kernel/
│   ├── boot/
│   ├── bootloader/
│   ├── network/
│   ├── ntfy_server/
│   ├── services/
│   └── finalize/
├── scripts/
│   ├── bootstrap-liveiso.sh
│   ├── generate-ansible-python-setup.sh
│   ├── run-install-sequence.sh
│   ├── setup-ansible-python-env.sh
│   └── watch-control-flow.py
├── service-definitions/
│   └── stage4-heartbeat.yml
└── vars/
    ├── cpu_profiles.yml
    ├── gpu_profiles.yml
    └── install_sequences.yml
```

## Ansible File Descriptions

### Core control files

- `ansible.cfg`
  enables local plugin paths and callback configuration
- `playbooks/install.yml`
  top-level installer playbook
- `playbooks/ntfy-server.yml`
  standalone private ntfy server deployment playbook
- `playbooks/tasks/run_install_stage.yml`
  named stage block wrapper used by `install_sequence`

### Inventories

- `inventories/examples/hosts.yml`
  general examples for local and remote LiveISO targets, plus a standalone `ntfy_servers` group
- `inventories/examples/group_vars/ntfy_servers.yml`
  example private ntfy server configuration, auth policy, and listen/base URL settings
- `inventories/qemu-alias/hosts.yml`
  installer-VM control path through alias mode and forwarded SSH
- `inventories/qemu-alias/group_vars/install_targets.yml`
  VM-visible disk IDs for QEMU-backed validation
- `inventories/vm-stage4/`
  earlier local validation VM definitions

### Roles

- `preflight`
  safety rails and parameter validation
- `liveiso_prepare`
  prepare the running LiveISO and target mount root
- `storage`
  partitioning, swap, and native-ZFS layout creation
- `zfs`
  ZFS-specific orchestration and assertions
- `stage3`
  stage3 discovery, download, and extraction
- `profile`
  local overlay profile composition
- `portage`
  `make.conf`, package.use, and repository tuning
- `chroot_base`
  chroot mounts, sync, repositories, locale, timezone, hostname
- `system_packages`
  core target packages including kernel and boot prerequisites
- `kernel`
  compatibility wrapper around package installation strategy
- `boot`
  ZFSBootMenu, kernel/initramfs materialization, fstab, EFI state
- `bootloader`
  compatibility wrapper around boot orchestration
- `network`
  OpenRC and network service configuration
- `ntfy_server`
  dedicated private ntfy server deployment, config rendering, and OpenRC service management
- `services`
  data-driven OpenRC service deployment
- `finalize`
  wrapper for late-stage integration tasks

## QEMU Helper Subtree

```text
gentoo-virt-qemu
├── build-stage3-qcow.sh
├── gentoo-install-qemu-edk2.sh
├── qemu-launch-stage3-vm.sh
├── qemu-launch-cloudinit-vm.sh
├── qemu-launch-minimal-vm.sh
├── qemu-pci-remap.sh
├── validate-llvm-qcow-builder.sh
└── README.md
```

### QEMU File Descriptions

- `build-stage3-qcow.sh`
  build a bootable LLVM/OpenRC QCOW from a supported stage3 enum target
- `gentoo-install-qemu-edk2.sh`
  install host prerequisites for QEMU, EDK2, image creation, and supporting tools
- `qemu-launch-stage3-vm.sh`
  preferred installer and target-disk validation launcher
- `qemu-launch-cloudinit-vm.sh`
  legacy reference workflow for the official Gentoo cloud image path
- `qemu-launch-minimal-vm.sh`
  older manual ISO launcher kept for debugging
- `qemu-pci-remap.sh`
  VFIO binding helper for host passthrough experiments
- `validate-llvm-qcow-builder.sh`
  repeatable validation harness for the builder and launcher

## Notifications and Operator Tooling

```text
scripts
├── codex-ntfy.sh
├── codex_approval_watcher.py
├── codex_approval_watcher_with_env.sh
├── codex_hook_with_env.sh
├── codex_notify_event.py
├── codex_notify_with_env.sh
├── codex_ntfy_hook.py
├── install_codex_approval_watcher_service.sh
├── ntfy_notify.py
├── ntfy_pubsub_tui.py
└── slack_webhook.py
```

Key roles:

- `ntfy_notify.py`
  common ntfy publisher utility
- `codex_notify_event.py`
  turn-complete notification handler
- `codex_ntfy_hook.py`
  Codex hook event handling for approvals/replies
- `codex_approval_watcher.py`
  log watcher for sandbox approval dialogs
- `install_codex_approval_watcher_service.sh`
  installs the watcher as an OpenRC service

## Test Suite Layout

```text
tests/shell
├── run-tests.sh
├── test_build_stage3_qcow.sh
├── test_control_flow_tools.sh
├── test_generate_ansible_python_setup.sh
├── test_generate_cloud_init_seed.sh
├── test_install_codex_approval_watcher_service.sh
├── test_ntfy_tools.sh
├── test_ntfy_server_role.sh
├── test_qemu_launch_cloudinit_vm.sh
├── test_qemu_launch_minimal_vm.sh
├── test_qemu_launch_stage3_vm.sh
├── test_qemu_pci_remap.sh
├── test_validate_llvm_qcow_builder.sh
├── test_workflow_manifests.sh
└── test_zfs_layout_specs.sh
```

Purpose:

- keep the shell-heavy orchestration layer regression-testable
- validate workflow manifests and notification helpers
- catch QEMU and installer drift before merge
