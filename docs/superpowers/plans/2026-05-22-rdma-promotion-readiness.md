# RDMA Promotion Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define one repo-native RDMA promotion gate spanning RDMA-002 (#117), RDMA-003 (#111), and FMT2-007 (#130).

**Architecture:** Add a machine-readable workflow manifest that models storage-client baseline, vendor-driver convergence, FMT2 fabric admission, protocol smoke, failure injection, and closeout. Add a small validator that reads the manifest, enforces safety invariants, and reports which issues are complete versus still live-gated.

**Tech Stack:** Bash tests, Python 3, PyYAML, existing docs/workflows and tests/shell conventions.

---

### Task 1: Add RDMA Promotion Readiness Contract

**Files:**
- Create: `docs/workflows/rdma-fabric-promotion-readiness.yml`
- Create: `scripts/validate-rdma-promotion-readiness.py`
- Create: `tests/shell/test_rdma_promotion_readiness.sh`
- Modify: `tests/shell/run-tests.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/shell/test_rdma_promotion_readiness.sh` requiring the manifest and validator, issue IDs `111`, `117`, `130`, safety defaults, production blockers, and closeable state for `RDMA-002`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/shell/test_rdma_promotion_readiness.sh`
Expected: `FAIL: missing file ... docs/workflows/rdma-fabric-promotion-readiness.yml`

- [ ] **Step 3: Write minimal implementation**

Create the workflow manifest and validator. The validator must parse YAML, reject missing issue IDs or unsafe mutation defaults, print JSON summary by default, and exit non-zero with `--enforce-production-ready` while production blockers remain.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/shell/test_rdma_promotion_readiness.sh`
Expected: `PASS: test_rdma_promotion_readiness.sh`

### Task 2: Wire Documentation And Roadmap

**Files:**
- Create: `docs/RDMA-PROMOTION-READINESS.md`
- Create: `docs/wiki/RDMA-Promotion-Readiness.md`
- Modify: `docs/RDMA-STORAGE-FABRIC-PLAN.md`
- Modify: `docs/NFS-STORAGE-CLIENT.md`
- Modify: `docs/wiki/NFS-Storage-Client.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`

- [ ] **Step 1: Update docs from the manifest**

Document that #117 is baseline-defined and closeable after merge, while #111 and #130 remain blocked by live OFED/DOCA, Arista, pairwise smoke, and failure-injection evidence.

- [ ] **Step 2: Run focused tests**

Run: `bash tests/shell/test_rdma_promotion_readiness.sh && bash tests/shell/test_nfs_storage_client_profile.sh && bash tests/shell/test_nvidia_doca_ofed_role.sh && bash tests/shell/test_fmt2_r630_arista_fabric_policy.sh`
Expected: all pass.

### Task 3: Validate, Commit, And Publish

**Files:**
- All files from Tasks 1 and 2.

- [ ] **Step 1: Run validation**

Run: `pre-commit run shfmt --all-files && pre-commit run ruff --all-files && pre-commit run black --all-files && bash tests/shell/run-tests.sh && git diff --check`
Expected: all pass.

- [ ] **Step 2: Commit and open PR**

Run:

```bash
git add docs/RDMA-PROMOTION-READINESS.md docs/wiki/RDMA-Promotion-Readiness.md docs/workflows/rdma-fabric-promotion-readiness.yml scripts/validate-rdma-promotion-readiness.py tests/shell/test_rdma_promotion_readiness.sh tests/shell/run-tests.sh docs/RDMA-STORAGE-FABRIC-PLAN.md docs/NFS-STORAGE-CLIENT.md docs/wiki/NFS-Storage-Client.md docs/ROADMAP-AND-TODO.md docs/wiki/Roadmap-and-TODO.md docs/superpowers/plans/2026-05-22-rdma-promotion-readiness.md
git commit -m "Add RDMA promotion readiness gate"
git push -u origin codex/rdma-promotion-readiness
```

Open a draft PR and watch GitHub Actions.
