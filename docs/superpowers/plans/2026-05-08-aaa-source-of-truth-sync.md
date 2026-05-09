# AAA Source Of Truth Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repo-safe identity source-of-truth layer that validates and renders FreeIPA/FreeRADIUS sync plans.

**Architecture:** Store non-secret identity state in YAML, validate it with a dependency-light Python script, and render deterministic sync-plan JSON for future apply playbooks. Secrets remain in Ansible Vault and are referenced only by variable name.

**Tech Stack:** Bash shell tests, Python 3, PyYAML, Ansible playbook syntax checks, existing Gentoo Stage4 Ansible tree.

---

### Task 1: Add Failing Regression

**Files:**
- Create: `tests/shell/test_identity_source_of_truth.sh`
- Modify: `tests/shell/run-tests.sh`

- [x] Create a shell test that expects identity source files, validator, renderer, Ansible validation playbook, docs, and run-tests integration.
- [x] Run `bash tests/shell/test_identity_source_of_truth.sh`.
- [x] Confirm expected failure: missing `identity-source-definitions/local-rfc1918.yml`.

### Task 2: Add Source Definition And Validator

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/identity-source-definitions/local-rfc1918.yml`
- Create: `scripts/validate_identity_source.py`

- [x] Add non-secret RFC1918 identity desired state with groups, users, service accounts, K10 host enrollment, and AP7901 RADIUS client.
- [x] Implement validation for top-level schema, duplicate users/groups, duplicate UID/GID values, unknown group references, host enrollment references, RADIUS client secret hygiene, and count summaries.
- [x] Run `python3 scripts/validate_identity_source.py .../local-rfc1918.yml --format json`.
- [x] Confirm invalid fixture failures for duplicate GID, unknown primary group, and plaintext RADIUS secret.

### Task 3: Add Sync-Plan Renderer And Playbook

**Files:**
- Create: `scripts/render_identity_sync_plan.py`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/identity-source-validate.yml`

- [x] Implement `render_identity_sync_plan()` to emit `freeipa_groups`, `freeipa_users`, `freeipa_service_accounts`, `freeipa_host_enrollments`, `freeradius_clients`, and `rollout_gates`.
- [x] Add a local Ansible playbook that runs the validator and renderer without mutating FreeIPA or FreeRADIUS.
- [x] Run `ansible-playbook --syntax-check` when Ansible is available.

### Task 4: Document And Verify

**Files:**
- Modify: `docs/IDENTITY-AAA.md`
- Modify: `docs/wiki/Identity-AAA.md`
- Modify: `tests/shell/run-tests.sh`

- [x] Document the source-of-truth model, vault boundary, and first rollout targets.
- [x] Add `test_identity_source_of_truth.sh` to the full shell harness.
- [x] Run targeted tests and `git diff --check`.
- [x] Commit the completed scaffold.
