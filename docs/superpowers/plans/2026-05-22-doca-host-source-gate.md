# DOCA Host Source Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert #111 from a generic OFED/DOCA placeholder into a tested DOCA Host source gate for BlueField-2 and ConnectX-5.

**Architecture:** Add a machine-readable source-of-truth manifest, extend the existing `nvidia_doca_ofed` role instead of creating a parallel role, and keep all live mutation blocked by explicit apply variables. Retain ConnectX-4 as diagnostic-only unless a later live preflight promotes it by change control.

**Tech Stack:** Ansible, Rocky/RHEL `dnf`, NVIDIA DOCA Host RPM repository packages, DKMS/kernel headers, shell regression tests, NFS-backed artifact publication.

---

### Task 1: Add the Source Gate

**Files:**
- Create: `docs/workflows/doca-host-source-of-truth.yml`
- Create: `docs/RDMA-DOCA-HOST-SOURCE-GATE.md`
- Create: `docs/wiki/RDMA-DOCA-Host-Source-Gate.md`
- Create: `tests/shell/test_doca_host_source_gate.sh`
- Modify: `tests/shell/run-tests.sh`

- [ ] **Step 1: Write the failing test**

Run:

```bash
bash tests/shell/test_doca_host_source_gate.sh
```

Expected: fail because the source gate files do not exist.

- [ ] **Step 2: Add the manifest and docs**

Create `docs/workflows/doca-host-source-of-truth.yml` with DOCA Host `3.3.0`, Rocky Linux 10 kernel `6.12.0-124.8.1.el10_1.x86_64`, kernel.org 6.18 `doca-ofed-only`, and ConnectX-4 `legacy-diagnostic-only`.

- [ ] **Step 3: Verify**

Run:

```bash
bash tests/shell/test_doca_host_source_gate.sh
```

Expected: pass after the role and builder changes below are complete.

### Task 2: Extend the Role Contract

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nvidia_doca_ofed/defaults/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/nvidia_doca_ofed/tasks/main.yml`

- [ ] **Step 1: Add RPM and support-matrix defaults**

Add `nvidia_doca_ofed_repo_package_type`, RPM URL/path/checksum variables, DOCA Host version, supported kernel target metadata, and ConnectX-4 diagnostic policy.

- [ ] **Step 2: Add RPM apply path**

Keep read-only preflight unchanged. For live apply, require `nvidia_doca_ofed_repo_package_type` to be `deb` or `rpm`; use `apt` for `deb` and `dnf` for `rpm`.

- [ ] **Step 3: Verify role tests**

Run:

```bash
bash tests/shell/test_nvidia_doca_ofed_role.sh
bash tests/shell/test_doca_host_source_gate.sh
```

Expected: both pass.

### Task 3: Extend Artifact Publication

**Files:**
- Modify: `scripts/fmt2-build-mlnx-ofed-rhel-kernel.sh`
- Modify: `tests/shell/test_fmt2_mlnx_ofed_rhel_kernel_builder.sh`

- [ ] **Step 1: Add DOCA artifact variables**

Add `DOCA_HOST_VERSION`, `DOCA_HOST_ARTIFACT_ROOT`, `PUBLISH_DIR`, and a `publish-artifacts` safety-gated action.

- [ ] **Step 2: Verify builder tests**

Run:

```bash
bash tests/shell/test_fmt2_mlnx_ofed_rhel_kernel_builder.sh
```

Expected: pass.

### Task 4: Closeout Validation

**Files:**
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`
- Modify: `docs/RDMA-STORAGE-FABRIC-PLAN.md`

- [ ] **Step 1: Update references**

Point #111 at `docs/workflows/doca-host-source-of-truth.yml`, mark Rocky Linux 10 as the primary current lane, and keep ConnectX-4 diagnostic-only.

- [ ] **Step 2: Run validation**

Run:

```bash
bash tests/shell/test_doca_host_source_gate.sh
bash tests/shell/test_nvidia_doca_ofed_role.sh
bash tests/shell/test_fmt2_mlnx_ofed_rhel_kernel_builder.sh
bash tests/shell/test_rdma_promotion_readiness.sh
pre-commit run shfmt --all-files
pre-commit run ruff --all-files
pre-commit run black --all-files
git diff --check
```

Expected: all pass.
