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

The default target profile is effectively:

- amd64
- openrc
- llvm
- split-usr
- no-multilib
- hardened

Gentoo exposes these profile axes, but this scaffold treats the exact combination as a local
profile overlay so that the installer can compose the desired state cleanly and predictably.
The default split-usr overlay parents are:

- `gentoo:default/linux/amd64/23.0/llvm`
- `gentoo:default/linux/amd64/23.0/split-usr/no-multilib/hardened`

For merged-usr consumers such as container roots and new VM profiles, use the
parallel merged-usr overlay definition:

- `profile-definitions/hardened-llvm-stage4-merged-usr.yml`

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

- `x86_64_v2_generic`
- `x86_64_v3_generic`
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

### Path A: LiveISO execution from the target or installer VM

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

### Deploy a private ntfy server

Use the dedicated `ntfy_servers` inventory group for a standalone notification
endpoint. This is intentionally separate from the imaging workflow so private
operator messaging can live on an infrastructure host that is not itself being
reimaged.

```bash
./scripts/bootstrap-liveiso.sh
vim inventories/examples/hosts.yml
vim inventories/examples/group_vars/ntfy_servers.yml
ansible-playbook -i inventories/examples/hosts.yml playbooks/ntfy-server.yml -l ntfy_primary
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

### Path B: iPXE asset publication for fleet bootstrapping

Use this path when hosts or VMs should reach a Gentoo provisioning environment
through DHCP/TFTP or UEFI HTTP into iPXE, then fetch kernel/initramfs/rootfs
artifacts over HTTP/HTTPS before running the same Stage4 workflow.

Build the provisioning artifacts first:

```bash
bash scripts/build-path-b-netboot-artifacts.sh
```

```bash
ansible-playbook \
  -i inventories/examples/hosts.yml \
  playbooks/netboot-path-b.yml \
  -l netboot_control_local
```

This renders:

- `bootstrap.ipxe`
- `menu.ipxe`
- `roles/*.ipxe`
- `hosts/*.ipxe`
- `manifests/path-b-netboot.json`

Path B host metadata should be defined on the `install_targets` inventory
entries themselves so the same host records drive Ansible control, iPXE
dispatch, and published manifest data:

```yaml
target_system_remote:
  ansible_host: 10.9.8.7
  ansible_user: root
  ansible_python_interpreter: /usr/bin/python3
  netboot_enabled: true
  netboot_interface_name: eth0
  netboot_mac_address: "52:54:00:12:34:56"
  netboot_type: dhcp
  netboot_dhcp_client_options:
    - "class-id=PXEClient:Arch:00000:UNDI:002001"
  netboot_os_type: linux
  netboot_os_name: gentoo
  netboot_os_version: stage4-current
  netboot_machine_type: qemu
  netboot_platform: uefi
  netboot_arch: amd64
  netboot_role: installer
```

Relevant enums:

- `netboot_type`: `static`, `dhcp`, `bootp`
- `netboot_os_type`: `linux`, `bsd`, `router-os`, `solaris`, `other`
- `netboot_os_name`: `gentoo`, `centos`, `rocky`, `debian`, `devuan`, `solaris`, `tribblix`, `dietpi`, `fedora`, `freebsd`, `netbsd`, `other`
- `netboot_machine_type`: `metal`, `qemu`, `xen`, `embedded`
- `netboot_platform`: `bios`, `uefi`, `other`
- `netboot_arch`: `amd64`, `arm64`, `ppc64le`, `other`

Optional fields:

- `netboot_host_alias`
- `netboot_script_name`
- `netboot_static_address`
- `netboot_gateway`

The rendered role scripts now boot the published SquashFS environment through
dracut live-boot arguments such as:

- `root=live:http://.../artifacts/gentoo-installer/rootfs.img`
- `rd.live.image`
- `ip=dhcp`

Path A remains the supported fallback for systems that cannot join the iPXE
network or otherwise require a LiveISO-style entry path.

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

The default `target-integration` stage now includes two additional roles:

- `platform_profile`
- `identity`
- `container_host`
- `container_app_ntfy`
- `container_app_nginx`
- `container_app_haproxy`
- `container_net_policy`
- `container_service_segments`

`platform_profile` writes profile-driven `modules-load.d` fragments and enables native
OpenRC services. `identity` creates local users and, when requested, writes NoCloud
compatible `cloud-init` seed data under `/var/lib/cloud/seed/nocloud-net/`.
The container roles are dormant unless a profile defines
`container_services.enabled: true`; when enabled, they render Podman host config,
service-segment network helpers, site-security `nftables` policy, and app-profile
artifacts for `ntfy`, `nginx`, and `haproxy`.

### Ephemeral memory-backed storage

Two separate knobs now exist for faster iterative VM development:

- hypervisor-side tmpfs-backed QEMU disks via `playbooks/qemu-memory-drives.yml`
- guest-side tmpfs mounts via the `memory_storage` role in `target-integration`

Hypervisor-side example:

```bash
ansible-playbook \
  -i inventories/examples/hosts.yml \
  playbooks/qemu-memory-drives.yml \
  -l qemu_control_local \
  -e qemu_memory_drives_enabled=true \
  -e qemu_memory_drives_instance_name=stage4-devvm
```

That renders a manifest such as:

```text
/dev/shm/qemu-memory-drives/stage4-devvm/memory-drives.json
```

and the stage3 launcher can attach it with:

```bash
QEMU_MEMORY_DRIVES_FILE=/dev/shm/qemu-memory-drives/stage4-devvm/memory-drives.json \
bash ../../gentoo-virt-qemu/qemu-launch-stage3-vm.sh
```

Guest-side example for a container host:

```yaml
profile_container_services:
  runtime_root: /var/lib/container-services-ephemeral

profile_memory_storage:
  enabled: true
  mounts:
    - path: /var/lib/container-services-ephemeral
      size: 32G
      mode: "0755"
      options:
        - noatime
```

This is intended for:

- Portage tmpdirs and caches
- Podman image/runtime scratch space
- disposable application data for short-lived development containers

### Container-Services VM profile

Use the simple guest profile as the base, then layer the container-services overlay:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-simple-ipxe.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-container-services.yml"
```

Example host-vars file:

- `inventories/examples/host_vars/vm-container-services.yml`

The profile adds:

- Podman plus `conmon`, `crun`, `netavark`, `aardvark-dns`, `fuse-overlayfs`
- `nftables`-driven site-security policy
- profile-driven container service segments
- app-profile roles for `ntfy`, `nginx`, and `haproxy`
- optional IPAM ingestion from a flat JSON file or a pre-normalized NetBox API endpoint
- a narrow `sys-apps/systemd-utils` exception scoped only to the Podman/netavark container stack while keeping the repo-wide `without-systemd` posture elsewhere

### Jenkins controller and distcc builder farm

The repo now carries a Stage 5 controller profile plus a Stage 5 builder-farm
worker profile:

- `profile-definitions/vm-jenkins-controller.yml`
- `profile-definitions/metal-builder-farm-node.yml`

Example controller stack:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-application-server.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-jenkins-controller.yml"
```

Example builder node stack:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-baremetal.yml"
  - "{{ playbook_dir }}/../profile-definitions/metal-builder-farm-node.yml"
```

Supporting examples:

- `inventories/examples/host_vars/vm-jenkins-controller.yml`
- `inventories/examples/group_vars/ci_controllers.yml`
- `inventories/examples/group_vars/builder_farm_nodes.yml`

These roles render:

- a Jenkins controller launcher plus JCasC manifest
- distcc client and worker manifests
- managed `DISTCC_HOSTS` policy in `make.conf` with local fallback disabled
- OpenRC-managed `jenkins-controller` and `distccd-farm` services

The intended first fabric is a dedicated builder LAN carried to a switch and
uplinked from one of the BlueField2 interfaces:

- `ens7f0np0`
- `ens7f1np0`

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
- `/root/RFC_Codex_Gentoo-Stage4-LLVM/docs/workflows/ntfy-server-deployment.json`

Those manifests document the repeatable operator sequence for:

- QCOW build
- installer VM launch
- staged Ansible execution
- control-flow pipeline watching
- boot-role repair iterations
- target-disk boot validation
- private ntfy server deployment and health validation

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
export ANSIBLE_NTFY_URL=http://msg-sun99-ntfysys.rfc1918.host
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

## Private ntfy server deployment

This subtree now also carries a dedicated private ntfy server role and playbook:

- `playbooks/ntfy-server.yml`
- `roles/ntfy_server`
- `inventories/examples/group_vars/ntfy_servers.yml`

The role is OpenRC-oriented and supports:

- `ntfy_server_install_method: binary` (default, upstream release tarball)
- `ntfy_server_install_method: package` (override for distros with a packaged ntfy)
- declarative `auth-users` and `auth-access` policy in `server.yml`
- a repo-managed OpenRC `init.d` and `conf.d`

Run a syntax check before touching a live host:

```bash
ansible-playbook -i inventories/examples/hosts.yml playbooks/ntfy-server.yml --syntax-check
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
- OpenRC service enablement for ZFS, netifrc/Open vSwitch, and sshd
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
- `package_unmask_files`
- `package_mask_symlinks`
- `kernel_config_fragment_files`
- `package_atoms`
- `package_list_files`
- `modules_load_files`
- `openrc_services_enable`
- `cloud_init`
- `jenkins_controller`
- `distcc_farm`

## Stage language

The repo uses a layered profile language:

- `Stage 4`
  - shared OS baseline policy
  - compiler, linker, hardening, OpenRC, and Portage behavior
  - example: `llvm-clang-hardened-portage.yml`
- `Stage 5`
  - role overlay
  - host or service intent carried on top of the Stage 4 baseline
  - package layers, module hints, service defaults, and role-specific policy

Current Stage 5 role classes:

- `baremetal-base`
- `baremetal-hypervisor`
- `metal-host`
- `virtual-host`
- `service-container`
- `cloud-init-overlay`
- `ci-controller`
- `builder-farm-node`

For scalability, Stage 5 package sets should live in external flat files under
`profile-package-lists/` and be referenced through `package_list_files` instead
of embedding long `package_atoms` lists inline.

Service-level atoms that bind package lists, OpenRC services, kernel modules,
and protocol surfaces are tracked under `profile-service-atoms/`.

The included Stage 4 presets:

- `profile-definitions/hardened-llvm-stage4.yml`
- `profile-definitions/hardened-llvm-stage4-split-usr.yml`
- `profile-definitions/hardened-llvm-stage4-merged-usr.yml`
- `profile-definitions/llvm-clang-hardened-portage.yml`

The compatibility alias `hardened-llvm-stage4.yml` retains the split-usr
baseline. The explicit split-usr and merged-usr variants make usr-layout
selection data-driven for new consumers.

The Stage 4 policy adds:

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
  - "{{ playbook_dir }}/../profile-definitions/hardened-llvm-stage4-split-usr.yml"
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
```

## Gentoo system profiles

The repo now carries a reusable LLVM/Clang Portage baseline, explicit base role
overlays, virtual-machine overlays, and modular cloud-init overlays:

- `profile-definitions/llvm-clang-hardened-portage.yml`
- `profile-definitions/base-minimal-nox.yml`
- `profile-definitions/base-minimal-xorg-slim.yml`
- `profile-definitions/base-hypervisor-xen.yml`
- `profile-definitions/base-hypervisor-qemu-libvirt.yml`
- `profile-definitions/base-hypervisor-xen-qemu-libvirt.yml`
- `profile-definitions/virt-minimal.yml`
- `profile-definitions/virt-xorg.yml`
- `profile-definitions/cloud-init-baremetal.yml`
- `profile-definitions/cloud-init-vm.yml`
- `profile-definitions/hypervisor-xen-qemu-libvirt-host.yml`
- `profile-definitions/vm-guest-application-server.yml`
- `profile-definitions/vm-guest-simple-ipxe.yml`

Use them as stacked data, with the Stage 4 baseline first and the Stage 5 role
overlay(s) after it.

For new VM profiles that should match container-root behavior, prefer:

- `profile-definitions/hardened-llvm-stage4-merged-usr.yml`

For existing metal or compatibility-sensitive installs, keep:

- `profile-definitions/hardened-llvm-stage4-split-usr.yml`

### Hypervisor host profile

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-baremetal.yml"
  - "{{ playbook_dir }}/../profile-definitions/hypervisor-xen-qemu-libvirt-host.yml"
```

This profile targets bare-metal Xen/QEMU/Libvirt hosts and adds:

- Xen, Xen tools, QEMU, Libvirt, guestfs tools
- Open vSwitch
- NVMe-oF and RDMA userland support
- NVDIMM / PMem tooling via `ndctl`
- ZFS 2.4.x testing-track pins
- kernel modules for `nvme-rdma`, `mlx5_*`, `qede`, `libnvdimm`, `nd_pmem`, and `zfs`

Vendor-managed pieces are explicitly tracked in metadata rather than forced into
Portage:

- BlueField2 DOCA / MLNX_OFED host drivers
- AMDGPU Pro userspace nuances beyond Gentoo-provided `amdgpu-pro-vulkan`

### VM guest application-server profile

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-application-server.yml"
```

This profile targets hardened OpenRC guests with:

- serial console plus SSH-only operational model
- `qemu-guest-agent`
- `xe-guest-utilities`
- `bonding`, `virtio_*`, and `xen_*front` kernel module load hints
- cloud-init behavior supplied by the separate `cloud-init-vm` overlay

### VM guest simple iPXE profile

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"
  - "{{ playbook_dir }}/../profile-definitions/vm-guest-simple-ipxe.yml"
```

This profile keeps the package set small for Path B bring-up and repeatable iPXE
testing.

### Per-host accounts and cloud-init

Use the modular cloud-init overlays to enable package and datasource defaults, then
keep host-specific instance IDs, hostnames, and users in inventory:

```yaml
profile_definition_files:
  - "{{ playbook_dir }}/../profile-definitions/cloud-init-vm.yml"

profile_local_user_accounts:
  - name: deploy
    groups:
      - wheel
    sudo_nopasswd: true
    ssh_authorized_keys: []

profile_cloud_init:
  instance_id: vm-guest-appserver
  local_hostname: appserver
```

Example host records are included under:

- `inventories/examples/host_vars/hypervisor-host.yml`
- `inventories/examples/host_vars/vm-guest-appserver.yml`
- `inventories/examples/host_vars/vm-guest-simple.yml`

Each profile also has a matching `*.metadata.yml` file that records package pinning,
kernel-module expectations, and any vendor-managed components that are outside the
Gentoo tree.
- advanced per-interface network policy beyond the managed netifrc/Open vSwitch renderer

## Suggested next steps

1. Decide whether mdadm-backed layouts should remain supported at all.
2. Add optional LUKS-on-top-of-partition, then ZFS inside LUKS.
3. Add per-host files under `inventories/examples/host_vars/`.
4. Replace the prebuilt ZFSBootMenu download with local image generation if desired.
5. Add a post-install validation play.
