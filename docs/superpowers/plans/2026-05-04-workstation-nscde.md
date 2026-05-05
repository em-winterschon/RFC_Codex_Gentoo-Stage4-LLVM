# Workstation NsCDE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Stage5 workstation VM overlay with Xorg, SPICE, and NsCDE for on-host QEMU validation.

**Architecture:** Add a workstation-specific profile and package layer, keep server VM defaults unchanged, and source-install pinned NsCDE through a dedicated Ansible role. Extend the QEMU stage3 launcher to support SPICE/QXL and provide a wrapper with workstation defaults.

**Tech Stack:** Gentoo Stage4/Stage5 profile definitions, OpenRC, Xorg, SPICE/QXL, NsCDE `2.3`, Ansible, shell tests.

---

### Task 1: Profile And Package Layer

**Files:**
- Create: `profile-definitions/vm-workstation-nscde.yml`
- Create: `profile-definitions/vm-workstation-nscde.metadata.yml`
- Create: `profile-package-lists/stage5-virtual-host-workstation-nscde.packages`
- Modify: `inventories/examples/host_vars/vm-workstation-nscde.yml`
- Modify: `inventories/examples/hosts.yml`

- [x] **Step 1: Add normalized package atoms**

Use current Gentoo atom names instead of stale upstream names:

```text
x11-base/xorg-server
x11-base/xorg-apps
x11-base/xorg-drivers
x11-base/xorg-fonts
dev-python/pyqt5
x11-wm/fvwm3
app-emulation/spice-vdagent
```

- [x] **Step 2: Add profile metadata**

Track profile taxonomy, package layers, NsCDE source version, and the SPICE/QXL
validation path.

### Task 2: NsCDE Role

**Files:**
- Create: `roles/nscde_workstation/defaults/main.yml`
- Create: `roles/nscde_workstation/tasks/main.yml`
- Create: `roles/nscde_workstation/templates/nscde.sh.j2`
- Create: `roles/nscde_workstation/templates/xinitrc.j2`
- Modify: `roles/preflight/tasks/main.yml`
- Modify: `roles/preflight/tasks/load_profile_definition.yml`
- Modify: `playbooks/install.yml`
- Modify: `vars/install_sequences.yml`

- [x] **Step 1: Add profile merge plumbing**

Expose `resolved_profile_nscde_workstation` through the preflight/profile
loader pipeline.

- [x] **Step 2: Install pinned source**

Download `https://github.com/NsCDE/NsCDE/archive/refs/tags/2.3.tar.gz`, verify
SHA256, run `./configure`, `make`, and `make install` in the target chroot.

### Task 3: QEMU SPICE Launcher

**Files:**
- Modify: `gentoo-virt-qemu/qemu-launch-stage3-vm.sh`
- Create: `gentoo-virt-qemu/qemu-launch-workstation-nscde-vm.sh`

- [x] **Step 1: Add SPICE/QXL support**

Support `QEMU_DISPLAY_MODE=spice`, `QEMU_VIDEO_DEVICE=qxl-vga`, and the SPICE
agent virtio serial channel.

- [x] **Step 2: Add workstation wrapper**

Set defaults for instance name, SPICE port, SSH port, vCPU count, and memory.

### Task 4: Tests And Documentation

**Files:**
- Modify: `tests/shell/test_system_profiles.sh`
- Modify: `tests/shell/test_qemu_launch_stage3_vm.sh`
- Create: `tests/shell/test_qemu_launch_workstation_nscde_vm.sh`
- Create: `docs/WORKSTATION-NSCDE.md`
- Create: `docs/wiki/Workstation-NsCDE.md`

- [x] **Step 1: Add tests**

Run:

```bash
bash tests/shell/test_system_profiles.sh
bash tests/shell/test_qemu_launch_stage3_vm.sh
bash tests/shell/test_qemu_launch_workstation_nscde_vm.sh
```

- [ ] **Step 2: Live build validation**

Run the on-host QEMU build after repo checks pass. Capture SSH, SPICE, DBus,
`spice-vdagent`, and `startx` validation evidence.
