# Stage4 LOX Workstation GPU Binpkg Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encode Stage4 LOX workstation naming, universal Xorg GPU package policy, no-Wayland guardrails, captured package review sets, and binpkg repository metadata.

**Architecture:** Keep active package policy curated while storing host captures as review inputs. Use shell tests to prevent Wayland/Plasma regressions and verify canonical repository IDs. Avoid importing raw former-host Portage archives because they may contain secrets.

**Tech Stack:** Bash, Ansible profile definitions, Gentoo Portage package atoms, Markdown docs, repo shell tests.

---

### Task 1: Capture Review Data

**Files:**
- Create: `scripts/generate-workstation-package-review.sh`
- Create: `docs/workstation-package-capture/microbox-2026-05-06/`
- Create: `docs/workstation-package-capture/stage4-lox-workstation-review-2026-05-06/`

- [ ] **Step 1:** Import the microbox capture files from the provided tarball.
- [ ] **Step 2:** Generate shared, host-specific, union, reject, and review-candidate atom lists.
- [ ] **Step 3:** Store generated counts in a review README.

### Task 2: Former Host Policy

**Files:**
- Create: `docs/workstation-package-capture/former-portage-policy/README.md`
- Create: `docs/workstation-package-capture/former-portage-policy/gpu-universal-xorg-advisory.atoms`

- [ ] **Step 1:** Summarize useful former-host Portage policy without copying raw archive contents.
- [ ] **Step 2:** Record advisory GPU/Xorg package atoms from former hosts and current Gentoo package availability.
- [ ] **Step 3:** State that raw GnuPG material is intentionally excluded.

### Task 3: Profile Policy

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-workstation-nscde.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-workstation-nscde.metadata.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/stage5-virtual-host-workstation-nscde.packages`

- [ ] **Step 1:** Add normalized Stage4 LOX ID metadata.
- [ ] **Step 2:** Expand active workstation GPU package atoms for NVIDIA, AMD, and Intel Xorg support.
- [ ] **Step 3:** Add package.use, package.mask, accept_keywords, and license fragments for universal Xorg GPU support and no-Wayland policy.
- [ ] **Step 4:** Add binpkg output defaults for the workstation repository ID.

### Task 4: Tests And Docs

**Files:**
- Create: `tests/shell/test_workstation_package_policy.sh`
- Modify: `tests/shell/run-tests.sh`
- Modify: `docs/WORKSTATION-PACKAGE-CAPTURE.md`
- Modify: `docs/WORKSTATION-NSCDE.md`
- Modify: `docs/wiki/Workstation-Package-Capture.md`
- Modify: `docs/wiki/Workstation-NsCDE.md`
- Modify: `docs/wiki/_Sidebar.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/wiki/Changelog.md`

- [ ] **Step 1:** Add shell assertions for canonical naming, no-Wayland policy, GPU atoms, and generated review sets.
- [ ] **Step 2:** Document the Stage4 LOX term and package review flow.
- [ ] **Step 3:** Run `bash tests/shell/run-tests.sh`.
- [ ] **Step 4:** Commit the resulting change set.
