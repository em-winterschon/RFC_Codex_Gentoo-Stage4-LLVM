# Trac Project Management Control Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repo-native scaffolding for a Trac-backed project-management control plane with an MCP bridge, HAProxy publication intent, identity integration intent, docs, and regression tests.

**Architecture:** Trac is modeled as a persistent Stage5 VM service backed by PostgreSQL and published by HAProxy. The MCP bridge is a separate service role so third-party or local bridge implementations can be swapped without changing Trac runtime state. Tests assert declarative profile, workflow, custom-field, and documentation invariants.

**Tech Stack:** Ansible roles, Gentoo Stage5 profile definitions, OpenRC templates, Trac, PostgreSQL, HAProxy, FreeIPA/SSSD integration intent, shell regression tests.

---

### Task 1: Add Trac Design Documentation

**Files:**
- Create: `docs/PROJECT-MANAGEMENT-CONTROL-PLANE.md`
- Create: `docs/wiki/Project-Management-Control-Plane.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/wiki/Changelog.md`

- [ ] **Step 1: Write docs**

Create docs explaining Trac as authoritative Kanban, GitHub/Codeberg as linked Git surfaces, workflow states, custom fields, service dependencies, and non-goals.

- [ ] **Step 2: Verify docs contain core terms**

Run:

```bash
rg -n "Trac|MCP|GitHub|Codeberg|intake|validation|rfc1918-platform-fabric" docs/PROJECT-MANAGEMENT-CONTROL-PLANE.md docs/wiki/Project-Management-Control-Plane.md
```

Expected: every command match appears in both docs.

### Task 2: Add Stage5 Trac Profile

**Files:**
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-package-lists/stage5-virtual-host-trac-service.packages`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-trac-service.yml`
- Create: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/vm-trac-service.metadata.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/vars/install_sequences.yml`

- [ ] **Step 1: Add package list**

Include Trac, PostgreSQL, Python virtualenv/pip tooling, HAProxy/nginx support, Git, rsyslog, curl, and metrics primitives.

- [ ] **Step 2: Add profile definition**

Define `trac_server.enabled`, `trac_mcp_bridge.enabled`, HAProxy service type `trac-http`, rsyslog forwarding, OpenRC services, Trac workflow states, and custom fields.

- [ ] **Step 3: Add metadata**

Record Trac authority model, GitHub/Codeberg link policy, identity dependency, and plugin caution.

- [ ] **Step 4: Wire install sequence**

Add `trac_server` and `trac_mcp_bridge` after base service and identity-adjacent roles without changing existing profile behavior unless the profile enables them.

### Task 3: Add Trac Server Role

**Files:**
- Create directory: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/trac_server/`
- Create: `defaults/main.yml`
- Create: `tasks/main.yml`
- Create: `templates/trac.ini.j2`
- Create: `templates/trac.openrc.j2`
- Create: `templates/trac-workflow.ini.j2`
- Create: `templates/trac-custom-fields.ini.j2`

- [ ] **Step 1: Add defaults**

Defaults must disable the role unless the profile enables it. Include service user/group, env path, project path, listen host/port, database URL placeholder, workflow list, custom fields, LDAP/FreeIPA intent, and notification settings.

- [ ] **Step 2: Add tasks**

Tasks should resolve settings, create service user/group, create directories, render templates, render OpenRC service, and append `tracd` to `resolved_profile_openrc_services_enable` only when enabled.

- [ ] **Step 3: Add templates**

Templates render deterministic Trac settings, workflow transitions, custom fields, and an OpenRC script that runs `tracd`.

### Task 4: Add Trac MCP Bridge Role

**Files:**
- Create directory: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/trac_mcp_bridge/`
- Create: `defaults/main.yml`
- Create: `tasks/main.yml`
- Create: `templates/trac-mcp.env.j2`
- Create: `templates/trac-mcp.openrc.j2`

- [ ] **Step 1: Add defaults**

Defaults must disable the bridge unless enabled by profile. Include listen host/port, Trac base URL, token variable name, implementation mode (`third_party` or `local_adapter`), and mutation allowlist.

- [ ] **Step 2: Add tasks**

Tasks should create user/group, create config/log dirs, render env and OpenRC service, and append `trac-mcp` to OpenRC enable list when enabled.

- [ ] **Step 3: Add templates**

OpenRC should source `/etc/trac-mcp/trac-mcp.env` and run a configured command. The env template must reference vault variable names, not plaintext tokens.

### Task 5: Add Tests And Run Verification

**Files:**
- Create: `tests/shell/test_trac_control_plane_roles.sh`
- Modify: `tests/shell/run-tests.sh`
- Modify: `tests/shell/test_system_profiles.sh`

- [ ] **Step 1: Add role/profile test**

The test should assert required files exist, profile contains `vm-trac-service`, package list contains Trac/PostgreSQL/HAProxy/Git, templates contain workflow/custom field values, and MCP bridge env references vault variables.

- [ ] **Step 2: Register shell test**

Add `test_trac_control_plane_roles.sh` to `tests/shell/run-tests.sh`.

- [ ] **Step 3: Extend system profile test**

Assert the Trac profile, metadata, and package list are present.

- [ ] **Step 4: Run verification**

Run:

```bash
git diff --check
bash tests/shell/test_trac_control_plane_roles.sh
bash tests/shell/test_system_profiles.sh
bash -n tests/shell/test_trac_control_plane_roles.sh
```

Expected: all commands exit 0.

### Task 6: Commit And Push

**Files:**
- All changed files.

- [ ] **Step 1: Check status**

Run:

```bash
git status --short
```

Expected: only Trac control-plane files are modified or added.

- [ ] **Step 2: Commit**

Run:

```bash
git add docs gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible tests/shell
git commit -m "Add Trac project management control plane"
```

- [ ] **Step 3: Push**

Run:

```bash
git push origin codex/trac-control-plane
```

Expected: branch is pushed for PR creation.
