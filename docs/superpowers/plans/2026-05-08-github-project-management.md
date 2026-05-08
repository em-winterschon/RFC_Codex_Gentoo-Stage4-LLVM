# GitHub Project Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repo-native GitHub issue templates, milestone/label catalogs, issue seed data, and a dry-run-first CLI tool to bootstrap Issues, Milestones, and a Project board from the current roadmap.

**Architecture:** Keep project-management source-of-truth under `project-management/` and render GitHub mutations through one local Python CLI. Use GitHub CLI/API only when `--apply` is explicitly supplied. Do not add GitHub Actions or billable workflows.

**Tech Stack:** GitHub issue forms YAML, Python 3 with PyYAML, `gh api`, shell tests, existing docs/wiki conventions.

---

## File Structure

- Create `.github/ISSUE_TEMPLATE/config.yml` to define template chooser behavior and query-param helper links.
- Create `.github/ISSUE_TEMPLATE/roadmap_task.yml` for roadmap/TODO work items.
- Create `.github/ISSUE_TEMPLATE/change_control.yml` for ITIL-style changes.
- Create `.github/ISSUE_TEMPLATE/service_role.yml` for machine/VM/container service-role work.
- Create `.github/ISSUE_TEMPLATE/blocker.yml` for operational blockers.
- Create `project-management/labels.yml` as the label catalog.
- Create `project-management/milestones.yml` as the milestone catalog.
- Create `project-management/issue-seed.yml` as the initial issue seed list.
- Create `scripts/github_project_seed.py` as the dry-run/apply CLI.
- Create `tests/shell/test_github_project_management.sh` for local structure and dry-run validation.
- Create `docs/GITHUB-PROJECT-MANAGEMENT.md` and `docs/wiki/GitHub-Project-Management.md` for usage docs.
- Modify `docs/CHANGELOG.md`, `docs/ROADMAP-AND-TODO.md`, and `docs/wiki/_Sidebar.md` to reference the workflow.

## Task 1: Issue Forms And Catalogs

**Files:**
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/ISSUE_TEMPLATE/roadmap_task.yml`
- Create: `.github/ISSUE_TEMPLATE/change_control.yml`
- Create: `.github/ISSUE_TEMPLATE/service_role.yml`
- Create: `.github/ISSUE_TEMPLATE/blocker.yml`
- Create: `project-management/labels.yml`
- Create: `project-management/milestones.yml`
- Create: `project-management/issue-seed.yml`

- [ ] **Step 1: Write issue forms and catalogs**

Add structured issue forms with required roadmap ID, area, status, dependency, and removal-condition fields. Add labels covering `type:*`, `area:*`, `status:*`, and `priority:*`. Add milestones for the active roadmap lanes.

- [ ] **Step 2: Validate YAML syntax with Python**

Run: `python3 - <<'PY'
import pathlib, yaml
for path in pathlib.Path('.github/ISSUE_TEMPLATE').glob('*.yml'):
    yaml.safe_load(path.read_text())
for path in pathlib.Path('project-management').glob('*.yml'):
    yaml.safe_load(path.read_text())
print('yaml-ok')
PY`

Expected: `yaml-ok`

## Task 2: Seed CLI

**Files:**
- Create: `scripts/github_project_seed.py`
- Create: `tests/shell/test_github_project_management.sh`

- [ ] **Step 1: Write failing shell test**

The test must assert the script exists, supports `--dry-run`, emits planned labels/milestones/issues, includes query URLs, and refuses mutation without `--apply`.

- [ ] **Step 2: Run the test and verify it fails before implementation**

Run: `bash tests/shell/test_github_project_management.sh`

Expected: FAIL because `scripts/github_project_seed.py` does not exist.

- [ ] **Step 3: Implement CLI**

Implement argparse flags: `--repo`, `--labels`, `--milestones`, `--issues`, `--project-title`, `--apply`, `--create-project`, and `--emit-query-urls`. Use `gh api` only inside apply paths. Print a deterministic dry-run summary.

- [ ] **Step 4: Run the test and verify it passes**

Run: `bash tests/shell/test_github_project_management.sh`

Expected: `PASS: test_github_project_management.sh`

## Task 3: Documentation And Wiki Mirror

**Files:**
- Create: `docs/GITHUB-PROJECT-MANAGEMENT.md`
- Create: `docs/wiki/GitHub-Project-Management.md`
- Modify: `docs/wiki/_Sidebar.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/ROADMAP-AND-TODO.md`

- [ ] **Step 1: Document usage**

Document template chooser URLs, query-parameter issue URLs, dry-run/apply commands, milestone catalog behavior, project board behavior, and the no-GitHub-Actions constraint.

- [ ] **Step 2: Mirror docs to wiki**

Copy the operational doc to `docs/wiki/GitHub-Project-Management.md` and add it to `_Sidebar.md`.

- [ ] **Step 3: Update changelog and roadmap**

Add a changelog entry and a roadmap item for GitHub project management bootstrap.

## Task 4: Verification And GitHub Apply

**Files:**
- All files above

- [ ] **Step 1: Run targeted tests**

Run:

```bash
git diff --check
bash tests/shell/test_github_project_management.sh
python3 -m py_compile scripts/github_project_seed.py
```

Expected: all exit 0.

- [ ] **Step 2: Run GitHub dry-run with token**

Run:

```bash
GH_TOKEN="$(cat /root/.ssh/codex.d/tokens/FORGE_TOKEN)" \
  python3 scripts/github_project_seed.py --repo em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM --emit-query-urls
```

Expected: deterministic plan output and no GitHub mutations.

- [ ] **Step 3: Apply labels, milestones, and seed issues**

Run only after dry-run review:

```bash
GH_TOKEN="$(cat /root/.ssh/codex.d/tokens/FORGE_TOKEN)" \
  python3 scripts/github_project_seed.py --repo em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM --apply
```

Expected: created or updated labels and milestones; created missing seeded issues; existing issues are skipped by title. Project board creation requires a token with GitHub Projects v2 `project` / `read:project` scope and exits before project mutation when that scope is absent.

- [ ] **Step 4: Commit and push**

Run:

```bash
git add .github/ISSUE_TEMPLATE project-management scripts/github_project_seed.py tests/shell/test_github_project_management.sh docs/GITHUB-PROJECT-MANAGEMENT.md docs/wiki/GitHub-Project-Management.md docs/wiki/_Sidebar.md docs/CHANGELOG.md docs/ROADMAP-AND-TODO.md docs/superpowers/plans/2026-05-08-github-project-management.md
git commit -m "Add GitHub project management scaffolding"
git push -u origin codex/github-project-management
```

Expected: commit succeeds and branch is pushed.
