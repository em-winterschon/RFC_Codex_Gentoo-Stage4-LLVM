# gentoo-liveiso-ansible

A rapid-deploy Gentoo installer scaffold intended to be run from a booted Gentoo LiveISO,
either locally with `--connection=local` or remotely against a host booted into the same kind
of LiveISO via root SSH.

## Design goals

- UEFI-first
- OpenRC-first
- Root on ZFS with OpenZFS 2.4 and ZFSBootMenu by default
- LLVM/Clang-oriented make.conf generation
- A small local profile overlay to combine multiple stable Gentoo profile axes
- Reproducible disk provisioning with explicit destructive opt-in

## Why a local profile overlay exists

The desired target profile is effectively:

- amd64
- openrc
- llvm
- split-usr
- no-multilib
- hardened

Gentoo exposes these profile axes, but this scaffold treats the exact combination as a local
profile overlay so that the installer can compose the desired state cleanly and predictably.
The default overlay parents are:

- `gentoo:default/linux/amd64/23.0/llvm`
- `gentoo:default/linux/amd64/23.0/split-usr/no-multilib/hardened`

Adjust `profile_parents` if the upstream profile graph changes.

## Storage model

Supported `storage_layout` values:

- `single-drive`
- `raid-1`
- `raid-10`
- `zfs-mirror`
- `zfs-boot-root-mirror`
- `zraid1`
- `zraid2`
- `zraid3`
- `draid`

### Recommendation

For `zfs-2.4 on /`, prefer the native ZFS topologies:

- `single-drive`
- `zfs-mirror`
- `zraid2`
- `draid`

The `raid-1` and `raid-10` layouts intentionally gate execution with
`storage_allow_mdadm_under_zfs=true`, because they place ZFS on top of mdraid.
That can still be useful in some environments, but it is not the default recommendation.

## CPU tuning profiles

Available `portage_cpu_profile` values:

- `amd_ryzen_z1_extreme`
- `amd_epyc_zen4`
- `amd_epyc_zen5`
- `intel_xeon_8370c`
- `intel_core_i9_13900hk`
- `intel_core_ultra_5_125h`
- `intel_xeon_e5_2643v4`

These primarily drive:

- `-march`
- `-mtune`
- `RUSTFLAGS=-C target-cpu=...`
- `LLVM_TARGETS`

GPU-specific Portage settings are intentionally separate via `gpu_stack`.

## Quick start

### Local execution from the LiveISO

```bash
./scripts/bootstrap-liveiso.sh
vim inventories/examples/group_vars/install_targets.yml
ansible-playbook playbooks/install.yml -l target_system_local --connection=local
```

### Remote execution against a booted LiveISO

```bash
./scripts/bootstrap-liveiso.sh
vim inventories/examples/hosts.yml
vim inventories/examples/group_vars/install_targets.yml
ansible-playbook playbooks/install.yml -l target_system_remote
```

### QEMU alias-mode execution against the installer VM

Use the dedicated alias-mode inventory when the installer VM is launched with
`QEMU_NETWORK_MODE=alias`. In that mode, the guest uses `10.9.8.7/24`
internally, but Ansible must connect to the host-side alias and forwarded SSH
port.

```bash
./scripts/bootstrap-liveiso.sh
vim inventories/qemu-alias/group_vars/install_targets.yml
ansible-playbook -i inventories/qemu-alias/hosts.yml playbooks/install.yml -l target_system_remote
```

The qemu-alias validation inventory is also the current test bed for ZFS/kernel
compatibility debugging. It now demonstrates:

- source-built `sys-kernel/gentoo-kernel` rather than `gentoo-kernel-bin`
- package atom overrides for exact kernel and ZFS versions
- `package.accept_keywords` fragments for newer `~amd64` OpenZFS builds
- `/etc/kernel/config.d/*.config` snippets for targeted kernel config changes

Relevant inventory keys:

- `kernel_package_atom_override`
- `zfs_package_atom`
- `zfs_kmod_package_atom`
- `portage_package_use_files`
- `portage_package_accept_keywords_files`
- `kernel_config_fragment_files`
- the default `llvm-clang-hardened-portage.yml` profile definition

### Install sequences

The installer now supports staged `install_sequence` execution. The default sequence is:

- `full-default`

Available `install_sequence` values:

- `full-default`
- `full-modular-zfs`
- `storage-foundation`
- `chroot-bootstrap`
- `target-integration`
- `repair-boot`
- `repair-services`

Each sequence resolves to named Ansible blocks and optional debug checkpoints, so task
output and the structured control-flow pipeline can reference the same stage identifiers.

Enable explicit stage checkpoints by setting:

```yaml
install_debug_checkpoints: true
```

Optionally constrain a sequence to only certain stage IDs:

```yaml
install_stage_filter:
  - target-integration
```

If you need to bypass sequence enums during repair work, `selected_roles` still works and
collapses execution into a single `selected-roles` stage.

Example inventory override:

```yaml
selected_roles:
  - storage
  - stage3
  - profile
  - portage
  - boot
```

Example direct role override:

```bash
ansible-playbook playbooks/install.yml -l target_system_remote -e '{"selected_roles":["boot","network"]}'
```

### Sequence wrapper and control-flow pipeline

Use the wrapper script to run a sequence with a tail-able JSONL control-flow stream:

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence full-default \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.install.jsonl
```

Watch the run remotely in a second terminal or over SSH:

```bash
python3 scripts/watch-control-flow.py \
  --path /tmp/ansible-control-flow/target-system-remote.install.jsonl \
  --follow
```

Recommended first-pass staged execution for a destination test host:

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence storage-foundation \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.storage.jsonl

bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence chroot-bootstrap \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.bootstrap.jsonl

bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence target-integration \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.integration.jsonl
```

Optional focused repair pass:

```bash
bash scripts/run-install-sequence.sh \
  --inventory inventories/qemu-alias/hosts.yml \
  --limit target_system_remote \
  --sequence repair-boot \
  --checkpoint \
  --control-flow-path /tmp/ansible-control-flow/target-system-remote.repair-boot.jsonl
```

The control-flow stream is produced by:

- `callback_plugins/control_flow.py`

and writes JSONL events for:

- playbook start
- play start
- task start
- task ok / skipped / failed / unreachable
- stage checkpoint debug tasks
- final playbook stats

Machine-readable workflow definitions live under:

- `/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-vm-install-and-boot.json`
- `/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-destination-install-sequences.json`

Those manifests document the repeatable operator sequence for:

- QCOW build
- installer VM launch
- staged Ansible execution
- control-flow pipeline watching
- boot-role repair iterations
- target-disk boot validation

## ntfy notifications

This subtree now includes both a controller-side callback plugin and a task-level
action plugin for ntfy-compatible notifications:

- `callback_plugins/ntfy.py`
- `callback_plugins/control_flow.py`
- `action_plugins/ntfy.py`

The callback plugin is enabled in `ansible.cfg`, but it only emits notifications
when configured. The lowest-friction setup is environment-based:

```bash
export ANSIBLE_NTFY_ENABLED=true
export ANSIBLE_NTFY_URL=https://ntfy.sh
export ANSIBLE_NTFY_TOPIC=replace-with-your-topic
```

Optional per-state topics:

- `ANSIBLE_NTFY_TOPIC_SUCCESS`
- `ANSIBLE_NTFY_TOPIC_FAIL`
- `ANSIBLE_NTFY_TOPIC_ERROR`
- `ANSIBLE_NTFY_TOPIC_WARNING`

The callback plugin emits RFC 5424-style syslog lines in the ntfy message body and
maps playbook states onto syslog-style severities:

- playbook start: `info`
- warnings: `warning`
- task failures / unreachable hosts: `err`
- successful completion: `notice`

The control-flow callback is separate from ntfy delivery and is meant to be watched like a
serial console for long-running imaging jobs. Enable it through the wrapper or directly with:

```bash
export ANSIBLE_CONTROL_FLOW_ENABLED=true
export ANSIBLE_CONTROL_FLOW_PATH=/tmp/ansible-control-flow/install.jsonl
```

The action plugin can be used inside playbooks for explicit controller-side messages:

```yaml
- name: Notify ntfy that the install entered validation
  ntfy:
    msg: "Validation phase reached for {{ inventory_hostname }}"
    state: notice
    attrs:
      tags: [hammer_and_wrench]
```

### Package pins and kernel config fragments

The installer supports package pinning and distribution-kernel config snippets
without requiring a full custom savedconfig kernel.

Package atom overrides:

```yaml
kernel_package_atom_override: =sys-kernel/gentoo-kernel-6.1.163
zfs_package_atom: =sys-fs/zfs-2.4.1
zfs_kmod_package_atom: =sys-fs/zfs-kmod-2.4.1
```

Package accept-keywords fragments:

```yaml
portage_package_accept_keywords_files:
  zfs-testing: |
    =sys-fs/zfs-2.4.1 ~amd64
    =sys-fs/zfs-kmod-2.4.1 ~amd64
```

Kernel config fragments merged by `sys-kernel/gentoo-kernel`:

```yaml
kernel_config_fragment_files:
  90-zfs-ftrace.config: |
    # CONFIG_DYNAMIC_FTRACE_WITH_DIRECT_CALLS is not set
    # CONFIG_DYNAMIC_FTRACE_WITH_ARGS is not set
```

These snippets are written to:

- `/etc/portage/package.accept_keywords/*`
- `/etc/kernel/config.d/*.config`

### Translated modular roles

The external `/opt/gentoo-liveiso-ansible` scaffolding used placeholder roles named `zfs`,
`kernel`, `bootloader`, and `finalize`. Those names are now backed by real repo logic:

- `zfs`: creates the native ZFS pool and datasets after `storage` has partitioned the devices
- `kernel`: wraps the current `system_packages` role
- `bootloader`: wraps the current `boot` role
- `finalize`: applies the optional root password hash, enables target services and SSH keys via
  `services` and `network`, and can optionally unmount or reboot the live environment

For native ZFS layouts, you can use this alternate modular sequence:

```yaml
selected_roles:
  - preflight
  - liveiso_prepare
  - storage
  - zfs
  - stage3
  - profile
  - portage
  - chroot_base
  - kernel
  - bootloader
  - finalize
```

Do not mix these wrapper roles with their underlying roles in the same list:

- `kernel` with `system_packages`
- `bootloader` with `boot`
- `finalize` with `network` or `services`

## Managed OpenRC action services

The `services` role installs generic daemonizable OpenRC actions into the target system.
Each `openrc_action_services` item creates:

- `/usr/local/libexec/<name>`
- `/etc/conf.d/<name>`
- `/etc/init.d/<name>`

and enables the service with `rc-update` unless `enabled: false` is set.

Example:

```yaml
openrc_action_services:
  - name: stage4-example
    description: Example managed daemon action
    command: /usr/sbin/crond -f
    runlevel: default
    user: root
    group: root
    enabled: false
```

Included service-definition data files:

- `service-definitions/stage4-heartbeat.yml`

`stage4-heartbeat` is a disabled-by-default long-running logger that appends
periodic host and uptime markers to `/var/log/stage4-heartbeat.log`. It is
meant as a concrete validation target for the managed-service facility.

Example invocation:

```bash
ansible-playbook playbooks/install.yml -l target_system_remote -e @service-definitions/stage4-heartbeat.yml
```

Optional tuning keys:

- `workdir`
- `env_file`
- `umask`
- `output_log`
- `error_log`
- `retry`
- `respawn_delay`
- `respawn_max`
- `reload_signal`
- `dependencies_need`
- `dependencies_use`
- `dependencies_after`
- `dependencies_before`

`zfs` only applies to native ZFS layouts. For `raid-1` and `raid-10`, keep using the `storage`
role by itself because it owns the mdadm-backed provisioning path.

`zfs-boot-root-mirror` specifically means:

- `bpool` is created as a mirror from `zfs_boot_pool_devices`
- `rpool` is created as a mirror from `zfs_root_pool_devices`

### Python environment setup helper

Generate the ansible Python setup script:

```bash
./scripts/generate-ansible-python-setup.sh
```

Then run the generated script (defaults to `scripts/setup-ansible-python-env.sh`) to:

- clone/update this repository
- verify Python 3.11+
- bootstrap `pip` if needed
- install `pipenv` if needed
- install this project's `requirements.txt` into a pipenv

You can override defaults when running the generated script, for example:

```bash
REPO_URL=https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM.git BRANCH=main ./scripts/setup-ansible-python-env.sh
```

## Current implementation notes

This repository is a first-cut scaffold, not a finished fully unattended product. The major
flows are present:

- destructive device wipe and GPT partitioning
- UEFI ESP + swap + ZFS root member provisioning
- native ZFS or mdadm-backed storage selection
- latest-stage3 discovery and extraction
- local profile overlay creation
- generated LLVM/Clang make.conf
- basic chroot setup
- package installation for ZFS + dracut + dist-kernel strategy
- prebuilt ZFSBootMenu EFI deployment
- OpenRC service enablement for ZFS, NetworkManager, and sshd
- modular wrapper roles for `zfs`, `kernel`, `bootloader`, and `finalize`

The pieces most likely to need local policy refinement are:

- whether your target make.conf should inherit from an existing house style template
- the exact parent list for the custom profile overlay
- your preferred kernel strategy
- your exact `USE`, `CPU_FLAGS_X86`, and package masks
- any encrypted storage workflow
- multi-ESP synchronization on multi-disk installs

## YAML profile definitions

If you want to carry house policy as data instead of editing the roles, set
`profile_definition_files` to one or more YAML files with a top-level
`gentoo_profile_definition` mapping. Supported keys are:

- `repository_enable`
- `make_conf_append`
- `env_files`
- `package_env_files`
- `package_use_files`
- `package_accept_keywords_files`
- `package_mask_files`
- `package_mask_symlinks`
- `kernel_config_fragment_files`

An optional `metadata` mapping may also be present. The installer ignores that
block, but it is useful for keeping package lists, GCC fallback policy, and
validated exact-version pin sets next to the active Portage profile data.

The included presets:

- `profile-definitions/hardened-llvm-stage4.yml`
- `profile-definitions/llvm-clang-hardened-portage.yml`

adds the Hardened LLVM/OpenRC stage4 policy from the separate setup draft:

- enables `guru`, `xira`, and `without-systemd`
- appends hardened LLVM-oriented `make.conf` settings
- installs extra `package.use` fragments for LLVM and elogind replacements
- installs `package.mask` fragments including the `without-systemd` mask link

The LLVM/Clang Portage baseline preset:

- keeps the default compiler, linker, and binutils-facing variables on LLVM
- appends hardening and ThinLTO settings to the generated `make.conf`
- writes `/etc/portage/env/gcc-compat.conf`
- constrains GCC fallback to explicit `package.env` atoms such as `sys-devel/gcc`
  and `sys-libs/glibc`
- documents validated exact-version pin sets in:
  `profile-definitions/llvm-clang-hardened-portage.metadata.yml`

This LLVM/Clang Portage baseline is now enabled by default in the shipped
example, qemu-alias, and vm-stage4 inventories. Override `profile_definition_files`
explicitly only if you want to replace that default policy.

Example:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/hardened-llvm-stage4.yml"
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
```
- per-interface network policy beyond enabling NetworkManager

## Suggested next steps

1. Decide whether mdadm-backed layouts should remain supported at all.
2. Add optional LUKS-on-top-of-partition, then ZFS inside LUKS.
3. Add per-host files under `inventories/examples/host_vars/`.
4. Replace the prebuilt ZFSBootMenu download with local image generation if desired.
5. Add a post-install validation play.
