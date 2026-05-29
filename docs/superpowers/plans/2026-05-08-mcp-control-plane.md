# MCP Control Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repo-managed MCP candidate registry, risk policy, and Stage5 VM profile scaffold.

**Architecture:** The first implementation is render-only and profile-driven. Ansible resolves `mcp_control_plane` data from profile definitions, then renders policy files under `/etc/mcp-control-plane` without installing third-party MCP services or enabling mutation authority.

**Tech Stack:** Gentoo Stage4/Stage5 profile YAML, Ansible roles/templates, shell regression tests, Markdown docs/wiki mirrors.

---

### Task 1: Add Regression Coverage

**Files:**
- Create: `tests/shell/test_mcp_control_plane.sh`
- Modify: `tests/shell/run-tests.sh`
- Modify: `tests/shell/test_system_profiles.sh`

- [x] **Step 1: Write a failing shell test**

Verify the MCP docs, profile, package list, role defaults, templates, and preflight/install wiring exist.

- [x] **Step 2: Run the failing test**

Run: `bash tests/shell/test_mcp_control_plane.sh`

Expected: fail while the scaffold is absent.

### Task 2: Add Profile And Role Scaffold

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-mcp-control-plane.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-mcp-control-plane.metadata.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/stage5-virtual-host-mcp-control-plane.packages`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/mcp_control_plane/defaults/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/mcp_control_plane/tasks/main.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/mcp_control_plane/templates/candidate-registry.yml.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/mcp_control_plane/templates/promotion-policy.yml.j2`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/mcp_control_plane/templates/mcp-control-plane.env.j2`

- [x] **Step 1: Define the Stage5 virtual-host profile**

The profile enables `mcp_control_plane`, sets read-only defaults, and references the package list.

- [x] **Step 2: Define the render-only role**

The role creates the install root and renders registry, promotion, and env files from resolved profile data.

### Task 3: Wire Profile Resolution

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/preflight/tasks/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/preflight/tasks/load_profile_definition.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/install.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/vars/install_sequences.yml`

- [x] **Step 1: Add `resolved_profile_mcp_control_plane` to preflight defaults and override reapply**

This makes inventory-level overrides win after profile layering.

- [x] **Step 2: Merge profile `mcp_control_plane` blocks**

Profile definition files can now layer MCP policy data like other Stage5 services.

- [x] **Step 3: Add `mcp_control_plane` to install sequences**

The role is available in full and service-repair stages without being destructive.

### Task 4: Add Documentation And Roadmap Entries

**Files:**
- Create: `docs/MCP-CONTROL-PLANE.md`
- Create: `docs/wiki/MCP-Control-Plane.md`
- Modify: `docs/wiki/_Sidebar.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/wiki/Changelog.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`

- [x] **Step 1: Document MCP policy and candidate registry**

Include source URLs, risk tiers, and promotion rules.

- [x] **Step 2: Track OpenShift and OpenStack as platform-service TODOs**

Record the VM role/profile requirements and the Gentoo/OpenRC feasibility gate.

### Task 5: Verify And Publish

**Files:**
- All files above.

- [ ] **Step 1: Run focused tests**

Run:

```bash
git diff --check
bash tests/shell/test_mcp_control_plane.sh
bash tests/shell/test_system_profiles.sh
bash -n tests/shell/test_mcp_control_plane.sh
```

- [ ] **Step 2: Commit and push**

Run:

```bash
git status --short
git add .
git commit -m "Add MCP control plane scaffold"
git push -u origin codex/mcp-control-plane
```
