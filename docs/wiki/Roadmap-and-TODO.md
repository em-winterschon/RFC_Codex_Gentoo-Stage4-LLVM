# Roadmap and TODO

This page tracks concrete next work, not vague aspirations.

## Immediate TODO

### 1. Commit and push the current PR #15 branch state

Validated work completed locally now exceeds the original PR #15 summary.

Next actions:

- commit the current `codex/fix-zfs-hostid-and-zbm-kcl` branch state
- push the updated branch head
- refresh the PR description so it matches the actual validated scope

### 2. Decide whether PR #15 remains single-scope or gets split

Current branch includes:

- hostid and ZFSBootMenu commandline handling
- validated `gentoo-kernel` + `zfs-kmod` mitigation path
- qemu-alias inventory updates
- regression coverage for installer override paths and the `sole=tty0` typo

Next actions:

- decide whether to merge as one coherent ZFS-boot stabilization PR
- or split the newer kernel/ZFS mitigation work into a follow-up PR

### 3. Validate bridge/tap networking after alias mode

Alias mode is proven and safer for a LiveISO host.

Next actions:

- test `QEMU_NETWORK_MODE=tap`
- test `QEMU_NETWORK_MODE=bridge`
- document failure modes and rollback steps for host networking changes

### 4. Merge-gate enforcement

Technical policy is clear, but GitHub branch protection must remain aligned:

- require PRs
- require `Validate / pre-commit`
- require `Validate / shell-tests`
- require up-to-date branches before merge

## Short-Term Enhancements

### 5. Expand profile-definition usage

The installer already supports:

- `profile_definition_files`

Next actions:

- add more reusable YAML profile definition examples
- document expected schema more explicitly
- validate overlay composition in both VM and destination-host flows

### 6. Extend machine-readable workflow manifests

Current manifests cover the main flows.

Next actions:

- add manifests for alias-mode QEMU imaging
- add manifests for tap/bridge paths
- add expected artifact/state checks for post-install validation

### 7. Add post-install assertion stages

Current installer validation is operational but can go further.

Next actions:

- formalize checks for:
  - `zpool status`
  - mounted root dataset
  - `bpool` mount at `/boot`
  - ZFSBootMenu EFI placement
  - SSH readiness on installed target

## Medium-Term Work

### 8. Multi-host / multi-VM control-flow aggregation

Current JSONL callback works well per run.

Next actions:

- define a stable aggregation format
- correlate runs by host, sequence, and stage
- make watcher tooling friendlier for parallel imaging operations

### 9. Cross-architecture builder execution

Current enum support exists for:

- `amd64-llvm-openrc`
- `arm64-llvm-openrc`
- `power9le-openrc`

But real non-dry-run execution is still same-arch guarded.

Next actions:

- define the cross-arch bootstrap strategy
- decide whether to use native builders, emulation, or per-arch hosts

### 10. GitHub wiki publication automation

Current blocker:

- GitHub wiki remote must exist and be enabled for direct push-based publication

Next actions:

- enable the repository wiki if not already enabled
- add a small publish/update workflow for wiki source synchronization if desired

## Completed Milestones

- native `bpool` + mirrored `rpool` validation in VM path
- target-disk boot path with ZFSBootMenu
- staged Ansible install sequences with checkpoints
- JSONL control-flow callback and watcher
- alias-mode QEMU networking path as the validated standard workflow for the current LiveISO host
- ntfy integration across Ansible, GitHub, and Codex tooling
- persistent Codex approval watcher OpenRC service
- validated `gentoo-kernel` + Gentoo-native ZFS mitigation path that removes the prior `ftrace` warning reproduction on target-disk boot

## Rule for New TODO Items

A new TODO should be:

- directly tied to observed system behavior
- framed as an action, not a theme
- linked to a file, workflow, or runtime state
- removable once validated or rejected
