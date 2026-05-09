# MCP Control Plane Services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated MCP control-plane service scaffold with Nginx-UI and generic MCP backend support behind HAProxy.

**Architecture:** Reuse the existing container-services VM pattern. Add focused container app roles that register runtime apps, extend HAProxy routing for MCP-safe host/path routing, and document vault-only secret handling.

**Tech Stack:** Ansible roles, YAML service profiles, HAProxy, Podman, shell tests, Jinja2 render tests.

---

### Task 1: Add Failing Regression

**Files:**
- Create: `tests/shell/test_mcp_control_plane_services.sh`
- Modify: `tests/shell/run-tests.sh`

- [x] Add shell regression coverage for profile files, roles, install-sequence wiring, HAProxy MCP routing, docs, and run-tests integration.
- [x] Run `bash tests/shell/test_mcp_control_plane_services.sh`.
- [x] Confirm expected failure before implementation.

### Task 2: Add MCP Profile And App Roles

**Files:**
- Create: `profile-definitions/vm-mcp-control-plane.yml`
- Create: `profile-definitions/vm-mcp-control-plane.metadata.yml`
- Create: `roles/container_app_nginx_ui/defaults/main.yml`
- Create: `roles/container_app_nginx_ui/tasks/main.yml`
- Create: `roles/container_app_mcp_generic/defaults/main.yml`
- Create: `roles/container_app_mcp_generic/tasks/main.yml`
- Modify: `playbooks/install.yml`
- Modify: `vars/install_sequences.yml`

- [x] Define the `vm-mcp-control-plane` profile with Nginx-UI enabled, generic MCP disabled, HAProxy enabled, LAN-only hostnames, and vault variable references.
- [x] Add `container_app_nginx_ui` to create persistent directories and register the runtime app.
- [x] Add `container_app_mcp_generic` to register an optional configurable MCP backend only when enabled.
- [x] Wire both roles before HAProxy in the default install role ordering and modular install sequences.

### Task 3: Add HAProxy MCP Routing

**Files:**
- Modify: `roles/container_app_haproxy/templates/haproxy.cfg.j2`

- [x] Add host/path routing for Nginx-UI and generic MCP backends.
- [x] Disable request logging on MCP frontends or routes that may carry `node_secret`.
- [x] Preserve existing ntfy/nginx fallback behavior.

### Task 4: Document And Verify

**Files:**
- Create: `docs/MCP-CONTROL-PLANE.md`
- Create: `docs/wiki/MCP-Control-Plane.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: `docs/wiki/Roadmap-and-TODO.md`
- Modify: `tests/shell/run-tests.sh`

- [x] Document topology, vault variables, live gates, HAProxy exposure, and Nginx-UI MCP/OpenAI configuration.
- [x] Add roadmap task tracking for MCP control-plane live deployment.
- [x] Run targeted MCP tests, container service tests, and `git diff --check`.
- [x] Commit the completed scaffold.
