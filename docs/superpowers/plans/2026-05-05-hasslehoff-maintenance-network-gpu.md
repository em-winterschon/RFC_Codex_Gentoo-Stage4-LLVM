# Hasslehoff Maintenance Network GPU Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend Hasslehoff automation for GPU passthrough, QLogic LACP, PVE8 maintenance upgrades, and gated DOCA/OFED installation.

**Architecture:** Extend existing roles instead of adding one-off scripts. Keep live changes gated: GPU config can render files, Proxmox upgrades require `proxmox_host_upgrade_apply=true`, DOCA/OFED requires explicit repo input and custom-kernel acknowledgement, and RouterOS LACP remains render-only.

**Tech Stack:** Ansible Core, Proxmox VE 8, ZFS, RouterOS render templates, Linux modprobe/vfio, ethtool recommendations.

---

### Task 1: Extend GPU Host Policy

**Files:**
- Modify `roles/gpu_host_policy/defaults/main.yml`
- Modify `roles/gpu_host_policy/tasks/main.yml`
- Add `roles/gpu_host_policy/templates/vfio-pci-gpu.conf.j2`
- Add `roles/gpu_host_policy/templates/vfio-modules.conf.j2`
- Modify `playbooks/gpu-host-policy-render-check.yml`
- Modify `inventories/local-network/host_vars/hasslehoff.yml`

Steps:

- [ ] Add `gpu_passthrough_enabled`, vfio ID variables, Proxmox kernel cmdline variables, and Proxmox boot-tool refresh gates.
- [ ] Render vfio-pci and modules-load config when passthrough is enabled.
- [ ] Render `/etc/kernel/cmdline` only when explicitly enabled.
- [ ] Add Hasslehoff K1200 IDs and `snd_hda_intel` blacklist to host vars.
- [ ] Validate with `ANSIBLE_STDOUT_CALLBACK=default ansible-playbook playbooks/gpu-host-policy-render-check.yml`.

### Task 2: Add Proxmox Host Upgrade Role

**Files:**
- Add `roles/proxmox_host_upgrade/defaults/main.yml`
- Add `roles/proxmox_host_upgrade/tasks/main.yml`
- Add `playbooks/proxmox-host-upgrade.yml`

Steps:

- [ ] Add plan-only defaults.
- [ ] Validate PVE8 lane and reject PVE9/Trixie apt sources.
- [ ] Add pre/post recursive ZFS snapshot actions gated by `proxmox_host_upgrade_apply`.
- [ ] Add apt update/dist-upgrade and `proxmox-boot-tool refresh`, also gated.
- [ ] Validate syntax with the local-network inventory.

### Task 3: Add NVIDIA DOCA/OFED Gate

**Files:**
- Add `roles/nvidia_doca_ofed/defaults/main.yml`
- Add `roles/nvidia_doca_ofed/tasks/main.yml`
- Add `playbooks/nvidia-doca-ofed.yml`
- Modify `inventories/local-network/hosts.yml`

Steps:

- [ ] Add gated repo package installation from URL or local `.deb`.
- [ ] Require matching kernel headers/build tree.
- [ ] Require explicit custom-kernel acknowledgement for Proxmox kernels.
- [ ] Add `roce_hosts` inventory group with Hasslehoff disabled by default.

### Task 4: Update QLogic/CRS309 LACP Intent

**Files:**
- Modify `roles/routeros_spine_distribution/defaults/main.yml`
- Modify `roles/routeros_spine_distribution/tasks/main.yml`
- Modify `roles/routeros_spine_distribution/templates/crs309-spine.rsc.j2`
- Modify `inventories/local-network/group_vars/all/network_fabric.yml`
- Add `docs/QLOGIC-CRS309-LACP.md`

Steps:

- [ ] Rename former CCR-PCI intent to Hasslehoff QLogic intent.
- [ ] Render `bond-hasslehoff-qlogic` over CRS309 `sfp-sfpplus4/5`.
- [ ] Document Linux bond and first-pass ethtool tuning recommendations.

### Task 5: Validate And Commit

Steps:

- [ ] Run `git diff --check`.
- [ ] Run vault validation.
- [ ] Run local-network inventory parse assertions.
- [ ] Run syntax checks for GPU, BMC, Proxmox upgrade, NVIDIA DOCA/OFED, and RouterOS spine render playbooks.
- [ ] Run GPU render check.
- [ ] Commit and push.
