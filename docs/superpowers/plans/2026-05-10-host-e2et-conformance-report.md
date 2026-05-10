# Host E2ET Conformance Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first repo-native host E2ET conformance report tool for RFC99 host acceptance runs.

**Architecture:** Add one dependency-light Python CLI that reads a JSON/YAML host E2ET manifest, evaluates acceptance gates, computes hard-fail and conformance-tier state, and writes JSON, Markdown, and JUnit reports. Add one Ansible playbook wrapper and one K10 sample manifest to make the workflow operational.

**Tech Stack:** Python 3 standard library, optional PyYAML for YAML manifests, Ansible command wrapper, shell regression tests.

---

### Task 1: Regression Test

**Files:**
- Create: `tests/shell/test_host_e2et_conformance_report.sh`
- Modify: `tests/shell/run-tests.sh`

- [ ] **Step 1: Write the failing test**

Create a shell test that builds a temporary JSON manifest with pass, fail, warn, and skip checks. It must call `scripts/host_e2et_conformance.py`, request JSON, Markdown, and JUnit outputs, and assert that:

```text
e2et_pass=false
hard failure includes Identity Gate / SSSD IPA backend
current tier is below-p60
recommended release state is blocked
Markdown includes RFC99 Host E2ET Conformance Report
JUnit contains testsuite and testcase XML
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
bash tests/shell/test_host_e2et_conformance_report.sh
```

Expected: fail because `scripts/host_e2et_conformance.py` does not exist.

### Task 2: Python CLI

**Files:**
- Create: `scripts/host_e2et_conformance.py`
- Test: `tests/shell/test_host_e2et_conformance_report.sh`

- [ ] **Step 1: Implement manifest loading**

Support JSON always and YAML when PyYAML is installed. Reject manifests whose top-level document is not a mapping.

- [ ] **Step 2: Implement gate/check evaluation**

Accept `gates[]` with `name`, `weight`, `hard_required`, and `checks[]`. Valid check statuses are `pass`, `fail`, `warn`, and `skip`. `fail` under a hard-required gate or with `hard_fail=true` blocks E2ET.

- [ ] **Step 3: Implement scoring**

Compute weighted score from non-skipped checks. Map score to tiers:

```text
<60 below-p60
60 p60
80 p80
90 p90
95 p95
99 p99
```

Any hard failure forces `recommended_release_state=blocked`.

- [ ] **Step 4: Implement outputs**

Support `--json-output`, `--markdown-output`, and `--junit-output`. Also print JSON to stdout when no output path is provided.

- [ ] **Step 5: Run the regression**

Run:

```bash
bash tests/shell/test_host_e2et_conformance_report.sh
```

Expected: pass.

### Task 3: Ansible Wrapper And Sample Manifest

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/host-e2et-conformance-report.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/host-e2et-definitions/k10-stage5-aaa-reboot.yml`
- Test: `tests/shell/test_host_e2et_conformance_report.sh`

- [ ] **Step 1: Add wrapper playbook**

Run the Python CLI from localhost with variables for manifest path and report output directory.

- [ ] **Step 2: Add K10 sample manifest**

Model K10 as blocked after AP7901 reboot because `aaa-domain-client` is not yet present in the durable rootfs.

- [ ] **Step 3: Extend regression**

Assert that the playbook and sample manifest exist and contain K10, `aaa-domain-client`, and the output variables.

### Task 4: Docs And Verification

**Files:**
- Modify: `docs/HOST-E2ET-ACCEPTANCE.md`
- Modify: `docs/wiki/Host-E2ET-Acceptance.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/wiki/Changelog.md`

- [ ] **Step 1: Document report tooling**

Add command examples for JSON, Markdown, and JUnit outputs.

- [ ] **Step 2: Update roadmap**

Mark `E2ET-002` active or completed according to implementation result.

- [ ] **Step 3: Run verification**

Run:

```bash
bash tests/shell/test_host_e2et_conformance_report.sh
bash tests/shell/run-tests.sh
git diff --check
```

Expected: all pass.

- [ ] **Step 4: Commit and push**

Commit:

```bash
git add docs gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible scripts tests
git commit -m "Add host E2ET conformance reporting"
git push origin codex/container-services-delta
```
