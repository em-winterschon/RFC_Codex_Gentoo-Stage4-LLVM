# X12AGAIN Reimage And Coherent Scale Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare X12AGAIN to be reimaged as a LOX Stage5 workstation plus Xen/QEMU hypervisor and later admitted as a SLURM/RDMA/Project Coherent Flash scale-model host.

**Architecture:** Keep the live SLURM controller independent from X12AGAIN. Add a host-specific profile and documentation that composes existing workstation, hypervisor, AAA, NFS/RDMA, and SLURM-worker overlays without adding X12AGAIN to the active `slurm_workers` group until E2ET passes. Treat Project Coherent Flash as a simulation-first SLURM workload bundle before any production storage mutation.

**Tech Stack:** Gentoo Stage4 LOX LLVM/OpenRC, Portage profile overlays, Xorg/NsCDE, Xen/QEMU/libvirt, OpenZFS/NVDIMM/RDMA/NFS/NVMe-oF, FreeIPA/SSSD, SLURM, Ansible, shell regression tests.

---

### Task 1: Add X12AGAIN Host Profile Intent

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/metal-x12again-workstation-xen-coherent.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/metal-x12again-workstation-xen-coherent.metadata.yml`
- Modify: `tests/shell/test_x12again_reimage_coherent_scale.sh`
- Modify: `tests/shell/run-tests.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/shell/test_x12again_reimage_coherent_scale.sh` with assertions for the profile, metadata, inherited package lists, kernel fragments, roles, and no live SLURM admission.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/shell/test_x12again_reimage_coherent_scale.sh`
Expected: FAIL because the profile and metadata do not exist yet.

- [ ] **Step 3: Add the profile**

Create the profile with `profile_parents`/`package_list_files` for workstation, hypervisor, NFS storage client, domain client, observability, and SLURM worker policy. Include kernel fragments for `metal-base`, `base-hypervisor-xen-qemu-libvirt`, `gpu-universal-xorg`, `optane-nvdimm`, `nfs-storage-client`, `rdma-storage-fabric`, and `coherence-ce-node`. Keep `slurm_cluster.worker_enabled: false` until E2ET admission.

- [ ] **Step 4: Add metadata**

Create metadata documenting X12AGAIN as a host-specific exception with Intel Optane Series 200 NVDIMM, BlueField2, workstation display support, hypervisor duties, and Project Coherent scale-model intent.

- [ ] **Step 5: Wire test into suite and verify**

Run: `bash tests/shell/test_x12again_reimage_coherent_scale.sh && bash tests/shell/run-tests.sh`
Expected: PASS.

### Task 2: Document X12AGAIN ITIL Change Gates

**Files:**
- Create: `docs/X12AGAIN-WORKSTATION-XEN-COHERENT-SCALE.md`
- Create: `docs/wiki/X12AGAIN-Workstation-Xen-Coherent-Scale.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`
- Modify: `docs/wiki/Changelog.md`
- Modify: `tests/shell/test_x12again_reimage_coherent_scale.sh`

- [ ] **Step 1: Extend the failing test**

Assert both docs exist and contain: hard gates, backup/backout, SLURM admission, BlueField2/RDMA gate, Project Coherent simulation gate, and no production storage mutation.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/shell/test_x12again_reimage_coherent_scale.sh`
Expected: FAIL because docs are missing.

- [ ] **Step 3: Add docs**

Write the change-control document with preflight, implementation, validation, rollback, and post-change evidence sections.

- [ ] **Step 4: Update roadmap/changelog**

Set `WS-009` notes to reference the new profile and change-control doc. Add a 2026-05-13 changelog entry.

- [ ] **Step 5: Verify**

Run: `bash tests/shell/test_x12again_reimage_coherent_scale.sh`
Expected: PASS.

### Task 3: Add Project Coherent SLURM Simulation Bundle Plan

**Files:**
- Create: `docs/PROJECT-COHERENT-FLASH-SLURM-SCALE-MODEL.md`
- Create: `docs/wiki/Project-Coherent-Flash-SLURM-Scale-Model.md`
- Modify: `tests/shell/test_x12again_reimage_coherent_scale.sh`

- [ ] **Step 1: Extend the failing test**

Assert the Project Coherent doc maps ADR-001 through ADR-009 to simulation-only SLURM jobs, metrics, and artifacts.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/shell/test_x12again_reimage_coherent_scale.sh`
Expected: FAIL because the scale-model doc is missing.

- [ ] **Step 3: Add docs**

Define SLURM job classes for KV/prefix cache, object/model tier, RAG/vector tier, synthetic RDMA/NVMe-oF/NFS probes, DPU boundary simulation, and conformance reports.

- [ ] **Step 4: Verify**

Run: `bash tests/shell/test_x12again_reimage_coherent_scale.sh`
Expected: PASS.

### Task 4: Publish Branch

**Files:**
- All files changed above.

- [ ] **Step 1: Run final verification**

Run: `git diff --check && bash tests/shell/run-tests.sh`
Expected: PASS.

- [ ] **Step 2: Commit and push**

Run:

```bash
git add docs gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions tests/shell
git commit -m "Plan X12AGAIN coherent scale host profile"
git push -u origin codex/x12again-reimage-coherent-scale
```

- [ ] **Step 3: Open stacked PR**

Open the PR against `codex/slurm-pilot-control-plane` unless PR #119 has already merged; if #119 has merged, rebase onto the integration branch before opening.

---

Self-review:

- Spec coverage: X12AGAIN reimage, workstation+Xen host role, BlueField2/RDMA, SLURM admission, Project Coherent scale model, backup/backout, and testability are covered.
- Placeholder scan: no implementation step depends on an unspecified file path or unnamed command.
- Dependency handling: X12AGAIN is not added to active live `slurm_workers`; admission is gated by E2ET.
