# FMT2 Infra Evidence Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the old SFO-200/FMT2 wiki as evidence and convert it into verified NetBox/IPAM/DCIM planning inputs without treating stale data as authoritative.

**Architecture:** Add a dedicated FMT2 planning document that maps legacy source pages to validation tasks. Cross-link it from Check_MK transport, roadmap, changelog, and wiki navigation so the old repo can guide future automation while live validation remains the authority.

**Tech Stack:** Markdown documentation, repo wiki mirror under `docs/wiki`, existing shell validation suite.

---

### Task 1: Add FMT2 Planning Document

**Files:**

- Create: `docs/FMT2-INFRA-UPGRADE-PLANNING.md`
- Create: `docs/wiki/FMT2-Infra-Upgrade-Planning.md`

- [x] **Step 1:** Create the planning document with source repo path, commit, aliases, evidence-handling rules, high-value source map, inferred topology, NetBox intake targets, access methods, and validation gates.
- [x] **Step 2:** Copy the same content into the wiki mirror file.

### Task 2: Wire Existing Docs

**Files:**

- Modify: `docs/FMT2-CHECKMK-TRANSPORT.md`
- Modify: `docs/wiki/FMT2-CheckMK-Transport.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/wiki/Changelog.md`
- Modify: `docs/wiki/Home.md`
- Modify: `docs/wiki/_Sidebar.md`

- [x] **Step 1:** Add the new planning doc to wiki navigation.
- [x] **Step 2:** Add a legacy-evidence dependency section to the FMT2 Check_MK transport doc.
- [x] **Step 3:** Add roadmap tasks for FMT2 evidence consolidation, NetBox verification, transport validation, and Check_MK integration.
- [x] **Step 4:** Add a changelog entry for the evidence integration.

### Task 3: Verify and Publish

**Files:**

- Read-only validation across the repo.

- [x] **Step 1:** Run `git diff --check`.
- [x] **Step 2:** Run `bash tests/shell/run-tests.sh`.
- [x] **Step 3:** Commit the FMT2 planning changes.
- [x] **Step 4:** Push the branch and publish the wiki if checks pass.
