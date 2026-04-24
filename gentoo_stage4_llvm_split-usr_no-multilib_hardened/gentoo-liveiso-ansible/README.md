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
ansible-playbook playbooks/install.yml -l liveiso-local --connection=local
```

### Remote execution against a booted LiveISO

```bash
./scripts/bootstrap-liveiso.sh
vim inventories/examples/hosts.yml
vim inventories/examples/group_vars/install_targets.yml
ansible-playbook playbooks/install.yml -l remote-liveiso
```

### Modular role selection

The installer runs a default ordered role sequence:

- `preflight`
- `liveiso_prepare`
- `storage`
- `stage3`
- `profile`
- `portage`
- `chroot_base`
- `system_packages`
- `boot`
- `network`
- `services`

Override `selected_roles` in inventory or at the command line if you need to rerun only a
subset while iterating on one part of the install flow.

Example inventory override:

```yaml
selected_roles:
  - storage
  - stage3
  - profile
  - portage
  - boot
```

Example command-line override:

```bash
ansible-playbook playbooks/install.yml -l remote-liveiso -e '{"selected_roles":["boot","network"]}'
```

Machine-readable workflow definitions for the VM validation path live under:

- `/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/stage4-vm-install-and-boot.json`

That manifest documents the repeatable operator sequence for:

- QCOW build
- installer VM launch
- Ansible connectivity checks
- full install execution
- boot-role repair iterations
- target-disk boot validation

## ntfy notifications

This subtree now includes both a controller-side callback plugin and a task-level
action plugin for ntfy-compatible notifications:

- `callback_plugins/ntfy.py`
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

The action plugin can be used inside playbooks for explicit controller-side messages:

```yaml
- name: Notify ntfy that the install entered validation
  ntfy:
    msg: "Validation phase reached for {{ inventory_hostname }}"
    state: notice
    attrs:
      tags: [hammer_and_wrench]
```

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
ansible-playbook playbooks/install.yml -l remote-liveiso -e @service-definitions/stage4-heartbeat.yml
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
- `package_use_files`
- `package_mask_files`
- `package_mask_symlinks`

The included preset:

- `profile-definitions/hardened-llvm-stage4.yml`

adds the Hardened LLVM/OpenRC stage4 policy from the separate setup draft:

- enables `guru`, `xira`, and `without-systemd`
- appends hardened LLVM-oriented `make.conf` settings
- installs extra `package.use` fragments for LLVM and elogind replacements
- installs `package.mask` fragments including the `without-systemd` mask link

Example:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/hardened-llvm-stage4.yml"
```
- per-interface network policy beyond enabling NetworkManager

## Suggested next steps

1. Decide whether mdadm-backed layouts should remain supported at all.
2. Add optional LUKS-on-top-of-partition, then ZFS inside LUKS.
3. Add per-host files under `inventories/examples/host_vars/`.
4. Replace the prebuilt ZFSBootMenu download with local image generation if desired.
5. Add a post-install validation play.
