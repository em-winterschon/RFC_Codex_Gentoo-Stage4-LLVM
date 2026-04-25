# Architecture and Design

## System Shape

The repository is organized into three layers:

1. **Build and host orchestration**
   QEMU, OpenRC host services, VFIO helpers, and validation wrappers
2. **Installer orchestration**
   staged Ansible roles that partition disks, build the Gentoo target, install boot flow, and configure services
3. **Operator visibility**
   JSONL control-flow logs, ntfy notifications, GitHub workflows, and Codex approval watching

## Design Patterns

### 1. Staged Playbook Execution

The installer does not rely on a single opaque play. It uses named sequences such as:

- `storage-foundation`
- `chroot-bootstrap`
- `target-integration`
- `repair-boot`
- `repair-services`

Each sequence expands into stage blocks with:

- a stable stage identifier
- explicit roles
- optional debug checkpoints
- structured control-flow output

This allows partial reruns without rebuilding the entire target state.

### 2. Inventory Specialization

Inventories are separated by operational context:

- `inventories/examples`
  generic examples and placeholder targets
- `inventories/vm-stage4`
  local validation VM flow
- `inventories/qemu-alias`
  alias-mode installer VM control path through `10.9.8.108:2222`

This prevents accidental cross-use of physical device IDs and VM-visible QEMU device IDs.

### 3. Native ZFS Preference

Preferred storage paths are native ZFS, especially:

- `zfs-mirror`
- `zfs-boot-root-mirror`
- `zraid*`
- `draid`

`zfs-boot-root-mirror` is the core target pattern:

- mirrored SATADOM pair for `bpool`
- mirrored HDD/SSD pair for `rpool`
- ZFSBootMenu on the ESP
- boot artifacts materialized into `/boot`

### 4. LLVM/OpenRC Baseline

The build pipeline intentionally aligns with:

- Gentoo `llvm-openrc` stage3
- local overlay profiles for hardened, split-usr, and no-multilib combinations
- Clang/LLD-driven Portage defaults when practical

This keeps the runtime aligned with infrastructure assumptions and avoids relying on the official systemd cloud image path.

### 5. Operator-Observable Long Runs

Long-running actions are expected to be remotely visible. Two parallel channels exist:

- structured JSONL control-flow for deterministic execution state
- ntfy-based notifications for asynchronous operator awareness

The JSONL callback is the authoritative execution stream. ntfy is the attention channel.

## Design Principles

### Explicit destructive intent

Disk provisioning must require an explicit acknowledgment such as:

- `storage_confirm_destroy: true`

### Favor idempotent repair paths

The system should support tail-role reruns and recovery paths, not only pristine installs.

### Separate transport from target identity

Examples:

- alias-mode VM networking uses guest `10.9.8.7`, but Ansible targets `10.9.8.108:2222`
- target-disk boot is a different validation state than installer-QCOW boot

### Keep documentation executable

Operational docs should line up with:

- real commands
- expected return codes
- generated artifacts
- machine-readable workflow manifests

## Control-Flow Pipeline

Current implementation:

- callback plugin writes JSONL events
- wrapper script sets `ANSIBLE_CONTROL_FLOW_PATH`
- watcher tails the log in near-real time

This was chosen over raw console scraping because it scales better to:

- multi-stage installs
- multiple hosts or VMs
- external observers
- future aggregation

## Notification Architecture

The repository has three notification domains:

- **Ansible**
  controller callback plus task-level `ntfy` action plugin
- **GitHub**
  repository event workflow notifications
- **Codex/operator**
  turn-complete notifications, hooks, and persistent approval watcher

Messages are rendered as RFC 5424-style syslog lines and then mapped to ntfy priorities.

## Why the Current VM Path Exists

The preferred QEMU path exists because:

- official Gentoo cloud-init QCOW images are systemd-based
- manual minimal-ISO console workflows are not suitable for unattended validation
- Stage3 QCOW building makes the VM path match the real target assumptions

## Invariants

These should stay true unless there is an explicit design change:

- target installs remain OpenRC-first
- `bpool` and `rpool` are mirrored in `zfs-boot-root-mirror`
- boot validation includes direct target-disk boot, not only installer-QCOW boot
- operator-visible control-flow remains part of top-level workflows
